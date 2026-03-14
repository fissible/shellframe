#!/usr/bin/env bash
# clui/src/screen.sh — Alternate screen and terminal state management
#
# COMPATIBILITY: bash 3.2+ (macOS default). All sequences are raw ANSI/VT100
# rather than tput, because tput capabilities (smcup, rmcup, civis, cnorm,
# clear) may exit 0 without producing output on misconfigured TERM values.
#
# GOTCHA: write sequences to the real terminal fd, not stdout, in case stdout
# has been redirected. Use clui_screen_enter/exit together so the alternate
# screen buffer is always properly restored on exit.

# ── Alternate screen ─────────────────────────────────────────────────────────

# Switch to the alternate screen buffer (a separate framebuffer with no
# scrollback). This is what less, vim, top, etc. all do. The caller's terminal
# content is hidden but preserved — clui_screen_exit restores it exactly.
clui_screen_enter() {
    printf '\033[?1049h'  # enable alternate screen buffer
    printf '\033[H\033[2J' # cursor home + clear
}

clui_screen_exit() {
    printf '\033[?1049l'  # disable alternate screen buffer (restores prior content)
}

# Clear the current screen and move cursor to top-left. Call at the start of
# each redraw cycle inside the alternate screen.
clui_screen_clear() {
    printf '\033[H\033[2J'
}

# ── Cursor ───────────────────────────────────────────────────────────────────

clui_cursor_hide() { printf '\033[?25l'; }
clui_cursor_show() { printf '\033[?25h'; }

# ── Raw terminal mode ─────────────────────────────────────────────────────────
#
# GOTCHA: `read -s` only suppresses echo for the duration of a single `read`
# call. Between calls the terminal is back to its normal (echoing, canonical)
# state, which causes buffered escape-sequence bytes to echo visibly. Set the
# terminal to raw mode for the entire TUI session instead.
#
# Usage pattern:
#   local saved_stty
#   saved_stty=$(clui_raw_save)
#   clui_raw_enter
#   trap "clui_raw_exit '$saved_stty'; clui_screen_exit; exit 1" INT TERM
#   ...TUI loop...
#   clui_raw_exit "$saved_stty"

clui_raw_save()  { stty -g 2>/dev/null; }
clui_raw_enter() { stty -echo -icanon min 1 time 0 2>/dev/null; }
clui_raw_exit()  { stty "$1" 2>/dev/null || true; }
