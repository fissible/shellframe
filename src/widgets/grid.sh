#!/usr/bin/env bash
# shellframe/src/widgets/grid.sh — Data grid widget (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/selection.sh, src/scroll.sh, src/draw.sh.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a scrollable 2-D data grid with a sticky header row, per-column
# widths, │ column separators, and independent V (row) + H (column) scroll.
# Row selection via selection.sh; column panning via scroll.sh's horizontal axis.
#
# Multiple grid instances can coexist using different SHELLFRAME_GRID_CTX values.
#
# ── Data representation ───────────────────────────────────────────────────────
#
# Cell data is stored in a flat 1-D array indexed as:
#
#   SHELLFRAME_GRID_DATA[ row * SHELLFRAME_GRID_COLS + col ]
#
# Row and column indices are 0-based.  Callers must set SHELLFRAME_GRID_ROWS and
# SHELLFRAME_GRID_COLS before calling shellframe_grid_init.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_GRID_HEADERS[@]     — column header labels (plain text)
#   SHELLFRAME_GRID_COL_WIDTHS[@]  — visible character width per column.
#                                    Embed any desired padding in these widths;
#                                    the grid adds │ separators automatically.
#   SHELLFRAME_GRID_DATA[@]        — flat cell array: data[row*COLS + col]
#   SHELLFRAME_GRID_ROWS           — number of data rows
#   SHELLFRAME_GRID_COLS           — number of columns
#   SHELLFRAME_GRID_PK_COLS        — number of leading primary-key columns
#                                    (default 0 = no PK highlight).
#                                    When > 0, the separator after column
#                                    PK_COLS-1 is drawn as ┃ (thick) and the
#                                    header junction as ╋ instead of ┼.
#   SHELLFRAME_GRID_COL_ALIGN[@]   — per-column alignment: "left" | "right" | "center"
#                                    Defaults to "left" when empty or unset for a column.
#   SHELLFRAME_GRID_CTX            — context name (default: "grid")
#   SHELLFRAME_GRID_MULTISELECT    — 0 (default) | 1  (Space toggles selection)
#   SHELLFRAME_GRID_FOCUSED        — 0 (default) | 1
#   SHELLFRAME_GRID_FOCUSABLE      — 1 (default) | 0
#
# ── Column separators ─────────────────────────────────────────────────────────
#
# A │ separator is placed between every pair of adjacent visible columns.
# No separator appears after the last column overall.  Separators that would
# fall outside the render region are silently omitted.
#
# When SHELLFRAME_GRID_PK_COLS > 0 the separator immediately after the last
# PK column (i.e. between column PK_COLS-1 and column PK_COLS) is drawn as:
#   ┃  in data rows and the header label row
#   ╋  in the header ─── separator row (instead of ┼)
# All other separators are │ / ┼.
#
# ── State globals (readable after init / on_key) ──────────────────────────────
#
#   Read cursor row via:  shellframe_sel_cursor  "$SHELLFRAME_GRID_CTX"
#   Read V scroll via:    shellframe_scroll_top  "$SHELLFRAME_GRID_CTX"
#   Read H scroll via:    shellframe_scroll_left "$SHELLFRAME_GRID_CTX"
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_grid_init [ctx] [viewport_rows]
#     Initialise (or reset) selection + scroll for the current grid globals.
#     Must be called after any change to SHELLFRAME_GRID_ROWS/COLS.
#
#   shellframe_grid_render top left width height
#     Draw the grid within the given region.  All output to /dev/tty.
#     Layout (when height ≥ 3 and SHELLFRAME_GRID_HEADERS is non-empty):
#       Row  top       — header row  (bold white column labels + │/┃ separators)
#       Row  top+1     — ─── separator row (┼/╋ at column separator positions)
#       Rows top+2 ..  — data rows (vertically scrollable; cursor in reverse video)
#     When no headers, data rows occupy all rows.
#
#   shellframe_grid_on_key key
#     Returns:
#       0  — key handled (app shell should redraw)
#       1  — key not handled (pass to next handler)
#       2  — Enter pressed (row confirmed; read cursor via shellframe_sel_cursor)
#
#   shellframe_grid_on_focus focused  — set SHELLFRAME_GRID_FOCUSED
#
#   shellframe_grid_size              — print "3 3 0 0"
#
# ── Built-in key bindings ─────────────────────────────────────────────────────
#   Up / Down          — move row cursor
#   Left / Right       — pan column viewport (horizontal scroll, 1 column/step)
#   Page Up / Down     — move cursor + scroll by viewport height
#   Home / End         — jump to first / last row
#   Enter              — confirm; on_key returns 2
#   Space              — toggle multi-select (when SHELLFRAME_GRID_MULTISELECT=1)

