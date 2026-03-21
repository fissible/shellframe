#!/usr/bin/env bash
# examples/list-select.sh — Interactive single-select list using shellframe
#
# Usage: ./list-select.sh
# Returns the selected item on stdout after the TUI exits.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/shellframe.sh"

list_select() {
    local -a items=("$@")
    local n=${#items[@]}
    local selected=0

    # ── Route TUI output to the real terminal ─────────────────────────
    # When called as $(list_select ...), stdout is a pipe. Redirect to
    # /dev/tty so screen/draw output reaches the terminal. The final
    # result printf restores stdout so the value is captured by $().
    # Use fixed fd 4 — {varname} fd allocation requires bash 4.1+.
    # fd 3 is reserved by shellframe_screen_enter for persistent /dev/tty output.
    exec 4>&1
    exec 1>/dev/tty

    # ── Cleanup ───────────────────────────────────────────────────────
    local saved_stty
    saved_stty=$(shellframe_raw_save)

    _ls_exit() {
        shellframe_raw_exit "$saved_stty"
        shellframe_cursor_show
        shellframe_screen_exit
    }
    trap '_ls_exit; exit 1' INT TERM

    # ── Enter TUI ─────────────────────────────────────────────────────
    shellframe_screen_enter
    shellframe_raw_enter
    shellframe_cursor_hide

    _draw() {
        shellframe_screen_clear
        local i
        for (( i=0; i<n; i++ )); do
            if (( i == selected )); then
                printf "  ${SHELLFRAME_BOLD}${SHELLFRAME_GREEN}> %s${SHELLFRAME_RESET}\n" "${items[$i]}"
            else
                printf "    ${SHELLFRAME_GRAY}%s${SHELLFRAME_RESET}\n" "${items[$i]}"
            fi
        done
        printf "\n  ${SHELLFRAME_GRAY}↑/↓ move  Enter select  q quit${SHELLFRAME_RESET}\n"
    }
    _draw

    # ── Input loop ────────────────────────────────────────────────────
    local key result=""
    while true; do
        shellframe_read_key key
        if   [[ "$key" == "$SHELLFRAME_KEY_UP"    ]]; then
            (( selected > 0     )) && (( selected-- )) || true
        elif [[ "$key" == "$SHELLFRAME_KEY_DOWN"  ]]; then
            (( selected < n - 1 )) && (( selected++ )) || true
        elif [[ "$key" == "$SHELLFRAME_KEY_ENTER" || "$key" == "$SHELLFRAME_KEY_SPACE" ]]; then
            result="${items[$selected]}"
            break
        elif [[ "$key" == 'q' || "$key" == 'Q' || "$key" == $'\x03' ]]; then
            break
        fi
        _draw
    done

    _ls_exit
    trap - INT TERM

    # Restore original stdout so the result is captured by $() callers
    exec 1>&4
    exec 4>&-

    [[ -n "$result" ]] && printf '%s\n' "$result"
}

# ── Demo ──────────────────────────────────────────────────────────────────────
items=(
    "apple"
    "banana"
    "cherry"
    "date"
    "elderberry"
)

chosen=$(list_select "${items[@]}")

if [[ -n "$chosen" ]]; then
    printf 'You selected: %s\n' "$chosen"
else
    printf 'No selection.\n'
fi
