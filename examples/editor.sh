#!/usr/bin/env bash
# examples/editor.sh — Interactive multiline text editor using shellframe
#
# Usage: ./editor.sh [file]
#   With no arguments, starts with a blank buffer.
#   With a file argument, loads the file content for editing.
#   On Ctrl-D, exits and prints the final text to stdout.
#   On Ctrl-C, exits without output.
#
# Keys:
#   ↑ ↓ ← →         — navigate
#   Home / End       — start / end of line  (also Ctrl-A / Ctrl-E)
#   Enter            — insert newline
#   Backspace        — delete before cursor; joins lines at col 0
#   Delete           — delete at cursor;    joins lines at EOL
#   Ctrl-K           — clear to end of line
#   Ctrl-U           — clear to start of line
#   Ctrl-W           — clear last word
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
#
# All terminal escape sequences write to /dev/tty directly so they reach the
# real terminal even if stdout is redirected.  The result is printed to stdout
# after cleanup so callers can capture it with $().

saved_stty=$(shellframe_raw_save)

_cleanup() {
    shellframe_raw_exit "$saved_stty"
    printf '\033[?25h'  >/dev/tty   # show cursor
    printf '\033[?1049l' >/dev/tty  # exit alternate screen buffer
}
# EXIT fires on every exit path (normal, error, Ctrl-C).
# INT/TERM just trigger exit so the EXIT trap handles cleanup.
trap '_cleanup' EXIT
trap 'exit 1'   INT TERM

# Enter the TUI
printf '\033[?1049h\033[H\033[3J\033[2J' >/dev/tty  # alt screen + clear
printf '\033[?25l' >/dev/tty                         # hide cursor
shellframe_raw_enter

# ── Init widget ────────────────────────────────────────────────────────────────

SHELLFRAME_EDITOR_CTX="main"
SHELLFRAME_EDITOR_FOCUSED=1
shellframe_editor_init "main"

# ── Draw ───────────────────────────────────────────────────────────────────────

_draw() {
    local cols rows
    cols=$(tput cols)
    rows=$(tput lines)

    local count row col
    count=$(shellframe_editor_line_count "main")
    row=$(shellframe_editor_row "main")
    col=$(shellframe_editor_col "main")

    # Header bar (row 1)
    printf '\033[1;1H\033[2K\033[7m%-*s\033[0m' "$cols" \
        "  shellframe editor  |  ln $(( row + 1 ))/$count  col $(( col + 1 ))  |  Ctrl-D submit  Ctrl-C quit" \
        >/dev/tty

    # Editor body (rows 2 .. rows-1)
    local body_rows=$(( rows - 2 ))
    shellframe_editor_render 2 1 "$cols" "$body_rows"

    # Footer bar (last row)
    printf '\033[%d;1H\033[2K\033[2m%-*s\033[0m' "$rows" "$cols" \
        "  ↑↓←→ navigate  Enter newline  Bksp/Del delete  Ctrl-K/U/W clear  Ctrl-D submit" \
        >/dev/tty
}

_draw

# ── Input loop ─────────────────────────────────────────────────────────────────

result=""
key=""
while true; do
    shellframe_read_key key

    shellframe_editor_on_key "$key"
    case $? in
        2)  # Ctrl-D: submit
            result="$SHELLFRAME_EDITOR_RESULT"
            break
            ;;
        *)  # Ctrl-C is caught by the INT trap above
            ;;
    esac

    _draw
done

# Disable EXIT trap before controlled exit so _cleanup isn't called twice.
trap - EXIT INT TERM
_cleanup

# Print result to stdout (on a fresh line so it doesn't run into shell prompt)
printf '\n' >/dev/tty
[[ -n "$result" ]] && printf '%s\n' "$result"