SHELLFRAME_GRID_CTX="grid"
SHELLFRAME_GRID_MULTISELECT=0
SHELLFRAME_GRID_FOCUSED=0
SHELLFRAME_GRID_FOCUSABLE=1
SHELLFRAME_GRID_PK_COLS=0
SHELLFRAME_GRID_HEADERS=()
SHELLFRAME_GRID_COL_WIDTHS=()
SHELLFRAME_GRID_COL_ALIGN=()
SHELLFRAME_GRID_DATA=()
SHELLFRAME_GRID_ROWS=0
SHELLFRAME_GRID_COLS=0
SHELLFRAME_GRID_BG=""
SHELLFRAME_GRID_STRIPE_BG=""
SHELLFRAME_GRID_CURSOR_STYLE=""

# ── shellframe_grid_init ───────────────────────────────────────────────────────

# Initialise selection and scroll state.  Call after loading grid data.
#   ctx           — context name (default: SHELLFRAME_GRID_CTX)
#   viewport_rows — initial viewport height estimate (default 10; render updates)
shellframe_grid_init() {
    local _ctx="${1:-${SHELLFRAME_GRID_CTX:-grid}}"
    local _vrows="${2:-10}"
    local _nrows="${SHELLFRAME_GRID_ROWS:-0}"
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    shellframe_sel_init "$_ctx" "$_nrows"
    # H-scroll: content = n_cols columns, viewport starts conservative (1 visible
    # column).  render() calls shellframe_scroll_resize with the actual count so
    # clamping is correct before any keypress is processed.
    local _init_vcols=1
    (( _ncols <= 1 )) && _init_vcols="$_ncols"
    shellframe_scroll_init "$_ctx" "$_nrows" "$_ncols" "$_vrows" "$_init_vcols"
}

# ── shellframe_grid_render ─────────────────────────────────────────────────────

