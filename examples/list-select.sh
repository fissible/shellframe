#!/usr/bin/env bash
# examples/list-select.sh — Interactive single-select list using clui
#
# Usage: ./list-select.sh
# Returns the selected item on stdout after the TUI exits.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/clui.sh"

list_select() {
    local -a items=("$@")
    local n=${#items[@]}
    local selected=0

    # ── Cleanup ───────────────────────────────────────────────────────
    local saved_stty
    saved_stty=$(clui_raw_save)

    _ls_exit() {
        clui_raw_exit "$saved_stty"
        clui_cursor_show
        clui_screen_exit
    }
    trap '_ls_exit; exit 1' INT TERM

    # ── Enter TUI ─────────────────────────────────────────────────────
    clui_screen_enter
    clui_raw_enter
    clui_cursor_hide

    _draw() {
        clui_screen_clear
        local i
        for (( i=0; i<n; i++ )); do
            if (( i == selected )); then
                printf "  ${CLUI_BOLD}${CLUI_GREEN}> %s${CLUI_RESET}\n" "${items[$i]}"
            else
                printf "    ${CLUI_GRAY}%s${CLUI_RESET}\n" "${items[$i]}"
            fi
        done
        printf "\n  ${CLUI_GRAY}↑/↓ move  Enter select  q quit${CLUI_RESET}\n"
    }
    _draw

    # ── Input loop ────────────────────────────────────────────────────
    local key result=""
    while true; do
        clui_read_key key
        if   [[ "$key" == "$CLUI_KEY_UP"    ]]; then
            (( selected > 0     )) && (( selected-- )) || true
        elif [[ "$key" == "$CLUI_KEY_DOWN"  ]]; then
            (( selected < n - 1 )) && (( selected++ )) || true
        elif [[ "$key" == "$CLUI_KEY_ENTER" || "$key" == "$CLUI_KEY_SPACE" ]]; then
            result="${items[$selected]}"
            break
        elif [[ "$key" == 'q' || "$key" == 'Q' || "$key" == $'\x03' ]]; then
            break
        fi
        _draw
    done

    _ls_exit
    trap - INT TERM

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
