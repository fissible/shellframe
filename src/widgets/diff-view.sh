#!/usr/bin/env bash
# shellframe/src/widgets/diff-view.sh — Side-by-side diff viewer
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: split.sh, diff.sh, sync-scroll.sh, scroll.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a parsed diff (from shellframe_diff_parse) as a side-by-side view
# in a 2-pane split.  Left pane shows the old version, right pane shows the
# new version.  Scrolling is synchronized.
#
# Highlights:
#   - Changed lines: left in red, right in green
#   - Added lines: green on right, blank on left
#   - Deleted lines: red on left, blank on right
#   - Context lines: dimmed on both sides
#   - Separator rows: centered "───" indicator
#   - Line numbers in the gutter
#
# ── Input globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_DIFF_TYPES[]   — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_LEFT[]    — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_RIGHT[]   — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_LNUMS[]   — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_RNUMS[]   — populated by shellframe_diff_parse
#   SHELLFRAME_DIFF_ROW_COUNT — populated by shellframe_diff_parse
#
# ── Public API ──────────────────────────────────────────────────────────────
#
#   shellframe_diff_view_init
#     Initialise split, scroll, and sync-scroll contexts for the diff view.
#     Call after shellframe_diff_parse.
#
#   shellframe_diff_view_render top left width height
#     Render the full diff view (separator + both panes).
#
#   shellframe_diff_view_on_key key
#     Handle scroll keys.  Returns 0 if handled, 1 if not.
#
#   shellframe_diff_view_on_focus focused
#     Track focus state for visual indicator.

SHELLFRAME_DIFF_VIEW_FOCUSED=0
SHELLFRAME_DIFF_VIEW_LEFT_FOCUSED=0    # per-pane focus (for split-region mode)
SHELLFRAME_DIFF_VIEW_RIGHT_FOCUSED=0
SHELLFRAME_DIFF_VIEW_FOCUS_ACCENT=""   # ANSI sequence for focused pane accent (title bar bg)
SHELLFRAME_DIFF_VIEW_HIDE_FILE_HDR=0  # 1 to skip rendering file header rows

# Pane footer labels — set by the caller before render
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER=""     # left side: ref + tag + sha + subject
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER=""    # right side: ref + tag + sha + subject
SHELLFRAME_DIFF_VIEW_LEFT_DATE=""       # right-aligned date for left pane
SHELLFRAME_DIFF_VIEW_RIGHT_DATE=""      # right-aligned date for right pane

# File header styling — set by the caller for a custom look, or leave empty for default
SHELLFRAME_DIFF_VIEW_FILE_HDR_ON=""     # ANSI sequence to start file header
SHELLFRAME_DIFF_VIEW_FILE_HDR_OFF=""    # ANSI sequence to end file header

# Syntax-highlighted content — parallel arrays indexed by diff row.
# If set and non-empty for a row, used instead of plain text for ctx lines.
# Caller populates these (e.g. via bat). Leave empty to disable.
SHELLFRAME_DIFF_VIEW_HL_LEFT=()
SHELLFRAME_DIFF_VIEW_HL_RIGHT=()
SHELLFRAME_DIFF_VIEW_HL_ENABLED=0

# Gutter width: space(1) + linenum(4) + space(1) + space(1) + indicator(1) + space(1) = 9
_SHELLFRAME_DV_GUTTER=9

# ── shellframe_diff_view_init ───────────────────────────────────────────────

# Extra blank rows at the end of content so "end of diff" is visually clear
_SHELLFRAME_DV_PADDING=5

shellframe_diff_view_init() {
    shellframe_split_init "dv_split" "v" 2 "0:0"

    # Scroll contexts — total rows = diff row count + padding buffer
    local _total=$(( ${SHELLFRAME_DIFF_ROW_COUNT:-0} + _SHELLFRAME_DV_PADDING ))
    shellframe_scroll_init "dv_left"  "$_total" 1 1 1
    shellframe_scroll_init "dv_right" "$_total" 1 1 1

    shellframe_sync_scroll_init "dv_sync" "dv_left" "dv_right"
}

