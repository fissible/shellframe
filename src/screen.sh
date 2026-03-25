#!/usr/bin/env bash
# shellframe/src/screen.sh — Alternate screen and terminal state management
#
# COMPATIBILITY: bash 3.2+ (macOS default). All sequences are raw ANSI/VT100
# rather than tput, because tput capabilities (smcup, rmcup, civis, cnorm,
# clear) may exit 0 without producing output on misconfigured TERM values.
#
# GOTCHA: write sequences to the real terminal fd, not stdout, in case stdout
# has been redirected. Use shellframe_screen_enter/exit together so the alternate
# screen buffer is always properly restored on exit.

# ── Alternate screen ─────────────────────────────────────────────────────────

# Switch to the alternate screen buffer (a separate framebuffer with no
# scrollback). This is what less, vim, top, etc. all do. The caller's terminal
# content is hidden but preserved — shellframe_screen_exit restores it exactly.
shellframe_screen_enter() {
    # Open a persistent fd to /dev/tty so widgets can write to >&3 instead
    # of >/dev/tty (which opens+closes the file on every write and eventually
    # exhausts file descriptors under rapid scrolling).
    exec 3>/dev/tty
    printf '\033[?1049h' >&3     # enable alternate screen buffer
    printf '\033[H\033[3J\033[2J' >&3  # cursor home + clear screen + clear scrollback
}

shellframe_screen_exit() {
    printf '\033[?1049l' >&3  # disable alternate screen buffer (restores prior content)
    exec 3>&-                  # close the persistent fd
}

# Clear the current screen and move cursor to top-left. Call at the start of
# each redraw cycle inside the alternate screen.
#
# RENDERING STRATEGY — full redraw (current):
#   Every frame calls shellframe_screen_clear, then every widget re-renders
#   its full region to /dev/tty. Simple, correct, and fast enough for typical
#   80×24 TUIs. The cost is visible flicker on slow connections and unnecessary
#   work when only one widget changes.
#
# ROADMAP — two-stage migration to diff rendering (Phase 7, shellframe):
#
#   Stage 1 — Dirty-region tracking (Phase 7 task B, GH #23):
#     Each widget gains a dirty flag. The app render loop skips
#     shellframe_screen_clear and only calls render on dirty widgets.
#     Render functions still write directly to /dev/tty. No API break.
#     Captures ~80% of the benefit with minimal change.
#
#   Stage 2 — Full per-cell framebuffer diff (Phase 7 task F, GH #TBD):
#     A flat indexed array _SF_FRAME_CURR[row*COLS+col] (and _PREV mirror)
#     acts as a virtual screen. All render functions write to the framebuffer
#     instead of /dev/tty — a mechanical but pervasive change touching
#     panel.sh, draw.sh, and every widget. shellframe_screen_flush() diffs
#     current vs prev and emits \033[row;colH + char only for changed cells.
#     This is the "right" long-term answer: eliminates flicker entirely and
#     makes large-TUI performance independent of unchanged regions.
#     Depends on Stage 1 being stable first.
shellframe_screen_clear() {
    printf '\033[H\033[3J\033[2J' >&3
    # \033[H   — cursor home (top-left)
    # \033[3J  — erase saved lines (clears scrollback so the scrollbar
    #            doesn't shrink on each redraw)
    # \033[2J  — erase entire visible screen
}

# ── Cursor ───────────────────────────────────────────────────────────────────

shellframe_cursor_hide() { printf '\033[?25l' >&3; }
shellframe_cursor_show() { printf '\033[?25h' >&3; }

# ── Mouse reporting ───────────────────────────────────────────────────────────
#
# Enable/disable SGR mouse reporting (\033[?1006h).  Must be called alongside
# shellframe_screen_enter/exit so mouse events are cleanly disabled on exit.
# SGR mode (1006h) reports col/row as decimal integers, avoiding the 223-char
# limit of the older X10/X11 encoding.
#
# Requires \033[?1000h (X11 mouse tracking) to be enabled first; the two
# sequences are sent together here for convenience.
shellframe_mouse_enter() {
    printf '\033[?1000h\033[?1006h' >&3
}

shellframe_mouse_exit() {
    printf '\033[?1006l\033[?1000l' >&3
}

# ── Raw terminal mode ─────────────────────────────────────────────────────────
#
# GOTCHA: `read -s` only suppresses echo for the duration of a single `read`
# call. Between calls the terminal is back to its normal (echoing, canonical)
# state, which causes buffered escape-sequence bytes to echo visibly. Set the
# terminal to raw mode for the entire TUI session instead.
#
# Usage pattern:
#   local saved_stty
#   saved_stty=$(shellframe_raw_save)
#   shellframe_raw_enter
#   trap "shellframe_raw_exit '$saved_stty'; shellframe_screen_exit; exit 1" INT TERM
#   ...TUI loop...
#   shellframe_raw_exit "$saved_stty"

shellframe_raw_save()  { stty -g 2>/dev/null; }
shellframe_raw_enter() {
    stty -echo -icanon -icrnl min 1 time 0 2>/dev/null
    # Enable bracketed paste mode: terminal wraps pasted text in
    # ESC[200~ ... ESC[201~ so the editor can batch-insert it instantly.
    printf '\033[?2004h' >&3
}
# -icrnl: stop the tty from translating CR (\r) → NL (\n) on input.
# Without this, Enter arrives as \n, but bash's `read` strips trailing
# newlines and returns an empty string — so \n can never be matched.
shellframe_raw_exit()  {
    printf '\033[?2004l' >&3  # disable bracketed paste mode
    stty "$1" 2>/dev/null || true
}
