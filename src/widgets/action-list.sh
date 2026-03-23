#!/usr/bin/env bash
# shellframe/src/widgets/action-list.sh — Interactive action-list TUI widget
#
# GLOBALS (set by caller before calling shellframe_action_list):
#   SHELLFRAME_AL_LABELS[@]  — display label per row
#   SHELLFRAME_AL_ACTIONS[@] — space-separated available actions per row
#   SHELLFRAME_AL_IDX[@]     — current action index per row (caller inits to 0)
#   SHELLFRAME_AL_META[@]    — (optional) per-row metadata string passed to callbacks
#
# GLOBALS (set by shellframe_action_list; readable from callbacks):
#   SHELLFRAME_AL_SELECTED   — index of the currently highlighted row
#   SHELLFRAME_AL_SAVED_STTY — saved stty state; use with shellframe_raw_exit in extra_key_fn
#
# USAGE:
#   shellframe_action_list [draw_row_fn] [extra_key_fn] [footer_text]
#
# draw_row_fn  "$i" "$label" "$acts_str" "$aidx" "$meta"
#   Called once per row during each redraw. Must print one complete line
#   (including the trailing newline). SHELLFRAME_AL_SELECTED is set globally so
#   the function can render the selection cursor.
#   If omitted, a simple built-in renderer is used.
#
# extra_key_fn  "$key"
#   Called for any keypress not handled by the widget's built-in bindings.
#   SHELLFRAME_AL_SAVED_STTY is available so the function can suspend the TUI
#   (shellframe_raw_exit / shellframe_screen_exit) before running a pager, then
#   re-enter (shellframe_screen_enter / shellframe_raw_enter / shellframe_cursor_hide).
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

SHELLFRAME_AL_SELECTED=0
SHELLFRAME_AL_SAVED_STTY=""

