#!/usr/bin/env bash
# shellframe/src/widgets/table.sh — Navigable table TUI widget with header row,
# full-height/full-width layout, optional page chrome, and optional side panel.
#
# ── Page chrome globals (set by caller; reset by app.sh between screens) ────────
#
#   SHELLFRAME_TBL_PAGE_TITLE  — page header bar text (reverse-video, full-width, row 1)
#   SHELLFRAME_TBL_PAGE_H1     — content area h1 title (bold, full-width, row 2)
#   SHELLFRAME_TBL_PAGE_FOOTER — page footer bar text (gray, full-width, bottom row)
#   SHELLFRAME_TBL_PANEL_FN    — right-panel callback: fn top_row left_col width height
#                                 Receives absolute ANSI cursor context.
#                                 Omit or set to "" for full-width table.
#
# When page chrome globals are set the layout is:
#   Row 1              : header bar  (SHELLFRAME_TBL_PAGE_TITLE)
#   Row 2              : h1 title    (SHELLFRAME_TBL_PAGE_H1)
#   Row 3              : ─── separator (full-width)
#   Rows 4 .. rows-2   : content area  ← table fills this space
#   Row rows-1         : ─── separator (full-width)
#   Row rows           : footer bar  (SHELLFRAME_TBL_PAGE_FOOTER)
#
# When SHELLFRAME_TBL_PANEL_FN is set the content area is split 50/50:
#   Left  half : table  (SHELLFRAME_TBL_HEADERS, data rows, keyboard hint)
#   Col N+1    : │ separator
#   Right half : panel  (SHELLFRAME_TBL_PANEL_FN callback)
#
# ── Table data globals (set by caller before calling shellframe_table) ───────────
#
#   SHELLFRAME_TBL_HEADERS[@]    — column header labels (plain text)
#   SHELLFRAME_TBL_COL_WIDTHS[@] — visible character width per column
#                                   columns are printed left-aligned; embed padding
#                                   in widths or use blank-header columns for gaps
#   SHELLFRAME_TBL_LABELS[@]     — primary label per row (passed to draw_row_fn as $2)
#   SHELLFRAME_TBL_ACTIONS[@]    — space-separated available actions per row
#   SHELLFRAME_TBL_IDX[@]        — current action index per row (caller inits to 0)
#   SHELLFRAME_TBL_META[@]       — (optional) per-row metadata string
#
# ── State globals (set by shellframe_table; readable from callbacks) ─────────────
#
#   SHELLFRAME_TBL_COLS       — current terminal column count (set by shellframe_table on
#                               each redraw); read-only for callbacks, including draw_row_fn
#   SHELLFRAME_TBL_SELECTED   — index of the currently highlighted row
#   SHELLFRAME_TBL_SCROLL     — index of the first visible row (vertical scroll offset)
#                               Reset this to 0 in your screen's render hook when
#                               loading new data; app.sh does NOT reset it.
#   SHELLFRAME_TBL_SAVED_STTY — saved stty state; use with shellframe_raw_exit in
#                               extra_key_fn to temporarily suspend the TUI
#
# ── USAGE ────────────────────────────────────────────────────────────────────────
#
#   shellframe_table [draw_row_fn] [extra_key_fn] [footer_text]
#
# draw_row_fn  "$i" "$label" "$acts_str" "$aidx" "$meta"
#   Called once per visible row during each redraw. The cursor has been positioned
#   at (row, 1) via absolute ANSI positioning before this call, and the line has
#   been erased (\033[2K). Print one line of content; a trailing \n is harmless.
#   SHELLFRAME_TBL_SELECTED is set globally so the function can render the cursor.
#   Omit to use the built-in default renderer.
#
# extra_key_fn  "$key"
#   Called for any keypress not handled by built-in bindings.
#   Return 0 = handled (redraw), 1 = not handled, 2 = quit requested.
#   SHELLFRAME_TBL_SAVED_STTY is available for TUI suspend/resume.
#
# ── Built-in key bindings ────────────────────────────────────────────────────────
#   Up / Down          — move cursor
#   Right / Space      — cycle action for selected row forward
#   Enter / c          — confirm; widget returns 0
#   q                  — quit;    widget returns 1
#
# RETURN:
#   0 — user confirmed
#   1 — user quit
#
# NOTE: Uses fd 3 internally (bash 3.2 compat; no {varname} fd allocation).
#       Ensure fd 3 is not in use by the calling process.

