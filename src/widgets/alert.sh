#!/usr/bin/env bash
# shellframe/src/widgets/alert.sh — Modal informational dialog (dismiss-only)
#
# API:
#   shellframe_alert <title> [detail ...]
#
#   <title>      — bold centered heading shown in the modal (plain text)
#   [detail ...]  — optional plain-text lines shown below the title
#
# Displays a centered full-screen modal. Waits for any keypress to dismiss.
# Returns 0.
#
# Key bindings: any key dismisses.

# _shellframe_alert_render title n_details [detail ...]
# Renders the alert box to fd 3. Caller must have set fd 3 to a tty or capture fd.
# Reads SHELLFRAME_* color globals.
_shellframe_alert_render() {
    local _title="$1" _n_details="$2"
    shift 2
    local -a _details=("$@")

    local _cols _rows
    _cols=$(tput cols  2>/dev/null || printf '80')
    _rows=$(tput lines 2>/dev/null || printf '24')

    local _max_content=${#_title}
    local _line
    for _line in "${_details[@]+"${_details[@]}"}"; do
        (( ${#_line} > _max_content )) && _max_content=${#_line}
    done
    local _inner=$(( _max_content + 4 ))
    (( _inner < 32        )) && _inner=32
    (( _inner > _cols - 4 )) && _inner=$(( _cols - 4 ))
    (( _inner < 20        )) && _inner=20

    local _box_h=$(( 5 + _n_details ))
    (( _n_details > 0 )) && (( _box_h++ ))

    local _box_w=$(( _inner + 2 ))
    local _r0=$(( (_rows - _box_h - 1) / 2 ))
    local _c0=$(( (_cols - _box_w)     / 2 ))
    (( _r0 < 1 )) && _r0=1
    (( _c0 < 1 )) && _c0=1

    local _row="$_r0"
    local _i

    # top border
    printf '\033[%d;%dH%b+' "$_row" "$_c0" "$SHELLFRAME_GRAY" >&3
    for (( _i=0; _i<_inner; _i++ )); do printf '-' >&3; done
    printf '+%b' "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # blank
    printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # title (centered, bold)
    local _tl="${#_title}"
    local _tlpad=$(( (_inner - _tl) / 2 ))
    local _trpad=$(( _inner - _tl - _tlpad ))
    printf '\033[%d;%dH%b|%b%*s%b%s%b%*s%b|%b' \
        "$_row" "$_c0" \
        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" \
        "$_tlpad" "" \
        "$SHELLFRAME_BOLD$SHELLFRAME_WHITE" "$_title" "$SHELLFRAME_RESET" \
        "$_trpad" "" \
        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # blank
    printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # detail lines
    if (( _n_details > 0 )); then
        for _line in "${_details[@]}"; do
            local _ll="${#_line}"
            local _rpad=$(( _inner - _ll - 2 ))
            (( _rpad < 0 )) && _rpad=0
            printf '\033[%d;%dH%b|%b  %s%*s%b|%b' \
                "$_row" "$_c0" \
                "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" \
                "$_line" "$_rpad" "" \
                "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" >&3
            (( _row++ ))
        done
        printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET" >&3
        (( _row++ ))
    fi

    # bottom border
    printf '\033[%d;%dH%b+' "$_row" "$_c0" "$SHELLFRAME_GRAY" >&3
    for (( _i=0; _i<_inner; _i++ )); do printf '-' >&3; done
    printf '+%b' "$SHELLFRAME_RESET" >&3
    (( _row++ ))

    # footer hint
    local _hint="Any key to continue"
    local _hcol=$(( _c0 + (_box_w - ${#_hint}) / 2 ))
    (( _hcol < 1 )) && _hcol=1
    printf '\033[%d;%dH%b%s%b' "$_row" "$_hcol" "$SHELLFRAME_GRAY" "$_hint" "$SHELLFRAME_RESET" >&3
}

shellframe_alert() {
    local _title="${1:-Done}"
    (( $# > 0 )) && shift
    local -a _details=("$@")
    local _n_details=${#_details[@]}

    # ── fd plumbing ───────────────────────────────────────────────────────────
    exec 3>&1
    exec 1>&3

    # ── cleanup ───────────────────────────────────────────────────────────────
    local _alrt_saved_stty
    _alrt_saved_stty=$(shellframe_raw_save)

    _alrt_exit() {
        shellframe_raw_exit "$_alrt_saved_stty"
        shellframe_cursor_show
        shellframe_screen_exit
        { exec 1>&3; } 2>/dev/null || true
        { exec 3>&-; } 2>/dev/null || true
    }
    trap '_alrt_exit; exit 1' INT TERM

    # ── enter TUI ─────────────────────────────────────────────────────────────
    shellframe_screen_enter
    shellframe_raw_enter
    shellframe_cursor_hide

    # ── draw ──────────────────────────────────────────────────────────────────
    shellframe_screen_clear
    _shellframe_alert_render "$_title" "$_n_details" "${_details[@]+"${_details[@]}"}"

    # ── wait for any keypress ─────────────────────────────────────────────────
    local _key
    shellframe_read_key _key

    # ── teardown ──────────────────────────────────────────────────────────────
    trap - INT TERM
    _alrt_exit
    return 0
}