# _shellframe_action_list_on_key key n_items
# Handles one keypress for the action-list widget.
# Reads/writes: SHELLFRAME_AL_SELECTED, SHELLFRAME_AL_ACTIONS[], SHELLFRAME_AL_IDX[]
# Returns: 0 = cursor/cycle changed (dirty=1)
#          1 = key not handled
#          2 = confirm (Enter/c)
#          3 = quit (q)
_shellframe_action_list_on_key() {
    local _key="$1" _n="$2"
    if   [[ "$_key" == "$SHELLFRAME_KEY_UP" ]]; then
        (( SHELLFRAME_AL_SELECTED > 0 )) && (( SHELLFRAME_AL_SELECTED-- )) || true
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_DOWN" ]]; then
        (( SHELLFRAME_AL_SELECTED < _n - 1 )) && (( SHELLFRAME_AL_SELECTED++ )) || true
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" || "$_key" == "$SHELLFRAME_KEY_SPACE" ]]; then
        local -a _cur_acts
        IFS=' ' read -r -a _cur_acts <<< "${SHELLFRAME_AL_ACTIONS[$SHELLFRAME_AL_SELECTED]}"
        SHELLFRAME_AL_IDX[$SHELLFRAME_AL_SELECTED]=$(( (SHELLFRAME_AL_IDX[$SHELLFRAME_AL_SELECTED] + 1) % ${#_cur_acts[@]} ))
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
        return 2
    elif [[ "$_key" == 'q' || "$_key" == 'Q' ]]; then
        return 3
    fi
    return 1
}

shellframe_action_list() {
    local _draw_row_fn="${1:-}"
    local _extra_key_fn="${2:-}"
    local _footer="${3:-↑/↓ move  Space/→ cycle  Enter confirm  q quit}"
    local _n=${#SHELLFRAME_AL_LABELS[@]}
    local _dirty=2       # 2=full  1=partial(cursor rows only)  0=none
    local _prev_sel=0    # cursor position before this key event
    local _prev_rows=0 _prev_cols=0   # for resize detection

    # ── Route TUI output to the real terminal ─────────────────────────────
    # When called via $(), stdout is a pipe.  Redirect to /dev/tty so all
    # screen output reaches the terminal.  Fixed fd 3 — {varname} requires
    # bash 4.1+; macOS ships bash 3.2.
    exec 3>&1
    exec 1>&3

    # ── Cleanup ───────────────────────────────────────────────────────────
    SHELLFRAME_AL_SAVED_STTY=$(shellframe_raw_save)
    # Clamp SHELLFRAME_AL_SELECTED to a valid row — do not reset to 0 so callers
    # can preserve cursor position across multiple widget invocations.
    (( SHELLFRAME_AL_SELECTED >= _n && _n > 0 )) && SHELLFRAME_AL_SELECTED=$(( _n - 1 )) || true
    (( SHELLFRAME_AL_SELECTED < 0 )) && SHELLFRAME_AL_SELECTED=0 || true

    _al_exit() {
        shellframe_raw_exit "$SHELLFRAME_AL_SAVED_STTY"
        shellframe_cursor_show
        shellframe_screen_exit
        { exec 1>&3; } 2>/dev/null || true
        { exec 3>&-; } 2>/dev/null || true
    }
    trap '_al_exit; exit 1' INT TERM

    # ── Enter TUI ─────────────────────────────────────────────────────────
    shellframe_screen_enter
    shellframe_raw_enter
    shellframe_cursor_hide

    # ── Default row renderer ──────────────────────────────────────────────
    _al_default_draw_row() {
        local _di="$1" _dlabel="$2" _dacts_str="$3" _daidx="$4"
        local _dcursor="  "
        (( _di == SHELLFRAME_AL_SELECTED )) && _dcursor="${SHELLFRAME_BOLD}> ${SHELLFRAME_RESET}"
        local -a _dacts
        IFS=' ' read -r -a _dacts <<< "$_dacts_str"
        local _daction="${_dacts[$_daidx]}"
        printf "%b%-24s  [%s]\n" "$_dcursor" "$_dlabel" "$_daction"
    }

    # ── Draw ──────────────────────────────────────────────────────────────
    _al_draw() {
        # Resize detection: if terminal size changed, escalate to full redraw
        local _cur_rows=24 _cur_cols=80 _sz
        _sz=$(stty size </dev/tty 2>/dev/null) || _sz="24 80"
        _cur_rows="${_sz%% *}"; _cur_cols="${_sz##* }"
        if (( _cur_rows != _prev_rows || _cur_cols != _prev_cols )); then
            _dirty=2
            _prev_rows=$_cur_rows
            _prev_cols=$_cur_cols
        fi

        if (( _dirty == 0 )); then return; fi

        if (( _dirty == 2 )); then
            # ── Full redraw ───────────────────────────────────────────────
            shellframe_screen_clear
            local _dai
            for (( _dai=0; _dai<_n; _dai++ )); do
                local _dlabel="${SHELLFRAME_AL_LABELS[$_dai]}"
                local _dacts_str="${SHELLFRAME_AL_ACTIONS[$_dai]}"
                local _daidx="${SHELLFRAME_AL_IDX[$_dai]}"
                local _dmeta="${SHELLFRAME_AL_META[$_dai]:-}"
                if [[ -n "$_draw_row_fn" ]]; then
                    "$_draw_row_fn" "$_dai" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                else
                    _al_default_draw_row "$_dai" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                fi
            done
            printf "\n  ${SHELLFRAME_GRAY}%s${SHELLFRAME_RESET}\n" "$_footer"
        else
            # ── Partial redraw (_dirty=1): overwrite old and new cursor rows ──
            # Terminal row = item index + 1 (items start at row 1, no scroll offset).
            # For action cycle (Right/Space), _prev_sel == SHELLFRAME_AL_SELECTED;
            # the loop still works — it redraws the same row twice (idempotent).
            local _dr
            for _dr in "$_prev_sel" "$SHELLFRAME_AL_SELECTED"; do
                printf '\033[%d;1H\033[2K' "$(( _dr + 1 ))"
                local _dlabel="${SHELLFRAME_AL_LABELS[$_dr]}"
                local _dacts_str="${SHELLFRAME_AL_ACTIONS[$_dr]}"
                local _daidx="${SHELLFRAME_AL_IDX[$_dr]}"
                local _dmeta="${SHELLFRAME_AL_META[$_dr]:-}"
                if [[ -n "$_draw_row_fn" ]]; then
                    "$_draw_row_fn" "$_dr" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                else
                    _al_default_draw_row "$_dr" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                fi
            done
        fi

        _dirty=0
    }
    _al_draw

    # ── Input loop ────────────────────────────────────────────────────────
    local _al_retval=1
    while true; do
        local _key _krc
        _prev_sel=$SHELLFRAME_AL_SELECTED
        shellframe_read_key _key

        _shellframe_action_list_on_key "$_key" "$_n"
        _krc=$?

        if (( _krc == 2 )); then
            _al_retval=0; break
        elif (( _krc == 3 )); then
            _al_retval=1; break
        elif (( _krc == 0 )); then
            _dirty=1
        elif [[ -n "$_extra_key_fn" ]]; then
            "$_extra_key_fn" "$_key"
            local _xrc=$?
            if   (( _xrc == 2 )); then
                _al_retval=1; break
            elif (( _xrc == 1 )); then
                continue
            fi
            _dirty=2
        else
            continue
        fi
        _al_draw
    done

    # ── Teardown ──────────────────────────────────────────────────────────
    trap - INT TERM
    _al_exit

    return $_al_retval
}
