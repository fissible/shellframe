#!/usr/bin/env bash
# clui/src/widgets/action-list.sh — Interactive action-list TUI widget
#
# GLOBALS (set by caller before calling clui_action_list):
#   CLUI_AL_LABELS[@]  — display label per row
#   CLUI_AL_ACTIONS[@] — space-separated available actions per row
#   CLUI_AL_IDX[@]     — current action index per row (caller inits to 0)
#   CLUI_AL_META[@]    — (optional) per-row metadata string passed to callbacks
#
# GLOBALS (set by clui_action_list; readable from callbacks):
#   CLUI_AL_SELECTED   — index of the currently highlighted row
#   CLUI_AL_SAVED_STTY — saved stty state; use with clui_raw_exit in extra_key_fn
#
# USAGE:
#   clui_action_list [draw_row_fn] [extra_key_fn] [footer_text]
#
# draw_row_fn  "$i" "$label" "$acts_str" "$aidx" "$meta"
#   Called once per row during each redraw. Must print one complete line
#   (including the trailing newline). CLUI_AL_SELECTED is set globally so
#   the function can render the selection cursor.
#   If omitted, a simple built-in renderer is used.
#
# extra_key_fn  "$key"
#   Called for any keypress not handled by the widget's built-in bindings.
#   CLUI_AL_SAVED_STTY is available so the function can suspend the TUI
#   (clui_raw_exit / clui_screen_exit) before running a pager, then
#   re-enter (clui_screen_enter / clui_raw_enter / clui_cursor_hide).
#   Return codes:
#     0 — key handled; widget will redraw
#     1 — key not handled; widget skips redraw (default)
#     2 — quit requested; widget exits with return 1
#
# Built-in key bindings (not overridable):
#   Up / Down  — move cursor
#   Right / Space — cycle action for selected row forward
#   Enter / c  — confirm; widget returns 0
#   q          — quit;    widget returns 1
#
# RETURN:
#   0 — user confirmed
#   1 — user quit
#
# NOTE: Uses fd 3 internally (bash 3.2 compat; no {varname} fd allocation).
#       Ensure fd 3 is not in use by the calling process.

CLUI_AL_SELECTED=0
CLUI_AL_SAVED_STTY=""

clui_action_list() {
    local _draw_row_fn="${1:-}"
    local _extra_key_fn="${2:-}"
    local _footer="${3:-↑/↓ move  Space/→ cycle  Enter confirm  q quit}"
    local _n=${#CLUI_AL_LABELS[@]}

    # ── Route TUI output to the real terminal ─────────────────────────────
    # When called via $(), stdout is a pipe.  Redirect to /dev/tty so all
    # screen output reaches the terminal.  Fixed fd 3 — {varname} requires
    # bash 4.1+; macOS ships bash 3.2.
    exec 3>&1
    exec 1>/dev/tty

    # ── Cleanup ───────────────────────────────────────────────────────────
    CLUI_AL_SAVED_STTY=$(clui_raw_save)
    CLUI_AL_SELECTED=0

    _al_exit() {
        clui_raw_exit "$CLUI_AL_SAVED_STTY"
        clui_cursor_show
        clui_screen_exit
        exec 1>&3  2>/dev/null || true
        exec 3>&-  2>/dev/null || true
    }
    trap '_al_exit; exit 1' INT TERM

    # ── Enter TUI ─────────────────────────────────────────────────────────
    clui_screen_enter
    clui_raw_enter
    clui_cursor_hide

    # ── Default row renderer ──────────────────────────────────────────────
    _al_default_draw_row() {
        local _di="$1" _dlabel="$2" _dacts_str="$3" _daidx="$4"
        local _dcursor="  "
        (( _di == CLUI_AL_SELECTED )) && _dcursor="${CLUI_BOLD}> ${CLUI_RESET}"
        local -a _dacts
        IFS=' ' read -r -a _dacts <<< "$_dacts_str"
        local _daction="${_dacts[$_daidx]}"
        printf "%b%-24s  [%s]\n" "$_dcursor" "$_dlabel" "$_daction"
    }

    # ── Draw ──────────────────────────────────────────────────────────────
    _al_draw() {
        clui_screen_clear
        local _dai
        for (( _dai=0; _dai<_n; _dai++ )); do
            local _dlabel="${CLUI_AL_LABELS[$_dai]}"
            local _dacts_str="${CLUI_AL_ACTIONS[$_dai]}"
            local _daidx="${CLUI_AL_IDX[$_dai]}"
            local _dmeta="${CLUI_AL_META[$_dai]:-}"
            if [[ -n "$_draw_row_fn" ]]; then
                "$_draw_row_fn" "$_dai" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
            else
                _al_default_draw_row "$_dai" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
            fi
        done
        printf "\n  ${CLUI_GRAY}%s${CLUI_RESET}\n" "$_footer"
    }
    _al_draw

    # ── Input loop ────────────────────────────────────────────────────────
    local _al_retval=1
    while true; do
        local _key
        clui_read_key _key

        if   [[ "$_key" == "$CLUI_KEY_UP" ]]; then
            (( CLUI_AL_SELECTED > 0 )) && (( CLUI_AL_SELECTED-- )) || true
        elif [[ "$_key" == "$CLUI_KEY_DOWN" ]]; then
            (( CLUI_AL_SELECTED < _n - 1 )) && (( CLUI_AL_SELECTED++ )) || true
        elif [[ "$_key" == "$CLUI_KEY_RIGHT" || "$_key" == "$CLUI_KEY_SPACE" ]]; then
            local -a _cur_acts
            IFS=' ' read -r -a _cur_acts <<< "${CLUI_AL_ACTIONS[$CLUI_AL_SELECTED]}"
            CLUI_AL_IDX[$CLUI_AL_SELECTED]=$(( (CLUI_AL_IDX[$CLUI_AL_SELECTED] + 1) % ${#_cur_acts[@]} ))
        elif [[ "$_key" == "$CLUI_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
            _al_retval=0
            break
        elif [[ "$_key" == 'q' || "$_key" == 'Q' ]]; then
            _al_retval=1
            break
        elif [[ -n "$_extra_key_fn" ]]; then
            "$_extra_key_fn" "$_key"
            local _xrc=$?
            if   (( _xrc == 2 )); then
                _al_retval=1; break
            elif (( _xrc == 1 )); then
                continue   # not handled — skip redraw
            fi
            # _xrc == 0: handled — fall through to redraw
        else
            continue  # unrecognized key — skip redraw
        fi

        _al_draw
    done

    # ── Teardown ──────────────────────────────────────────────────────────
    trap - INT TERM
    _al_exit

    return $_al_retval
}