shellframe_grid_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _ctx="${SHELLFRAME_GRID_CTX:-grid}"
    local _multi="${SHELLFRAME_GRID_MULTISELECT:-0}"
    local _nrows="${SHELLFRAME_GRID_ROWS:-0}"
    local _ncols="${SHELLFRAME_GRID_COLS:-0}"
    local _pk_cols="${SHELLFRAME_GRID_PK_COLS:-0}"

    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"
    local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"
    local _bold="${SHELLFRAME_BOLD:-$'\033[1m'}"
    local _gray="${SHELLFRAME_GRAY:-$'\033[90m'}"
    local _white="${SHELLFRAME_WHITE:-$'\033[37m'}"

    # ── Layout: header + separator occupy rows top and top+1 ──────────────────
    local _has_header=0
    local _data_top="$_top"
    local _data_height="$_height"
    local _n_headers=0
    if [[ -n "${SHELLFRAME_GRID_HEADERS+set}" ]]; then
        _n_headers=${#SHELLFRAME_GRID_HEADERS[@]}
    fi

    if (( _ncols > 0 && _n_headers > 0 && _height >= 3 )); then
        _has_header=1
        _data_top=$(( _top + 2 ))
        _data_height=$(( _height - 2 ))
    fi

    # ── Compute visible columns and separator positions ────────────────────────
    #
    # Each column occupies COL_WIDTHS[c] pixels.  Between adjacent columns a 1-px
    # │ or ┃ separator is inserted (except after the last column globally).
    # _vis_cols[vi]    — actual column index of the vi-th visible column
    # _vis_x[vi]       — pixel offset (from _left) of the vi-th visible column
    # _vis_sep_x[vi]   — pixel offset of the separator after column vi
    # _vis_sep_char[vi] — │ or ┃  (data rows)
    # _vis_sep_junc[vi] — ┼ or ╋  (header ─── row junction)
    # Separators are only recorded when they fit within the render width.

    local _hscroll_left=0
    shellframe_scroll_left "$_ctx" _hscroll_left

    local -a _vis_cols
    local -a _vis_x
    local -a _vis_sep_x
    local -a _vis_sep_char
    local -a _vis_sep_junc
    _vis_cols=()
    _vis_x=()
    _vis_sep_x=()
    _vis_sep_char=()
    _vis_sep_junc=()

    local _px=0 _ci
    for (( _ci=_hscroll_left; _ci<_ncols; _ci++ )); do
        local _cw="${SHELLFRAME_GRID_COL_WIDTHS[$_ci]:-10}"
        if (( _px >= _width )); then break; fi
        _vis_cols+=("$_ci")
        _vis_x+=("$_px")
        _px=$(( _px + _cw ))

        # Add separator after this column when:
        #   (a) it is not the last column globally, and
        #   (b) the separator pixel position (_px) is within the render region.
        if (( _ci < _ncols - 1 && _px < _width )); then
            if (( _pk_cols > 0 && _ci + 1 == _pk_cols )); then
                _vis_sep_char+=("┃")
                _vis_sep_junc+=("╋")
            else
                _vis_sep_char+=("│")
                _vis_sep_junc+=("┼")
            fi
            _vis_sep_x+=("$_px")
            _px=$(( _px + 1 ))   # 1-px separator
        fi
    done

    local _n_vis_cols=0
    (( ${#_vis_cols[@]} > 0 )) && _n_vis_cols=${#_vis_cols[@]}
    local _n_vis_seps=0
    (( ${#_vis_sep_x[@]} > 0 )) && _n_vis_seps=${#_vis_sep_x[@]}

    # Compute _trailing_vis_cols: how many tail columns fit in _width when starting
    # from the right end, using pixel arithmetic.  This gives the correct _max_left
    # so the last column is always fully visible at maximum scroll — not partially
    # clipped as it would be if _n_vis_cols (computed at the current scroll position)
    # were used instead.
    local _trailing_vis_cols=0 _trailing_px=0 _tcw _tneed
    for (( _ci=_ncols-1; _ci>=0; _ci-- )); do
        _tcw="${SHELLFRAME_GRID_COL_WIDTHS[$_ci]:-10}"
        _tneed=$(( _trailing_vis_cols > 0 ? _tcw + 1 : _tcw ))
        (( _trailing_px + _tneed > _width )) && break
        _trailing_px=$(( _trailing_px + _tneed ))
        (( _trailing_vis_cols++ ))
    done
    (( _trailing_vis_cols < 1 )) && _trailing_vis_cols=1

    # Detect right end-of-data border: draw │ after the last column when it is the
    # final column globally AND it fully fits within the render region.
    local _right_border_x=-1
    if (( _n_vis_cols > 0 && _ncols > 0 )); then
        local _last_vi=$(( _n_vis_cols - 1 ))
        local _last_ci="${_vis_cols[$_last_vi]}"
        local _last_end=$(( ${_vis_x[$_last_vi]} + ${SHELLFRAME_GRID_COL_WIDTHS[$_last_ci]:-10} ))
        if (( _last_ci == _ncols - 1 && _last_end < _width )); then
            _right_border_x=$_last_end
        fi
    fi

    # Update scroll viewport dimensions so clamping is correct on the next keypress.
    shellframe_scroll_resize "$_ctx" "$_data_height" "$_trailing_vis_cols"

    local _grid_bg="${SHELLFRAME_GRID_BG:-}"

    # ── Header label row ──────────────────────────────────────────────────────
    if (( _has_header )); then
        printf '\033[%d;%dH%s%*s\033[%d;%dH' "$_top" "$_left" "$_grid_bg" "$_width" '' "$_top" "$_left" >&3

        local _vi
        for (( _vi=0; _vi<_n_vis_cols; _vi++ )); do
            _ci="${_vis_cols[$_vi]}"
            local _xoff="${_vis_x[$_vi]}"
            local _cw="${SHELLFRAME_GRID_COL_WIDTHS[$_ci]:-10}"
            local _hdr=""
            (( _ci < _n_headers )) && _hdr="${SHELLFRAME_GRID_HEADERS[$_ci]}"
            local _pad_xoff=$(( _xoff + 1 ))
            local _avail=$(( _width - _pad_xoff ))
            (( _avail > _cw - 1 )) && _avail=$(( _cw - 1 ))
            (( _avail <= 0 )) && continue
            local _clipped
            _clipped=$(shellframe_str_clip_ellipsis "$_hdr" \
                "${_bold}${_white}${_hdr}${_rst}" "$_avail")
            printf '\033[%d;%dH%s' "$_top" "$(( _left + _pad_xoff ))" "$_clipped" >&3

            # Separator after this header
            if (( _vi < _n_vis_seps )); then
                printf '\033[%d;%dH%s%s%s' \
                    "$_top" "$(( _left + ${_vis_sep_x[$_vi]} ))" \
                    "$_gray" "${_vis_sep_char[$_vi]}" "$_rst" >&3
            fi
        done

        # Right end-of-data border in header label row
        if (( _right_border_x >= 0 )); then
            printf '\033[%d;%dH%s│%s' \
                "$_top" "$(( _left + _right_border_x ))" "$_gray" "$_rst" >&3
        fi

        # ── Header separator row: ─── with ┼/╋ at column separator positions ──
        printf '\033[%d;%dH%s%s' "$(( _top + 1 ))" "$_left" "$_grid_bg" "$_gray" >&3
        local _prev_x=0 _bvi
        for (( _bvi=0; _bvi<_n_vis_seps; _bvi++ )); do
            local _sep_x="${_vis_sep_x[$_bvi]}"
            # Dashes from _prev_x up to (but not including) the separator pixel
            local _bdi
            for (( _bdi=_prev_x; _bdi<_sep_x; _bdi++ )); do printf '─' >&3; done
            printf '%s' "${_vis_sep_junc[$_bvi]}" >&3
            _prev_x=$(( _sep_x + 1 ))
        done
        # Remaining dashes to the right edge (or to the right border position)
        local _dash_end=$(( _right_border_x >= 0 ? _right_border_x : _width ))
        local _bdi
        for (( _bdi=_prev_x; _bdi<_dash_end; _bdi++ )); do printf '─' >&3; done
        if (( _right_border_x >= 0 )); then printf '┘' >&3; fi
        printf '%s' "$_rst" >&3
    fi

    # ── Data rows ─────────────────────────────────────────────────────────────
    local _vscroll_top=0
    shellframe_scroll_top "$_ctx" _vscroll_top

    local _cursor=0
    shellframe_sel_cursor "$_ctx" _cursor 2>/dev/null \
        || _cursor=$(shellframe_sel_cursor "$_ctx")

    local _r
    for (( _r=0; _r<_data_height; _r++ )); do
        local _row=$(( _data_top + _r ))
        local _ridx=$(( _vscroll_top + _r ))

        printf '\033[%d;%dH%s%*s\033[%d;%dH' "$_row" "$_left" "$_grid_bg" "$_width" '' "$_row" "$_left" >&3
        [[ "$_ridx" -ge "$_nrows" ]] && continue

        # Apply stripe background to even data rows
        if [[ -n "${SHELLFRAME_GRID_STRIPE_BG:-}" ]] && (( _ridx % 2 == 1 )); then
            printf '\033[%d;%dH%s%*s' "$_row" "$_left" "$SHELLFRAME_GRID_STRIPE_BG" "$_width" '' >&3
            printf '\033[%d;%dH' "$_row" "$_left" >&3
        fi

        local _is_cursor=0
        (( _ridx == _cursor && ${SHELLFRAME_GRID_FOCUSED:-0} )) && _is_cursor=1

        # Multi-select checkbox prefix for the first visible column
        local _prefix=""
        if (( _multi )); then
            if shellframe_sel_is_selected "$_ctx" "$_ridx"; then
                _prefix="[x] "
            else
                _prefix="[ ] "
            fi
        fi

        # Activate reverse video for the entire cursor row before writing any cell.
        # The attribute persists through absolute cursor moves, so all subsequent
        # cells and separators will be rendered in reverse video.
        if (( _is_cursor )); then
            local _cursor_attr="${SHELLFRAME_GRID_CURSOR_STYLE:-$_rev}"
            printf '\033[%d;%dH%s' "$_row" "$_left" "$_cursor_attr" >&3
        fi

        local _vi
        for (( _vi=0; _vi<_n_vis_cols; _vi++ )); do
            _ci="${_vis_cols[$_vi]}"
            local _xoff="${_vis_x[$_vi]}"
            local _cw="${SHELLFRAME_GRID_COL_WIDTHS[$_ci]:-10}"
            local _pad_xoff=$(( _xoff + 1 ))
            local _avail=$(( _width - _pad_xoff ))
            (( _avail > _cw - 1 )) && _avail=$(( _cw - 1 ))
            (( _avail <= 0 )) && continue

            local _didx=$(( _ridx * _ncols + _ci ))
            local _cell=""
            if (( _didx < ${#SHELLFRAME_GRID_DATA[@]} )); then
                _cell="${SHELLFRAME_GRID_DATA[$_didx]}"
            fi

            local _text="$_cell"
            (( _vi == 0 && _multi )) && _text="${_prefix}${_cell}"

            local _tlen="${#_text}"
            local _align="${SHELLFRAME_GRID_COL_ALIGN[$_ci]:-left}"
            printf '\033[%d;%dH' "$_row" "$(( _left + _pad_xoff ))" >&3
            if (( _tlen > _avail )); then
                # Text wider than column — clip with ellipsis (subshell only here)
                local _clipped
                _clipped=$(shellframe_str_clip_ellipsis "$_text" "$_text" "$_avail")
                printf '%s' "$_clipped" >&3
            else
                local _pad=$(( _avail - _tlen ))
                case "$_align" in
                    right)
                        (( _pad > 0 )) && printf '%*s' "$_pad" '' >&3
                        printf '%s' "$_text" >&3
                        ;;
                    center)
                        local _lpad=$(( _pad / 2 ))
                        (( _lpad > 0 )) && printf '%*s' "$_lpad" '' >&3
                        printf '%s' "$_text" >&3
                        local _rpad=$(( _pad - _lpad ))
                        (( _rpad > 0 )) && printf '%*s' "$_rpad" '' >&3
                        ;;
                    *)  # left (default)
                        printf '%s' "$_text" >&3
                        (( _pad > 0 )) && printf '%*s' "$_pad" '' >&3
                        ;;
                esac
            fi

            # Separator after this column.
            # Cursor row: separator inherits the active reverse-video attribute.
            # Non-cursor row: gray separator, then reset back to normal.
            if (( _vi < _n_vis_seps )); then
                local _sxoff="${_vis_sep_x[$_vi]}"
                local _schar="${_vis_sep_char[$_vi]}"
                if (( _is_cursor )); then
                    printf '\033[%d;%dH%s' \
                        "$_row" "$(( _left + _sxoff ))" "$_schar" >&3
                else
                    printf '\033[%d;%dH%s%s%s' \
                        "$_row" "$(( _left + _sxoff ))" \
                        "$_gray" "$_schar" "$_rst" >&3
                fi
            fi
        done

        (( _is_cursor )) && printf '%s' "$_rst" >&3

        # Right end-of-data border in data row (only for rows that have data)
        if (( _right_border_x >= 0 && _ridx < _nrows )); then
            printf '\033[%d;%dH%s│%s' \
                "$_row" "$(( _left + _right_border_x ))" "$_gray" "$_rst" >&3
        fi
    done

    # Leave cursor at last row, column left (component contract)
    printf '\033[%d;%dH' "$(( _top + _height - 1 ))" "$_left" >&3
}

# ── shellframe_grid_on_key ─────────────────────────────────────────────────────

shellframe_grid_on_key() {
    local _key="$1"
    local _ctx="${SHELLFRAME_GRID_CTX:-grid}"

    # Read current viewport rows from scroll state (updated by render/resize)
    local _vr_var="_SHELLFRAME_SCROLL_${_ctx}_VROWS"
    local _vrows="${!_vr_var:-10}"

    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"
    local _k_enter="${SHELLFRAME_KEY_ENTER:-$'\n'}"

    if [[ "$_key" == "$_k_enter" ]] || [[ "$_key" == $'\r' ]]; then
        return 2    # row confirmed
    elif [[ "$_key" == "$_k_down" ]]; then
        shellframe_sel_move "$_ctx" down
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        return 0
    elif [[ "$_key" == "$_k_up" ]]; then
        shellframe_sel_move "$_ctx" up
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        return 0
    elif [[ "$_key" == "$_k_right" ]]; then
        shellframe_scroll_move "$_ctx" right
        return 0
    elif [[ "$_key" == "$_k_left" ]]; then
        shellframe_scroll_move "$_ctx" left
        return 0
    elif [[ "$_key" == "$_k_pgdn" ]]; then
        shellframe_sel_move "$_ctx" page_down "$_vrows"
        shellframe_scroll_move "$_ctx" page_down
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        return 0
    elif [[ "$_key" == "$_k_pgup" ]]; then
        shellframe_sel_move "$_ctx" page_up "$_vrows"
        shellframe_scroll_move "$_ctx" page_up
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        return 0
    elif [[ "$_key" == "$_k_home" ]]; then
        shellframe_sel_move "$_ctx" home
        shellframe_scroll_move "$_ctx" home
        return 0
    elif [[ "$_key" == "$_k_end" ]]; then
        shellframe_sel_move "$_ctx" end
        shellframe_scroll_move "$_ctx" end
        return 0
    elif [[ "$_key" == " " ]] && (( ${SHELLFRAME_GRID_MULTISELECT:-0} )); then
        shellframe_sel_toggle "$_ctx"
        return 0
    fi

    return 1
}

# ── shellframe_grid_on_focus ───────────────────────────────────────────────────

shellframe_grid_on_focus() {
    SHELLFRAME_GRID_FOCUSED="${1:-0}"
}

# ── shellframe_grid_size ───────────────────────────────────────────────────────

# min: 3 rows × 3 cols (header + separator + 1 data row; at least one cell wide)
# preferred: fill all available space (0×0)
shellframe_grid_size() {
    printf '%d %d %d %d' 3 3 0 0
}
