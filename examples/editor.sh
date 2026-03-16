#!/usr/bin/env bash
# examples/editor.sh — Interactive multiline text editor using shellframe
#
# Usage: ./editor.sh [file]
#   With no arguments, starts with a blank buffer.
#   With a file argument, loads the file content for editing.
#   On Ctrl-D, exits and prints the final text to stdout.
#   On Ctrl-C / q (from outside focused field), exits without output.
#
# Keys:
#   ↑ ↓ ← →         — navigate
#   Home / End       — start / end of line
#   Ctrl-A / Ctrl-E  — start / end of line
#   Enter            — insert newline
#   Backspace        — delete before cursor; joins lines at col 0
#   Delete           — delete at cursor; joins lines at EOL
#   Ctrl-K           — kill to end of line
#   Ctrl-U           — kill to start of line
#   Ctrl-W           — kill word left
#   Ctrl-D           — submit (prints text to stdout, exits)
#   Ctrl-C           — quit without output

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

# ── Load initial content ───────────────────────────────────────────────────────

SHELLFRAME_EDITOR_LINES=()
if [[ "${1:-}" != "" && -f "$1" ]]; then
    while IFS= read -r _line; do
        SHELLFRAME_EDITOR_LINES+=("$_line")
    done < "$1"
fi

# ── Terminal setup ─────────────────────────────────────────────────────────────

saved_stty=$(shellframe_raw_save)

_editor_exit() {
    shellframe_raw_exit "$saved_stty"
    shellframe_cursor_show
    shellframe_screen_exit
}
trap '_editor_exit; exit 1' INT TERM

shellframe_screen_enter
shellframe_raw_enter
shellframe_cursor_hide

# ── Init widget ────────────────────────────────────────────────────────────────

SHELLFRAME_EDITOR_CTX="main"
SHELLFRAME_EDITOR_FOCUSED=1
shellframe_editor_init "main"

# ── Draw ───────────────────────────────────────────────────────────────────────

_cols=$(tput cols)
_rows=$(tput lines)

_draw() {
    local _cols _rows
    _cols=$(tput cols)
    _rows=$(tput lines)

    local _count
    _count=$(shellframe_editor_line_count "main")
    local _row
    _row=$(shellframe_editor_row "main")
    local _col
    _col=$(shellframe_editor_col "main")
    local _vtop
    _vtop=$(shellframe_editor_vtop "main")

    # Header bar (row 1)
    printf '\033[1;1H\033[2K' >/dev/tty
    printf '\033[7m%-*s\033[0m' "$_cols" \
        "  shellframe editor  |  row $(( _row + 1 ))/$_count  col $(( _col + 1 ))  |  Ctrl-D submit  Ctrl-C quit" \
        >/dev/tty

    # Editor body (rows 2 .. _rows-1)
    local _body_rows=$(( _rows - 2 ))
    shellframe_editor_render 2 1 "$_cols" "$_body_rows"

    # Footer bar (last row)
    printf '\033[%d;1H\033[2K' "$_rows" >/dev/tty
    printf '\033[2m%-*s\033[0m' "$_cols" \
        "  ↑↓←→ navigate  Enter newline  Bksp/Del delete  Ctrl-K/U/W kill  Ctrl-D submit" \
        >/dev/tty
}

_draw

# ── Input loop ─────────────────────────────────────────────────────────────────

result=""
while true; do
    local key
    shellframe_read_key key

    shellframe_editor_on_key "$key"
    local rc=$?

    if (( rc == 2 )); then
        # Ctrl-D: submit
        result="$SHELLFRAME_EDITOR_RESULT"
        break
    elif [[ "$key" == $'\x03' ]]; then
        # Ctrl-C: quit without output
        break
    fi

    _draw
done

_editor_exit
trap - INT TERM

[[ -n "$result" ]] && printf '%s\n' "$result"
