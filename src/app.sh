#!/usr/bin/env bash
# shellframe/src/app.sh — Application runtime (declarative screen FSM)
#
# API:
#   shellframe_app <prefix> [initial_screen]
#
#   <prefix>          — naming prefix for all screen functions (see below)
#   [initial_screen]  — first screen to display (default: ROOT)
#
# ── Screen definition ─────────────────────────────────────────────────────────
#
# A screen is a named state.  For each screen FOO, define these functions
# (replace PREFIX and FOO with your values):
#
#   PREFIX_FOO_type()      — print the widget type: action-list | table | confirm | alert
#                            (called in a subshell — do not modify globals here)
#   PREFIX_FOO_render()    — populate widget context globals before the widget runs
#   PREFIX_FOO_EVENT()     — set _SHELLFRAME_APP_NEXT to the next screen name, or __QUIT__
#                            (called directly — safe to modify application globals)
#
# Events per widget type:
#   action-list  →  confirm (Enter)   |  quit (q)
#   table        →  confirm (Enter)   |  quit (q)
#   confirm      →  yes    (Y/Enter)  |  no   (N/Esc/q)
#   alert        →  dismiss (any key)
#
# ── Output globals (set by event handlers) ────────────────────────────────────
#
#   _SHELLFRAME_APP_NEXT   set this to the next screen name inside every EVENT function
#
# ── Widget context globals (set in render hooks) ──────────────────────────────
#
#   action-list / table screens:
#     _SHELLFRAME_APP_DRAW_FN   row renderer callback name (empty → built-in default)
#     _SHELLFRAME_APP_KEY_FN    extra key handler callback name (empty → none)
#     _SHELLFRAME_APP_HINT      footer hint text (empty → built-in default)
#
#   table screens (additional):
#     SHELLFRAME_TBL_HEADERS[@]    column header labels (plain text)
#     SHELLFRAME_TBL_COL_WIDTHS[@] visible character width per column
#     SHELLFRAME_TBL_PAGE_TITLE    page header bar text (empty → no page chrome)
#     SHELLFRAME_TBL_PAGE_H1       h1 content title
#     SHELLFRAME_TBL_PAGE_FOOTER   page footer bar text
#     SHELLFRAME_TBL_PANEL_FN      right-panel callback name (empty → full-width table)
#     Note: SHELLFRAME_TBL_SCROLL is NOT reset here — set it in your render hook.
#
#   confirm screens:
#     _SHELLFRAME_APP_QUESTION  question text
#     _SHELLFRAME_APP_DETAILS   (array) detail lines shown above the question
#
#   alert screens:
#     _SHELLFRAME_APP_TITLE     title text
#     _SHELLFRAME_APP_DETAILS   (array) detail lines shown below the title
#
# ── Minimal example ───────────────────────────────────────────────────────────
#
#   _myapp_ROOT_type()    { printf 'action-list'; }
#   _myapp_ROOT_render()  { SHELLFRAME_AL_LABELS=(...); ...; _SHELLFRAME_APP_HINT="q quit"; }
#   _myapp_ROOT_confirm() { _SHELLFRAME_APP_NEXT="CONFIRM"; }
#   _myapp_ROOT_quit()    { _SHELLFRAME_APP_NEXT="__QUIT__"; }
#
#   _myapp_CONFIRM_type()   { printf 'confirm'; }
#   _myapp_CONFIRM_render() { _SHELLFRAME_APP_QUESTION="Apply?"; }
#   _myapp_CONFIRM_yes()    { _do_work; _SHELLFRAME_APP_NEXT="DONE"; }
#   _myapp_CONFIRM_no()     { _SHELLFRAME_APP_NEXT="ROOT"; }
#
#   _myapp_DONE_type()      { printf 'alert'; }
#   _myapp_DONE_render()    { _SHELLFRAME_APP_TITLE="Done"; }
#   _myapp_DONE_dismiss()   { _SHELLFRAME_APP_NEXT="ROOT"; }
#
#   shellframe_app "_myapp" "ROOT"

