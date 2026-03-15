#!/usr/bin/env bash
# examples/action-list.sh — Interactive action-list widget demo
#
# Shows a list of fruits. Each item has a set of available actions;
# the user cycles through them with Space/→ and confirms with Enter.
# The final selections are printed to stdout.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)/clui.sh"

# ── Populate widget globals ───────────────────────────────────────────────────
CLUI_AL_LABELS=(
    "apple"
    "banana"
    "cherry"
    "date"
    "elderberry"
)
CLUI_AL_ACTIONS=(
    "nothing eat"
    "nothing eat peel"
    "nothing eat"
    "nothing eat"
    "nothing eat"
)
CLUI_AL_IDX=(0 0 0 0 0)
CLUI_AL_META=("" "" "" "" "")

# ── Custom row renderer ───────────────────────────────────────────────────────
# Signature: draw_row_fn "$i" "$label" "$acts_str" "$aidx" "$meta"
_demo_draw_row() {
    local i="$1" label="$2" acts_str="$3" aidx="$4"

    local cursor="  "
    (( i == CLUI_AL_SELECTED )) && cursor="${CLUI_BOLD}> ${CLUI_RESET}"

    local -a acts
    IFS=' ' read -r -a acts <<< "$acts_str"
    local action="${acts[$aidx]}"

    local action_str
    case "$action" in
        nothing)  action_str="${CLUI_GRAY}[ ------- ]${CLUI_RESET}" ;;
        eat)      action_str="${CLUI_GREEN}[   eat   ]${CLUI_RESET}" ;;
        peel)     action_str="${CLUI_PURPLE}[  peel   ]${CLUI_RESET}" ;;
        *)        action_str="${CLUI_GRAY}[ $action ]${CLUI_RESET}" ;;
    esac

    printf "%b%-14s  %b\n" "$cursor" "$label" "$action_str"
}

# ── Run widget ────────────────────────────────────────────────────────────────
clui_action_list "_demo_draw_row" "" \
    "↑/↓ move  Space/→ cycle action  Enter confirm  q quit"
_result=$?

# ── Print result ──────────────────────────────────────────────────────────────
_print_results() {
    local i=0 label action
    local -a acts
    if (( _result == 0 )); then
        printf 'Confirmed!\n'
        for label in "${CLUI_AL_LABELS[@]}"; do
            IFS=' ' read -r -a acts <<< "${CLUI_AL_ACTIONS[$i]}"
            action="${acts[${CLUI_AL_IDX[$i]}]}"
            if [[ "$action" != "nothing" ]]; then
                printf "  %s → %s\n" "$label" "$action"
            fi
            (( i++ ))
        done
    else
        printf 'Aborted.\n'
    fi
}
_print_results
