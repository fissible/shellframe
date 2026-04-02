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
#   Stage 2 — Row-based framebuffer (Phase 7 task F → GH #39 perf rewrite):
#     _SF_ROW_CURR / _SF_ROW_PREV per-row string arrays.  Each fb_* call
#     appends a cursor-positioned ANSI fragment — O(1), no per-char loops.
#     shellframe_screen_flush() diffs whole row strings and emits one printf
#     per changed row.  Standalone TUIs (alert, confirm, action-list, table)
#     manage their own fd 3 lifecycle and are intentionally excluded.
shellframe_screen_clear() {
    printf '\033[H\033[3J\033[2J' >&3
    # \033[H   — cursor home (top-left)
    # \033[3J  — erase saved lines (clears scrollback so the scrollbar
    #            doesn't shrink on each redraw)
    # \033[2J  — erase entire visible screen
    # Reset both framebuffer planes so the next flush does a full redraw.
    _SF_ROW_CURR=()
    _SF_ROW_PREV=()
    _SF_DIRTY_ROWS=()
}

# ── Framebuffer ──────────────────────────────────────────────────────────────
#
# Row-based virtual framebuffer.  All composable widget render functions write
# positioned ANSI fragments via shellframe_fb_put / shellframe_fb_print /
# shellframe_fb_fill.  Each call appends a cursor-positioned fragment to the
# row string — O(1), no per-character loops.  shellframe_screen_flush() diffs
# whole row strings and emits one printf per changed row.
#
# Row storage:
#   _SF_ROW_CURR[$row]   — accumulated positioned fragments for this frame
#   _SF_ROW_PREV[$row]   — last emitted row string (for diff)
#   _SF_DIRTY_ROWS[$row] — 1 for rows written this frame
#   Row indices are 1-based (matching terminal row coordinates).
#
# Frame lifecycle:
#   shellframe_fb_frame_start rows cols  — call at the top of every draw cycle
#   ... widget render functions write via fb_put / fb_print / fb_fill ...
#   shellframe_screen_flush              — emit only changed rows, swap buffers

_SF_ROW_CURR=()
_SF_ROW_PREV=()
_SF_DIRTY_ROWS=()
_SF_FRAME_ROWS=24
_SF_FRAME_COLS=80

# shellframe_fb_frame_start rows cols
#   Reset CURR and DIRTY for a new draw cycle.  PREV is untouched — it holds
#   the last committed state and is only cleared by shellframe_screen_clear.
shellframe_fb_frame_start() {
    _SF_FRAME_ROWS="${1:-24}"
    _SF_FRAME_COLS="${2:-80}"
    _SF_ROW_CURR=()
    _SF_DIRTY_ROWS=()
}

# shellframe_fb_put row col cell
#   Append a positioned single-cell fragment at (row, col).
shellframe_fb_put() {
    local _frag
    printf -v _frag '\033[%d;%dH%s' "$1" "$2" "$3"
    _SF_ROW_CURR[$1]+="$_frag"
    _SF_DIRTY_ROWS[$1]=1
}

# shellframe_fb_print row col str [prefix]
#   Append a positioned string fragment at (row, col).
#   prefix is prepended once (e.g. an ANSI highlight sequence).
shellframe_fb_print() {
    local _frag
    printf -v _frag '\033[%d;%dH%s%s' "$1" "$2" "${4:-}" "$3"
    _SF_ROW_CURR[$1]+="$_frag"
    _SF_DIRTY_ROWS[$1]=1
}

# shellframe_fb_fill row col n [char] [prefix]
#   Append a positioned fill fragment: n copies of char (default: space).
#   prefix is prepended once (e.g. a background colour sequence).
shellframe_fb_fill() {
    local _fill
    printf -v _fill '%*s' "$3" ''
    [[ "${4:- }" != " " ]] && _fill="${_fill// /${4}}"
    local _frag
    printf -v _frag '\033[%d;%dH%s%s' "$1" "$2" "${5:-}" "$_fill"
    _SF_ROW_CURR[$1]+="$_frag"
    _SF_DIRTY_ROWS[$1]=1
}

# shellframe_fb_print_ansi row col rendered_str
#   Append a positioned fragment containing a pre-assembled ANSI string.
#   Unlike the old cell-based version, no per-character parsing is needed —
#   the string is appended as-is with cursor positioning.
shellframe_fb_print_ansi() {
    local _frag
    printf -v _frag '\033[%d;%dH%s' "$1" "$2" "$3"
    _SF_ROW_CURR[$1]+="$_frag"
    _SF_DIRTY_ROWS[$1]=1
}

# shellframe_screen_flush
#   Diff CURR against PREV.  Emit \033[0m + row to fd 3 for every changed row.
#   Also handles erasures: rows present in PREV but absent in CURR are cleared.
#   Updates PREV in place; cleared rows are unset to keep PREV lean.
shellframe_screen_flush() {
    local _row

    # Erasure: rows in PREV but not written this frame
    for _row in "${!_SF_ROW_PREV[@]}"; do
        [[ -z "${_SF_ROW_CURR[$_row]+x}" ]] && _SF_DIRTY_ROWS[$_row]=1
    done

    for _row in "${!_SF_DIRTY_ROWS[@]}"; do
        local _curr="${_SF_ROW_CURR[$_row]:-}"
        local _prev="${_SF_ROW_PREV[$_row]:-}"
        if [[ "$_curr" != "$_prev" ]]; then
            if [[ -z "$_curr" ]]; then
                # Row was in PREV but nothing wrote to it — clear it
                printf '\033[%d;1H\033[0m%*s' "$_row" "$_SF_FRAME_COLS" '' >&3
                unset '_SF_ROW_PREV[$_row]'
            else
                printf '\033[0m%s' "$_curr" >&3
                _SF_ROW_PREV[$_row]="$_curr"
            fi
        fi
    done
    _SF_DIRTY_ROWS=()
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