# ── _shellframe_dv_clip_ansi ─────────────────────────────────────────────────
#
# Clip an ANSI-colored string to a visible width.  Walks the string,
# skips escape sequences (which are zero-width), counts visible chars.
# Usage: _shellframe_dv_clip_ansi "string" width out_var

_shellframe_dv_clip_ansi() {
    local _str="$1" _max="$2" _out="$3"
    local _result="" _vis=0 _i=0 _len=${#_str}

    while (( _i < _len && _vis < _max )); do
        local _ch="${_str:$_i:1}"
        if [[ "$_ch" == $'\033' ]]; then
            # Start of escape sequence — copy until 'm' (end of SGR)
            local _seq="$_ch"
            (( _i++ ))
            while (( _i < _len )); do
                _ch="${_str:$_i:1}"
                _seq+="$_ch"
                (( _i++ ))
                [[ "$_ch" == "m" ]] && break
            done
            _result+="$_seq"
        else
            _result+="$_ch"
            (( _vis++ ))
            (( _i++ ))
        fi
    done

    printf -v "$_out" '%s' "$_result"
}

# ── _shellframe_dv_render_pane ──────────────────────────────────────────────

# Render one side of the diff (left or right).
# _shellframe_dv_render_pane top left width height side
#   side: "left" | "right"
_shellframe_dv_render_pane() {
    local _top="$1" _left="$2" _width="$3" _height="$4" _side="$5"

    local _scroll_ctx="dv_${_side}"
    local _gutter="$_SHELLFRAME_DV_GUTTER"
    local _content_w=$(( _width - _gutter ))
    (( _content_w < 1 )) && _content_w=1

    # Update scroll viewport and total rows (padding = viewport height so
    # the last file can be scrolled to the top for selection)
    local _total=$(( SHELLFRAME_DIFF_ROW_COUNT + _height ))
    local _rows_var="_SHELLFRAME_SCROLL_${_scroll_ctx}_ROWS"
    printf -v "$_rows_var" '%d' "$_total"
    shellframe_scroll_resize "$_scroll_ctx" "$_height" "$_content_w"

    local _scroll_top
    shellframe_scroll_top "$_scroll_ctx" _scroll_top

    local _reset="${SHELLFRAME_RESET:-}"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _bold="${SHELLFRAME_BOLD:-}"
    local _reverse="${SHELLFRAME_REVERSE:-}"

    # Add: brighter green text, slightly tinted green bg
    # Del: warmer red text, slightly tinted red bg
    # Different bg tints so add/del are distinguishable even without reading text
    local _add_on=$'\033[48;5;22m\033[38;5;114m'      # green text, dark green bg
    local _del_on=$'\033[48;5;52m\033[38;5;174m'      # warm red text, dark red bg
    local _add_ind=$'\033[38;5;78m'                    # brighter green indicator
    local _del_ind=$'\033[38;5;167m'                   # warmer red indicator

    # Per-pane focus: check side-specific focus, fall back to widget-level
    local _pane_focused=0
    if [[ "$_side" == "left" ]]; then
        _pane_focused="${SHELLFRAME_DIFF_VIEW_LEFT_FOCUSED:-$SHELLFRAME_DIFF_VIEW_FOCUSED}"
    else
        _pane_focused="${SHELLFRAME_DIFF_VIEW_RIGHT_FOCUSED:-$SHELLFRAME_DIFF_VIEW_FOCUSED}"
    fi

    # When unfocused, dim all content so the focused pane stands out
    local _dim="" _undim=""
    if (( ! _pane_focused )); then
        _dim=$'\033[2m'
        _undim="${_reset}"
    fi

    # Build all output into a buffer (no subshells), then write once
    local _buf="" _tmp=""

    local _fh_on="${SHELLFRAME_DIFF_VIEW_FILE_HDR_ON:-${_bold}${_reverse}}"
    local _fh_off="${SHELLFRAME_DIFF_VIEW_FILE_HDR_OFF:-${_reset}}"

    # ── Sticky file header ────────────────────────────────────────────
    # If the top visible row is not a file header, pin the current file's
    # header at row 0 of the pane. The header disappears naturally when
    # the next file's own header row scrolls into view.
    local _sticky_row=-1  # -1 = no sticky header needed
    local _content_start=0

    if (( SHELLFRAME_DIFF_ROW_COUNT > 0 && _scroll_top < SHELLFRAME_DIFF_ROW_COUNT )); then
        local _top_type="${SHELLFRAME_DIFF_TYPES[$_scroll_top]}"
        if [[ "$_top_type" != "hdr" && "$_top_type" != "file_sep" ]]; then
            # Find which file owns the current scroll position
            local _sticky_fi=-1 _si
            for (( _si=0; _si < ${#SHELLFRAME_DIFF_FILE_ROWS[@]}; _si++ )); do
                if (( SHELLFRAME_DIFF_FILE_ROWS[_si] <= _scroll_top )); then
                    _sticky_fi=$_si
                fi
            done
            if (( _sticky_fi >= 0 )); then
                _sticky_row="${SHELLFRAME_DIFF_FILE_ROWS[$_sticky_fi]}"
                _content_start=1  # reserve row 0 for the sticky header
            fi
        fi
    fi

    # Render sticky header on row 0 if needed
    if (( _sticky_row >= 0 )); then
        local _stext
        if [[ "$_side" == "left" ]]; then
            _stext="${SHELLFRAME_DIFF_LEFT[$_sticky_row]}"
        else
            _stext="${SHELLFRAME_DIFF_RIGHT[$_sticky_row]}"
        fi

        local _sfstatus="modified" _sfi
        for (( _sfi=0; _sfi < ${#SHELLFRAME_DIFF_FILE_ROWS[@]}; _sfi++ )); do
            if (( SHELLFRAME_DIFF_FILE_ROWS[_sfi] == _sticky_row )); then
                _sfstatus="${SHELLFRAME_DIFF_FILE_STATUS[$_sfi]:-modified}"
                break
            fi
        done

        local _sstatus="" _scolor=""
        if [[ "$_side" == "left" ]]; then
            case "$_sfstatus" in
                deleted) _sstatus=" ✕ deleted"; _scolor="$_del_ind" ;;
                added)   _sstatus="" ;;
                *)       _sstatus=" ✎ modified"; _scolor="$_gray" ;;
            esac
        else
            case "$_sfstatus" in
                added)   _sstatus=" ✚ added"; _scolor="$_add_ind" ;;
                deleted) _sstatus="" ;;
                *)       _sstatus=" ✎ modified"; _scolor="$_gray" ;;
            esac
        fi

        local _shdr_inner=$(( _width - 2 ))
        local _sfname_max=$(( _shdr_inner - ${#_sstatus} ))
        local _sfname_clip="${_stext:0:$_sfname_max}"
        local _shdr_pad=$(( _shdr_inner - ${#_sfname_clip} - ${#_sstatus} ))
        (( _shdr_pad < 0 )) && _shdr_pad=0

        printf -v _tmp '\033[%d;%dH%*s\033[%d;%dH' \
            "$_top" "$_left" "$_width" "" "$_top" "$_left"
        _buf+="$_tmp"
        printf -v _tmp '%s▎%s%s%s%s%*s%s' \
            "$_fh_on" "$_bold" "$_sfname_clip" "$_reset$_fh_on" \
            "${_scolor}${_sstatus}${_reset}${_fh_on}" \
            "$_shdr_pad" "" "$_fh_off"
        _buf+="$_tmp"
    fi

    local _r
    for (( _r=_content_start; _r < _height; _r++ )); do
        local _row_idx=$(( _scroll_top + (_r - _content_start) ))
        local _screen_row=$(( _top + _r ))

        # Position cursor and clear the line area (printf -v, no fork)
        printf -v _tmp '\033[%d;%dH%*s\033[%d;%dH' \
            "$_screen_row" "$_left" "$_width" "" "$_screen_row" "$_left"
        _buf+="${_tmp}${_dim}"

        if (( _row_idx >= SHELLFRAME_DIFF_ROW_COUNT )); then
            _buf+="$_undim"
            continue
        fi

        local _type="${SHELLFRAME_DIFF_TYPES[$_row_idx]}"
        local _text _lnum

        if [[ "$_side" == "left" ]]; then
            _text="${SHELLFRAME_DIFF_LEFT[$_row_idx]}"
            _lnum="${SHELLFRAME_DIFF_LNUMS[$_row_idx]}"
        else
            _text="${SHELLFRAME_DIFF_RIGHT[$_row_idx]}"
            _lnum="${SHELLFRAME_DIFF_RNUMS[$_row_idx]}"
        fi

        case "$_type" in
            hdr)
                if (( SHELLFRAME_DIFF_VIEW_HIDE_FILE_HDR )); then
                    _buf+="$_undim"
                    continue
                fi
                # Look up file status for this header row
                local _fstatus="modified" _fi
                for (( _fi=0; _fi < ${#SHELLFRAME_DIFF_FILE_ROWS[@]}; _fi++ )); do
                    if (( SHELLFRAME_DIFF_FILE_ROWS[_fi] == _row_idx )); then
                        _fstatus="${SHELLFRAME_DIFF_FILE_STATUS[$_fi]:-modified}"
                        break
                    fi
                done

                local _status_label="" _status_color=""
                if [[ "$_side" == "left" ]]; then
                    case "$_fstatus" in
                        deleted) _status_label=" ✕ deleted"; _status_color="$_del_ind" ;;
                        added)   _status_label="" ;;
                        *)       _status_label=" ✎ modified"; _status_color="$_gray" ;;
                    esac
                else
                    case "$_fstatus" in
                        added)   _status_label=" ✚ added"; _status_color="$_add_ind" ;;
                        deleted) _status_label="" ;;
                        *)       _status_label=" ✎ modified"; _status_color="$_gray" ;;
                    esac
                fi

                # File header: ▎prefix + bold filename + status
                local _hdr_inner=$(( _width - 2 ))
                local _fname_max=$(( _hdr_inner - ${#_status_label} ))
                local _fname_clip="${_text:0:$_fname_max}"
                local _hdr_pad=$(( _hdr_inner - ${#_fname_clip} - ${#_status_label} ))
                (( _hdr_pad < 0 )) && _hdr_pad=0
                printf -v _tmp '%s▎%s%s%s%s%*s%s' \
                    "$_fh_on" "$_bold" "$_fname_clip" "$_reset$_fh_on" \
                    "${_status_color}${_status_label}${_reset}${_fh_on}" \
                    "$_hdr_pad" "" "$_fh_off"
                _buf+="${_tmp}${_undim}"
                continue
                ;;
            file_sep)
                if (( SHELLFRAME_DIFF_VIEW_HIDE_FILE_HDR )); then
                    _buf+="$_undim"
                    continue
                fi
                local _rule="" _rc
                for (( _rc=0; _rc < _width; _rc++ )); do _rule+="─"; done
                _buf+="${_gray}${_rule}${_reset}${_undim}"
                continue
                ;;
            sep)
                # Dark background matching line number zone, centered dots
                local _sep_bg=$'\033[48;5;233m'
                local _sep_txt=$'\033[38;5;241m'
                local _sep_label=" ···"
                local _sep_pad=$(( _width - ${#_sep_label} ))
                (( _sep_pad < 0 )) && _sep_pad=0
                printf -v _tmp '%s%s%s%*s%s' "$_sep_bg" "$_sep_txt" "$_sep_label" "$_sep_pad" "" "$_reset"
                _buf+="${_tmp}${_undim}"
                continue
                ;;
        esac

        # Detect blank opposite side (add on left, del on right)
        local _is_blank_opposite=0
        if [[ "$_type" == "add" && "$_side" == "left" ]]; then _is_blank_opposite=1; fi
        if [[ "$_type" == "del" && "$_side" == "right" ]]; then _is_blank_opposite=1; fi

        # Gutter: [dark: space linenum space] [change: space +/- space]
        local _indicator=" "
        case "$_type" in
            add) [[ "$_side" == "right" ]] && _indicator="+" ;;
            del) [[ "$_side" == "left" ]]  && _indicator="-" ;;
            chg) if [[ "$_side" == "left" ]]; then _indicator="-"; else _indicator="+"; fi ;;
        esac

        # Line number zone: slightly darker background
        local _ln_bg=$'\033[48;5;233m'  # very dark gray
        local _ln_fg=$'\033[38;5;252m'  # white-ish for line numbers
        if (( _is_blank_opposite )); then
            # Entire gutter dark on blank side
            printf -v _tmp '%s         %s' "$_ln_bg" "$_reset"
            _buf+="$_tmp"
        else
            if [[ -n "$_lnum" ]]; then
                printf -v _tmp '%s %s%4s %s' "$_ln_bg" "$_ln_fg" "$_lnum" "$_reset"
            else
                printf -v _tmp '%s      %s' "$_ln_bg" "$_reset"
            fi
            _buf+="$_tmp"

            # Change indicator zone: background matches the content change color
            local _ind_bg="" _ind_fg=""
            case "$_indicator" in
                "+") _ind_bg="${_add_on}"; _ind_fg="$_add_ind" ;;
                "-") _ind_bg="${_del_on}"; _ind_fg="$_del_ind" ;;
                *)   _ind_bg=""; _ind_fg="" ;;
            esac
            if [[ -n "$_ind_bg" ]]; then
                _buf+="${_ind_bg} ${_ind_fg}${_indicator}${_ind_bg} ${_reset}"
            else
                _buf+="   "
            fi
        fi

        # Content: expand tabs to spaces before measuring/clipping
        local _expanded="${_text//$'\t'/    }"
        local _display="${_expanded:0:$_content_w}"
        local _fill_n=$(( _content_w - ${#_display} ))
        (( _fill_n < 0 )) && _fill_n=0

        case "$_type" in
            ctx)
                # Use syntax-highlighted text if available, otherwise dim
                local _hl_text=""
                if (( SHELLFRAME_DIFF_VIEW_HL_ENABLED )) && (( _row_idx >= 0 )); then
                    if [[ "$_side" == "left" ]]; then
                        _hl_text="${SHELLFRAME_DIFF_VIEW_HL_LEFT[$_row_idx]:-}"
                    else
                        _hl_text="${SHELLFRAME_DIFF_VIEW_HL_RIGHT[$_row_idx]:-}"
                    fi
                fi
                if [[ -n "$_hl_text" ]]; then
                    # Always clip highlighted text — bat output may differ
                    # in visible width from our tab-expanded measurement
                    local _hl_clipped
                    _shellframe_dv_clip_ansi "$_hl_text" "$_content_w" _hl_clipped
                    _buf+="${_hl_clipped}${_reset}"
                else
                    _buf+=$'\033[38;5;245m'"${_display}${_reset}"
                fi
                ;;
            add)
                if [[ "$_side" == "right" ]]; then
                    printf -v _tmp '%s%s%*s%s' "$_add_on" "$_display" "$_fill_n" "" "$_reset"
                    _buf+="$_tmp"
                else
                    printf -v _tmp '%s%*s%s' "$_ln_bg" "$_content_w" "" "$_reset"
                    _buf+="$_tmp"
                fi
                ;;
            del)
                if [[ "$_side" == "left" ]]; then
                    printf -v _tmp '%s%s%*s%s' "$_del_on" "$_display" "$_fill_n" "" "$_reset"
                    _buf+="$_tmp"
                else
                    printf -v _tmp '%s%*s%s' "$_ln_bg" "$_content_w" "" "$_reset"
                    _buf+="$_tmp"
                fi
                ;;
            chg)
                if [[ "$_side" == "left" ]]; then
                    printf -v _tmp '%s%s%*s%s' "$_del_on" "$_display" "$_fill_n" "" "$_reset"
                    _buf+="$_tmp"
                else
                    printf -v _tmp '%s%s%*s%s' "$_add_on" "$_display" "$_fill_n" "" "$_reset"
                    _buf+="$_tmp"
                fi
                ;;
        esac
        _buf+="$_undim"
    done

    # Single write for the entire pane
    printf '%s' "$_buf" >&3
}

# ── shellframe_diff_view_render ─────────────────────────────────────────────

shellframe_diff_view_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"

    shellframe_split_init "dv_split" "v" 2 "0:0"

    # Reserve bottom row for pane footers if either footer is set
    local _content_h="$_height"
    local _has_footer=0
    if [[ -n "${SHELLFRAME_DIFF_VIEW_LEFT_FOOTER:-}" || -n "${SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER:-}" ]]; then
        _has_footer=1
        _content_h=$(( _height - 1 ))
        (( _content_h < 1 )) && _content_h=1
    fi

    # Draw the split separator (full height including footer row)
    shellframe_split_render "dv_split" "$_top" "$_left" "$_width" "$_height"

    # Compute pane bounds for content area (excluding footer)
    local _lt _ll _lw _lh _rt _rl _rw _rh
    shellframe_split_bounds "dv_split" 0 "$_top" "$_left" "$_width" "$_content_h" \
        _lt _ll _lw _lh
    shellframe_split_bounds "dv_split" 1 "$_top" "$_left" "$_width" "$_content_h" \
        _rt _rl _rw _rh

    # Render each pane
    _shellframe_dv_render_pane "$_lt" "$_ll" "$_lw" "$_lh" "left"
    _shellframe_dv_render_pane "$_rt" "$_rl" "$_rw" "$_rh" "right"

    # Render pane footers (use full-height bounds for correct widths)
    if (( _has_footer )); then
        local _footer_row=$(( _top + _height - 1 ))
        local _gray="${SHELLFRAME_GRAY:-}"
        local _reset="${SHELLFRAME_RESET:-}"
        local _rev="${SHELLFRAME_REVERSE:-}"
        local _fbuf="" _ftmp=""

        # Get full-width pane bounds (not the content-height-reduced ones)
        local _flt _fll _flw _flh _frt _frl _frw _frh
        shellframe_split_bounds "dv_split" 0 "$_top" "$_left" "$_width" "$_height" \
            _flt _fll _flw _flh
        shellframe_split_bounds "dv_split" 1 "$_top" "$_left" "$_width" "$_height" \
            _frt _frl _frw _frh

        local _white="${SHELLFRAME_WHITE:-}"

        # Left footer
        local _lf="${SHELLFRAME_DIFF_VIEW_LEFT_FOOTER:-}"
        local _ld="${SHELLFRAME_DIFF_VIEW_LEFT_DATE:-}"
        local _lf_clip="${_lf:0:$(( _flw - ${#_ld} - 3 ))}"
        printf -v _ftmp '\033[%d;%dH%s%s %s' \
            "$_footer_row" "$_fll" "$_rev" "$_white" "$_lf_clip"
        _fbuf+="$_ftmp"
        local _lmid=$(( _flw - ${#_lf_clip} - ${#_ld} - 2 ))
        (( _lmid < 0 )) && _lmid=0
        printf -v _ftmp '%*s%s %s' "$_lmid" "" "$_ld" "$_reset"
        _fbuf+="$_ftmp"

        # Right footer
        local _rf="${SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER:-}"
        local _rd="${SHELLFRAME_DIFF_VIEW_RIGHT_DATE:-}"
        local _rf_clip="${_rf:0:$(( _frw - ${#_rd} - 3 ))}"
        printf -v _ftmp '\033[%d;%dH%s%s %s' \
            "$_footer_row" "$_frl" "$_rev" "$_white" "$_rf_clip"
        _fbuf+="$_ftmp"
        local _rmid=$(( _frw - ${#_rf_clip} - ${#_rd} - 2 ))
        (( _rmid < 0 )) && _rmid=0
        printf -v _ftmp '%*s%s %s' "$_rmid" "" "$_rd" "$_reset"
        _fbuf+="$_ftmp"

        printf '%s' "$_fbuf" >&3
    fi
}

# ── shellframe_diff_view_render_side ─────────────────────────────────────────
#
# Render a single side of the diff (for split-region mode where each pane
# is a separate shell.sh region).
#   shellframe_diff_view_render_side top left width height side
#   side: "left" | "right"

shellframe_diff_view_render_side() {
    local _top="$1" _left="$2" _width="$3" _height="$4" _side="$5"

    local _reset="${SHELLFRAME_RESET:-}"
    local _content_top="$_top"
    local _content_h="$_height"

    # Reserve bottom row for footer if set
    local _footer_key _date_key
    if [[ "$_side" == "left" ]]; then
        _footer_key="$SHELLFRAME_DIFF_VIEW_LEFT_FOOTER"
        _date_key="$SHELLFRAME_DIFF_VIEW_LEFT_DATE"
    else
        _footer_key="$SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER"
        _date_key="$SHELLFRAME_DIFF_VIEW_RIGHT_DATE"
    fi

    local _has_footer=0
    if [[ -n "$_footer_key" ]]; then
        _has_footer=1
        _content_h=$(( _content_h - 1 ))
        (( _content_h < 1 )) && _content_h=1
    fi

    _shellframe_dv_render_pane "$_content_top" "$_left" "$_width" "$_content_h" "$_side"

    # Render footer
    if (( _has_footer )); then
        local _footer_row=$(( _top + _height - 1 ))
        local _reset="${SHELLFRAME_RESET:-}"
        local _white="${SHELLFRAME_WHITE:-}"
        local _rev="${SHELLFRAME_REVERSE:-}"
        local _fbuf="" _ftmp=""

        local _ftext="${_footer_key:0:$(( _width - ${#_date_key} - 3 ))}"
        printf -v _ftmp '\033[%d;%dH%s%s %s' \
            "$_footer_row" "$_left" "$_rev" "$_white" "$_ftext"
        _fbuf+="$_ftmp"
        local _mid=$(( _width - ${#_ftext} - ${#_date_key} - 2 ))
        (( _mid < 0 )) && _mid=0
        printf -v _ftmp '%*s%s %s' "$_mid" "" "$_date_key" "$_reset"
        _fbuf+="$_ftmp"

        printf '%s' "$_fbuf" >&3
    fi
}

# ── shellframe_diff_view_on_key ─────────────────────────────────────────────

shellframe_diff_view_on_key() {
    local _key="$1"

    case "$_key" in
        "$SHELLFRAME_KEY_UP")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "up" 3
            return 0
            ;;
        "$SHELLFRAME_KEY_DOWN")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "down" 3
            return 0
            ;;
        "$SHELLFRAME_KEY_PAGE_UP")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "page_up"
            return 0
            ;;
        "$SHELLFRAME_KEY_PAGE_DOWN")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "page_down"
            return 0
            ;;
        "$SHELLFRAME_KEY_HOME")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "home"
            return 0
            ;;
        "$SHELLFRAME_KEY_END")
            shellframe_sync_scroll_move "dv_sync" "dv_left" "end"
            return 0
            ;;
    esac

    return 1
}

# ── shellframe_diff_view_on_focus ───────────────────────────────────────────

shellframe_diff_view_on_focus() {
    SHELLFRAME_DIFF_VIEW_FOCUSED="${1:-0}"
}