SHELLFRAME_TBL_SELECTED=0
SHELLFRAME_TBL_SCROLL=0
SHELLFRAME_TBL_SAVED_STTY=""
SHELLFRAME_TBL_COLS=0
SHELLFRAME_TBL_HEADERS=()
SHELLFRAME_TBL_COL_WIDTHS=()
SHELLFRAME_TBL_PAGE_TITLE=""
SHELLFRAME_TBL_PAGE_H1=""
SHELLFRAME_TBL_PAGE_FOOTER=""
SHELLFRAME_TBL_PANEL_FN=""
SHELLFRAME_TBL_BELOW_FN=""
SHELLFRAME_TBL_BELOW_ROWS=0

# _shellframe_table_on_key key n_items
# Handles one keypress for the table widget.
# Reads/writes: SHELLFRAME_TBL_SELECTED, SHELLFRAME_TBL_ACTIONS[], SHELLFRAME_TBL_IDX[]
# Returns: 0 = cursor/cycle changed (dirty)
#          1 = key not handled
#          2 = confirm (Enter/c/C)
#          3 = quit (q/Q)
_shellframe_table_on_key() {
    local _key="$1" _n="$2"
    if   [[ "$_key" == "$SHELLFRAME_KEY_UP" ]]; then
        (( SHELLFRAME_TBL_SELECTED > 0 )) && (( SHELLFRAME_TBL_SELECTED-- )) || true
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_DOWN" ]]; then
        (( SHELLFRAME_TBL_SELECTED < _n - 1 )) && (( SHELLFRAME_TBL_SELECTED++ )) || true
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_RIGHT" || "$_key" == "$SHELLFRAME_KEY_SPACE" ]]; then
        local -a _cur_acts
        IFS=' ' read -r -a _cur_acts <<< "${SHELLFRAME_TBL_ACTIONS[$SHELLFRAME_TBL_SELECTED]}"
        SHELLFRAME_TBL_IDX[$SHELLFRAME_TBL_SELECTED]=$(( (SHELLFRAME_TBL_IDX[$SHELLFRAME_TBL_SELECTED] + 1) % ${#_cur_acts[@]} ))
        return 0
    elif [[ "$_key" == "$SHELLFRAME_KEY_ENTER" || "$_key" == 'c' || "$_key" == 'C' ]]; then
        return 2
    elif [[ "$_key" == 'q' || "$_key" == 'Q' ]]; then
        return 3
    fi
    return 1
}

# _shellframe_table_scroll_check visible_rows
# Adjusts SHELLFRAME_TBL_SCROLL so that SHELLFRAME_TBL_SELECTED stays within
# the viewport [SHELLFRAME_TBL_SCROLL, SHELLFRAME_TBL_SCROLL + visible_rows).
# Returns: 0 if SHELLFRAME_TBL_SCROLL changed, 1 if unchanged.
_shellframe_table_scroll_check() {
    local _vr="$1"
    local _new_scroll=$SHELLFRAME_TBL_SCROLL
    if (( SHELLFRAME_TBL_SELECTED < _new_scroll )); then
        _new_scroll=$SHELLFRAME_TBL_SELECTED
    fi
    if (( SHELLFRAME_TBL_SELECTED >= _new_scroll + _vr )); then
        _new_scroll=$(( SHELLFRAME_TBL_SELECTED - _vr + 1 ))
    fi
    if (( _new_scroll != SHELLFRAME_TBL_SCROLL )); then
        SHELLFRAME_TBL_SCROLL=$_new_scroll
        return 0
    fi
    return 1
}

shellframe_table() {
    local _draw_row_fn="${1:-}"
    local _extra_key_fn="${2:-}"
    local _footer="${3:-↑/↓ move  Space/→ cycle  Enter confirm  q quit}"
    local _n=${#SHELLFRAME_TBL_LABELS[@]}

    local _dirty=2       # 2=full  1=partial  0=none
    local _prev_sel=0    # cursor position before this key event
    local _prev_rows=0 _prev_cols=0   # for resize detection

    # Layout cache — set by full draw, read by partial draw.
    # These are declared here with 'local' in shellframe_table's scope.
    # _tbl_draw assigns to them WITHOUT 'local', so the assignments propagate
    # back to shellframe_table via bash dynamic scoping (inner function reads/
    # writes the enclosing function's local variables).
    #
    # Mapping to existing _tbl_draw variable names:
    #   _tbl_ct  ← _content_top       (first row of the content area)
    #   _tbl_fdr ← _first_data_row    (first data row, after headers)
    #   _tbl_vr  ← _visible_rows      (number of visible data rows in viewport)
    #   _tbl_sp  ← _show_panel        (1 if side panel is active)
    #   _tbl_pl  ← _panel_left        (panel start column)
    #   _tbl_pw  ← _panel_width       (panel column count)
    #   _tbl_ch  ← _content_height    (rows from _content_top to _content_bottom)
    local _tbl_ct=1
    local _tbl_fdr=1
    local _tbl_vr=1
    local _tbl_sp=0
    local _tbl_pl=0
    local _tbl_pw=0
    local _tbl_ch=0

    # ── Route TUI output to the real terminal ─────────────────────────────
    exec 3>&1
    exec 1>&3

    # ── Cleanup ───────────────────────────────────────────────────────────
    SHELLFRAME_TBL_SAVED_STTY=$(shellframe_raw_save)
    (( SHELLFRAME_TBL_SELECTED >= _n && _n > 0 )) && SHELLFRAME_TBL_SELECTED=$(( _n - 1 )) || true
    (( SHELLFRAME_TBL_SELECTED < 0 )) && SHELLFRAME_TBL_SELECTED=0 || true

    _tbl_exit() {
        shellframe_raw_exit "$SHELLFRAME_TBL_SAVED_STTY"
        shellframe_cursor_show
        shellframe_screen_exit
        { exec 1>&3; } 2>/dev/null || true
        { exec 3>&-; } 2>/dev/null || true
    }
    trap '_tbl_exit; exit 1' INT TERM

    # ── Enter TUI ─────────────────────────────────────────────────────────
    shellframe_screen_enter
    shellframe_raw_enter
    shellframe_cursor_hide

    # ── Default row renderer ──────────────────────────────────────────────
    _tbl_default_draw_row() {
        local _di="$1" _dlabel="$2" _dacts_str="$3" _daidx="$4"
        local _dcursor="  "
        (( _di == SHELLFRAME_TBL_SELECTED )) && _dcursor="${SHELLFRAME_BOLD}> ${SHELLFRAME_RESET}"
        local -a _dacts
        IFS=' ' read -r -a _dacts <<< "$_dacts_str"
        local _daction="${_dacts[$_daidx]}"
        printf "%b%-24s  [%s]" "$_dcursor" "$_dlabel" "$_daction"
    }

    # ── Main draw ─────────────────────────────────────────────────────────
    _tbl_draw() {
        # ── Terminal size and resize check ────────────────────────────────
        local _rows=24 _cols=80 _sz
        _sz=$(stty size </dev/tty 2>/dev/null) || _sz="24 80"
        _rows="${_sz%% *}"; _cols="${_sz##* }"
        SHELLFRAME_TBL_COLS=$_cols

        if (( _rows != _prev_rows || _cols != _prev_cols )); then
            _dirty=2
            _prev_rows=$_rows
            _prev_cols=$_cols
        fi

        if (( _dirty == 0 )); then return; fi

        if (( _dirty == 1 )); then
            # ── Partial redraw: scroll-boundary check ─────────────────────
            # If the viewport needs to shift, escalate to a full redraw.
            _shellframe_table_scroll_check "$_tbl_vr" && _dirty=2
        fi

        if (( _dirty == 2 )); then
            # ── Full redraw ───────────────────────────────────────────────
            shellframe_screen_clear

            # ── Page chrome: top ──────────────────────────────────────────
            local _content_top=1
            local _fi
            if [[ -n "$SHELLFRAME_TBL_PAGE_TITLE" || -n "$SHELLFRAME_TBL_PAGE_H1" ]]; then
                printf '\033[1;1H%b%b %s\033[K%b' \
                    "$SHELLFRAME_REVERSE" "$SHELLFRAME_BOLD" \
                    "$SHELLFRAME_TBL_PAGE_TITLE" \
                    "$SHELLFRAME_RESET"
                printf '\033[2;1H%b %s%b' \
                    "$SHELLFRAME_BOLD$SHELLFRAME_WHITE" \
                    "$SHELLFRAME_TBL_PAGE_H1" \
                    "$SHELLFRAME_RESET"
                printf '\033[3;1H%b' "$SHELLFRAME_GRAY"
                for (( _fi=0; _fi<_cols; _fi++ )); do printf '─'; done
                printf '%b' "$SHELLFRAME_RESET"
                _content_top=4
            fi

            # ── Page chrome: bottom ───────────────────────────────────────
            local _content_bottom=$_rows
            if [[ -n "$SHELLFRAME_TBL_PAGE_FOOTER" ]]; then
                printf '\033[%d;1H%b' "$(( _rows - 1 ))" "$SHELLFRAME_GRAY"
                for (( _fi=0; _fi<_cols; _fi++ )); do printf '─'; done
                printf '%b' "$SHELLFRAME_RESET"
                printf '\033[%d;1H%b %s\033[K%b' \
                    "$_rows" \
                    "$SHELLFRAME_GRAY" \
                    "$SHELLFRAME_TBL_PAGE_FOOTER" \
                    "$SHELLFRAME_RESET"
                _content_bottom=$(( _rows - 2 ))
            fi

            local _content_height=$(( _content_bottom - _content_top + 1 ))

            # ── Table width and optional panel layout ─────────────────────
            local _table_width=$_cols
            local _show_panel=0
            local _panel_left=0 _panel_width=0

            if [[ -n "$SHELLFRAME_TBL_PANEL_FN" ]]; then
                local _tbl_min_w=2
                local _cwi
                for _cwi in "${SHELLFRAME_TBL_COL_WIDTHS[@]+"${SHELLFRAME_TBL_COL_WIDTHS[@]}"}"; do
                    _tbl_min_w=$(( _tbl_min_w + _cwi ))
                done
                local _half=$(( _cols / 2 ))
                (( _half < _tbl_min_w )) && _half=$_tbl_min_w
                if (( _half + 1 + 20 <= _cols )); then
                    _table_width=$_half
                    _panel_left=$(( _table_width + 2 ))
                    _panel_width=$(( _cols - _table_width - 1 ))
                    _show_panel=1
                fi
            fi

            # ── Table column headers ───────────────────────────────────────
            local _n_headers=${#SHELLFRAME_TBL_HEADERS[@]}
            local _table_header_rows=0
            if (( _n_headers > 0 )); then
                _table_header_rows=2
                printf '\033[%d;1H  ' "$_content_top"
                local _hi
                for (( _hi=0; _hi<_n_headers; _hi++ )); do
                    local _hdr="${SHELLFRAME_TBL_HEADERS[$_hi]}"
                    local _hw="${SHELLFRAME_TBL_COL_WIDTHS[$_hi]:-${#_hdr}}"
                    printf '%b%-*s%b' \
                        "$SHELLFRAME_BOLD$SHELLFRAME_WHITE" "$_hw" "$_hdr" \
                        "$SHELLFRAME_RESET"
                done
                printf '\033[%d;1H  %b' "$(( _content_top + 1 ))" "$SHELLFRAME_GRAY"
                for (( _fi=0; _fi<_table_width-2; _fi++ )); do printf '─'; done
                printf '%b' "$SHELLFRAME_RESET"
            fi

            # ── Data rows ─────────────────────────────────────────────────
            local _first_data_row=$(( _content_top + _table_header_rows ))
            local _below_rows=${SHELLFRAME_TBL_BELOW_ROWS:-0}
            local _below_total=0
            (( _below_rows > 0 )) && _below_total=$(( _below_rows + 1 )) || true
            local _hint_row=$(( _content_bottom - _below_total ))
            local _visible_rows=$(( _hint_row - _first_data_row ))
            (( _visible_rows < 1 )) && _visible_rows=1

            # Scroll adjustment
            _shellframe_table_scroll_check "$_visible_rows"

            local _dai
            for (( _dai=0; _dai<_visible_rows; _dai++ )); do
                local _ridx=$(( SHELLFRAME_TBL_SCROLL + _dai ))
                local _drow=$(( _first_data_row + _dai ))
                printf '\033[%d;1H\033[2K' "$_drow"
                if (( _ridx < _n )); then
                    local _dlabel="${SHELLFRAME_TBL_LABELS[$_ridx]}"
                    local _dacts_str="${SHELLFRAME_TBL_ACTIONS[$_ridx]}"
                    local _daidx="${SHELLFRAME_TBL_IDX[$_ridx]}"
                    local _dmeta="${SHELLFRAME_TBL_META[$_ridx]:-}"
                    if [[ -n "$_draw_row_fn" ]]; then
                        "$_draw_row_fn" "$_ridx" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                    else
                        _tbl_default_draw_row "$_ridx" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                    fi
                fi
            done

            printf '\033[%d;1H\033[2K  %b%s%b' \
                "$_hint_row" \
                "$SHELLFRAME_GRAY" "$_footer" "$SHELLFRAME_RESET"

            if (( _show_panel )); then
                local _sep_row
                for (( _sep_row=_content_top; _sep_row<=_content_bottom; _sep_row++ )); do
                    printf '\033[%d;%dH%b│%b' \
                        "$_sep_row" "$(( _table_width + 1 ))" \
                        "$SHELLFRAME_GRAY" "$SHELLFRAME_RESET"
                done
                "$SHELLFRAME_TBL_PANEL_FN" \
                    "$_content_top" "$_panel_left" "$_panel_width" \
                    "$_content_height"
            fi

            if (( _below_total > 0 )) && [[ -n "$SHELLFRAME_TBL_BELOW_FN" ]]; then
                printf '\033[%d;1H\033[2K  %b' "$(( _hint_row + 1 ))" "$SHELLFRAME_GRAY"
                for (( _fi=0; _fi<_table_width-2; _fi++ )); do printf '─'; done
                printf '%b' "$SHELLFRAME_RESET"
                "$SHELLFRAME_TBL_BELOW_FN" \
                    "$(( _hint_row + 2 ))" 1 "$_cols" "$_below_rows"
            fi

            # Save layout cache for partial draws (assigned without 'local' —
            # updates shellframe_table's outer-scope locals via dynamic scoping)
            _tbl_ct=$_content_top
            _tbl_fdr=$_first_data_row
            _tbl_vr=$_visible_rows
            _tbl_sp=$_show_panel
            _tbl_pl=$_panel_left
            _tbl_pw=$_panel_width
            _tbl_ch=$_content_height

        else
            # ── Partial redraw (_dirty=1) ─────────────────────────────────
            # Overwrite old and new cursor rows using cached layout.
            # Terminal row = _tbl_fdr + (item_index - SHELLFRAME_TBL_SCROLL)
            local _dr
            for _dr in "$_prev_sel" "$SHELLFRAME_TBL_SELECTED"; do
                local _term_row=$(( _tbl_fdr + _dr - SHELLFRAME_TBL_SCROLL ))
                printf '\033[%d;1H\033[2K' "$_term_row"
                if (( _dr < _n )); then
                    local _dlabel="${SHELLFRAME_TBL_LABELS[$_dr]}"
                    local _dacts_str="${SHELLFRAME_TBL_ACTIONS[$_dr]}"
                    local _daidx="${SHELLFRAME_TBL_IDX[$_dr]}"
                    local _dmeta="${SHELLFRAME_TBL_META[$_dr]:-}"
                    if [[ -n "$_draw_row_fn" ]]; then
                        "$_draw_row_fn" "$_dr" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                    else
                        _tbl_default_draw_row "$_dr" "$_dlabel" "$_dacts_str" "$_daidx" "$_dmeta"
                    fi
                fi
            done

            # Panel repaints on every cursor movement (selection change drives content)
            # but does NOT clear the whole screen first.
            if (( _tbl_sp )); then
                "$SHELLFRAME_TBL_PANEL_FN" "$_tbl_ct" "$_tbl_pl" "$_tbl_pw" "$_tbl_ch"
            fi
        fi

        _dirty=0
    }
    _tbl_draw

    # ── Input loop ────────────────────────────────────────────────────────────
    local _tbl_retval=1
    while true; do
        local _key
        _prev_sel=$SHELLFRAME_TBL_SELECTED   # snapshot before key handling
        shellframe_read_key _key

        _shellframe_table_on_key "$_key" "$_n"
        local _krc=$?

        if   (( _krc == 2 )); then
            _tbl_retval=0; break
        elif (( _krc == 3 )); then
            _tbl_retval=1; break
        elif (( _krc == 0 )); then
            _dirty=1
        elif [[ -n "$_extra_key_fn" ]]; then
            "$_extra_key_fn" "$_key"
            local _xrc=$?
            if   (( _xrc == 2 )); then
                _tbl_retval=1; break
            elif (( _xrc == 1 )); then
                continue   # not handled — skip redraw
            fi
            _dirty=2   # _xrc == 0: handled — conservative full redraw
        else
            continue  # unrecognized key — skip redraw
        fi

        _tbl_draw
    done

    # ── Teardown ──────────────────────────────────────────────────────────
    trap - INT TERM
    _tbl_exit

    return $_tbl_retval
}