_SHELLFRAME_APP_NEXT=""
_SHELLFRAME_APP_DRAW_FN=""
_SHELLFRAME_APP_KEY_FN=""
_SHELLFRAME_APP_HINT=""
_SHELLFRAME_APP_QUESTION=""
_SHELLFRAME_APP_TITLE=""
_SHELLFRAME_APP_DETAILS=()

# Map widget return code → event name string
_shellframe_app_event() {
    local _type="$1" _rc="$2"
    case "$_type" in
        action-list|table) (( _rc == 0 )) && printf 'confirm' || printf 'quit'   ;;
        confirm)           (( _rc == 0 )) && printf 'yes'     || printf 'no'     ;;
        alert)             printf 'dismiss'                                       ;;
    esac
}

shellframe_app() {
    local _prefix="$1"
    local _current="${2:-ROOT}"

    while [[ "$_current" != "__QUIT__" ]]; do

        # Reset widget context globals before each render
        _SHELLFRAME_APP_DRAW_FN=""
        _SHELLFRAME_APP_KEY_FN=""
        _SHELLFRAME_APP_HINT=""
        _SHELLFRAME_APP_QUESTION=""
        _SHELLFRAME_APP_TITLE=""
        _SHELLFRAME_APP_DETAILS=()
        SHELLFRAME_TBL_HEADERS=()
        SHELLFRAME_TBL_COL_WIDTHS=()
        SHELLFRAME_TBL_PAGE_TITLE=""
        SHELLFRAME_TBL_PAGE_H1=""
        SHELLFRAME_TBL_PAGE_FOOTER=""
        SHELLFRAME_TBL_PANEL_FN=""
        SHELLFRAME_TBL_BELOW_FN=""
        SHELLFRAME_TBL_BELOW_ROWS=0

        # Get screen type (pure — subshell OK), run render hook (direct — can mutate globals)
        local _type
        _type=$("${_prefix}_${_current}_type")
        "${_prefix}_${_current}_render"

        # Run the widget for this screen type
        local _rc=0
        case "$_type" in
            action-list)
                shellframe_action_list \
                    "$_SHELLFRAME_APP_DRAW_FN" \
                    "$_SHELLFRAME_APP_KEY_FN" \
                    "$_SHELLFRAME_APP_HINT"
                _rc=$?
                ;;
            table)
                shellframe_table \
                    "$_SHELLFRAME_APP_DRAW_FN" \
                    "$_SHELLFRAME_APP_KEY_FN" \
                    "$_SHELLFRAME_APP_HINT"
                _rc=$?
                ;;
            confirm)
                if (( ${#_SHELLFRAME_APP_DETAILS[@]} > 0 )); then
                    shellframe_confirm "$_SHELLFRAME_APP_QUESTION" "${_SHELLFRAME_APP_DETAILS[@]}"
                else
                    shellframe_confirm "$_SHELLFRAME_APP_QUESTION"
                fi
                _rc=$?
                ;;
            alert)
                if (( ${#_SHELLFRAME_APP_DETAILS[@]} > 0 )); then
                    shellframe_alert "$_SHELLFRAME_APP_TITLE" "${_SHELLFRAME_APP_DETAILS[@]}"
                else
                    shellframe_alert "$_SHELLFRAME_APP_TITLE"
                fi
                _rc=$?
                ;;
        esac

        # Map rc → event name, call event handler directly (not in $() — safe to
        # mutate globals).  Handler must set _SHELLFRAME_APP_NEXT to the next screen name.
        local _event
        _event=$(_shellframe_app_event "$_type" "$_rc")
        _SHELLFRAME_APP_NEXT=""
        "${_prefix}_${_current}_${_event}"
        _current="$_SHELLFRAME_APP_NEXT"
    done
}
