#!/usr/bin/env bash
# shellframe/src/widgets/confirm.sh — Modal yes/no confirmation dialog
#
# GLOBALS (set by caller before calling shellframe_confirm):
#   none — all configuration is passed as arguments
#
# API:
#   shellframe_confirm <question> [detail ...]
#
#   <question>   — bold centered text shown in the modal (plain text)
#   [detail ...]  — optional plain-text lines shown above the question
#                   (e.g. a summary of what will be applied)
#
# Returns 0 for Yes, 1 for No or cancel.
#
# Key bindings:
#   ←/→  h/l    toggle between Yes and No
#   y / Y        select Yes and confirm immediately
#   n / N        select No and confirm immediately
#   Enter / c    confirm current selection (default: Yes)
#   Esc / q / Q  cancel (same as No)

shellframe_confirm() {
    local _question="${1:-Are you sure?}"
    (( $# > 0 )) && shift
    local -a _details=("$@")
    local _n_details=${#_details[@]}

    local _retval=1
    local _selected=0   # 0 = Yes, 1 = No

    # ── fd plumbing ───────────────────────────────────────────────────────────
    exec 3>&1
    exec 1>/dev/tty

    # ── cleanup ───────────────────────────────────────────────────────────────
    local _cf_saved_stty
    _cf_saved_stty=$(shellframe_raw_save)

    _cf_exit() {
        shellframe_raw_exit "$_cf_saved_stty"
        shellframe_cursor_show
        shellframe_screen_exit
        { exec 1>&3; } 2>/dev/null || true
        { exec 3>&-; } 2>/dev/null || true
    }
    trap '_cf_exit; exit 1' INT TERM

    # ── enter TUI ─────────────────────────────────────────────────────────────
    shellframe_screen_enter
    shellframe_raw_enter
    shellframe_cursor_hide

    # ── layout (computed once; _cf_draw reads from enclosing scope) ───────────
    local _cols _rows
    _cols=$(tput cols  2>/dev/null || printf '80')
    _rows=$(tput lines 2>/dev/null || printf '24')

    # inner width: wide enough for the longest line, with 2-char side padding
    local _max_content=${#_question}
    local _line
    for _line in "${_details[@]+"${_details[@]}"}"; do
        (( ${#_line} > _max_content )) && _max_content=${#_line}
    done
    local _inner=$(( _max_content + 4 ))
    (( _inner < 36              )) && _inner=36
    (( _inner > _cols - 4       )) && _inner=$(( _cols - 4 ))
    (( _inner < 20              )) && _inner=20     # hard floor for tiny terminals

    # box height (borders included):
    #   top border + blank + [details + blank-sep] + question + blank + buttons + blank + bottom
    local _box_h=$(( 7 + _n_details ))
    (( _n_details > 0 )) && (( _box_h++ ))

    local _box_w=$(( _inner + 2 ))

    # center position (1-indexed)
    local _r0=$(( (_rows - _box_h - 1) / 2 ))
    local _c0=$(( (_cols - _box_w)     / 2 ))
    (( _r0 < 1 )) && _r0=1
    (( _c0 < 1 )) && _c0=1

    # Pre-compute button row for partial draw.
    # Derivation: top border(+0) blank(+1) details(+n) [blank-sep(+1 if n>0)]
    #             question(+1) blank(+1) buttons → constant = 4
    local _btn_row=$(( _r0 + 4 + _n_details ))
    (( _n_details > 0 )) && (( _btn_row++ )) || true

    local _dirty=2   # 2=full  1=partial(button row only)  0=none

    # ── row renderer ─────────────────────────────────────────────────────────

    # Render the button row at absolute terminal row $1.
    _cf_draw_buttons() {
        local _brow="$1"
        local _yes_str _no_str
        if (( _selected == 0 )); then
            _yes_str="${SHELLFRAME_BOLD}${SHELLFRAME_WHITE}[ Yes ]${SHELLFRAME_RESET}"
            _no_str="${SHELLFRAME_GRAY}[ No  ]${SHELLFRAME_RESET}"
        else
            _yes_str="${SHELLFRAME_GRAY}[ Yes ]${SHELLFRAME_RESET}"
            _no_str="${SHELLFRAME_BOLD}${SHELLFRAME_WHITE}[ No  ]${SHELLFRAME_RESET}"
        fi
        local _btn_raw=20
        local _blpad=$(( (_inner - _btn_raw) / 2 ))
        local _brpad=$(( _inner - _btn_raw - _blpad ))
        (( _blpad < 1 )) && _blpad=1
        (( _brpad < 0 )) && _brpad=0
        printf '\033[%d;%dH%b|%b' "$_brow" "$_c0" "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
        printf '%*s%b      %b%*s' "$_blpad" "" "$_yes_str" "$_no_str" "$_brpad" ""
        printf '%b|%b' "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
    }

    _cf_draw() {
        if (( _dirty == 0 )); then return; fi

        if (( _dirty == 2 )); then
            # ── Full redraw ───────────────────────────────────────────────
            shellframe_screen_clear

            local _row="$_r0"
            local _i

            # top border
            printf '\033[%d;%dH%b+' "$_row" "$_c0" "$SHELLFRAME_GRAY"
            for (( _i=0; _i<_inner; _i++ )); do printf '-'; done
            printf '+%b' "$SHELLFRAME_RESET"
            (( _row++ ))

            # blank
            printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET"
            (( _row++ ))

            # detail lines
            local _line
            if (( _n_details > 0 )); then
                for _line in "${_details[@]}"; do
                    local _ll="${#_line}"
                    local _rpad=$(( _inner - _ll - 2 ))
                    (( _rpad < 0 )) && _rpad=0
                    printf '\033[%d;%dH%b|%b  %s%*s%b|%b' \
                        "$_row" "$_c0" \
                        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" \
                        "$_line" "$_rpad" "" \
                        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
                    (( _row++ ))
                done
                # blank separator
                printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET"
                (( _row++ ))
            fi

            # question (centered, bold)
            local _ql="${#_question}"
            local _qlpad=$(( (_inner - _ql) / 2 ))
            local _qrpad=$(( _inner - _ql - _qlpad ))
            printf '\033[%d;%dH%b|%b%*s%b%s%b%*s%b|%b' \
                "$_row" "$_c0" \
                "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET" \
                "$_qlpad" "" \
                "$SHELLFRAME_BOLD$SHELLFRAME_WHITE" "$_question" "$SHELLFRAME_RESET" \
                "$_qrpad" "" \
                "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
            (( _row++ ))

            # blank
            printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET"
            (( _row++ ))

            # buttons (row == _btn_row)
            _cf_draw_buttons "$_row"
            (( _row++ ))

            # blank
            printf '\033[%d;%dH%b|%*s|%b' "$_row" "$_c0" "$SHELLFRAME_GRAY" "$_inner" "" "$SHELLFRAME_RESET"
            (( _row++ ))

            # bottom border
            printf '\033[%d;%dH%b+' "$_row" "$_c0" "$SHELLFRAME_GRAY"
            for (( _i=0; _i<_inner; _i++ )); do printf '-'; done
            printf '+%b' "$SHELLFRAME_RESET"
            (( _row++ ))

            # footer hint
            local _hint="←/→ select   y/n quick   Enter confirm"
            local _hcol=$(( _c0 + (_box_w - ${#_hint}) / 2 ))
            (( _hcol < 1 )) && _hcol=1
            printf '\033[%d;%dH%b%s%b' "$_row" "$_hcol" "$SHELLFRAME_GRAY" "$_hint" "$SHELLFRAME_RESET"

        else
            # ── Partial redraw (_dirty=1): button row only ─────────────────
            _cf_draw_buttons "$_btn_row"
        fi

        _dirty=0
    }
    _cf_draw

    # ── input loop ────────────────────────────────────────────────────────────
    while true; do
        local _key
        shellframe_read_key _key

        if   [[ "$_key" == "$SHELLFRAME_KEY_LEFT"  || "$_key" == 'h' || "$_key" == 'H' ]]; then
            _selected=0
            _dirty=1
        elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" || "$_key" == 'l' || "$_key" == 'L' ]]; then
            _selected=1
            _dirty=1
        elif [[ "$_key" == 'y' || "$_key" == 'Y' ]]; then
            _retval=0; break
        elif [[ "$_key" == 'n' || "$_key" == 'N' ]]; then
            _retval=1; break
        elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
            _retval=$_selected; break
        elif [[ "$_key" == "$SHELLFRAME_KEY_ESC"   || "$_key" == 'q' || "$_key" == 'Q' ]]; then
            _retval=1; break
        else
            continue
        fi
        _cf_draw
    done

    # ── teardown ──────────────────────────────────────────────────────────────
    trap - INT TERM
    _cf_exit
    return $_retval
}
