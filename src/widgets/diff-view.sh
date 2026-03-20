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

# Pane footer labels — set by the caller before render
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER=""     # left side: ref + tag + sha + subject
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER=""    # right side: ref + tag + sha + subject
SHELLFRAME_DIFF_VIEW_LEFT_DATE=""       # right-aligned date for left pane
SHELLFRAME_DIFF_VIEW_RIGHT_DATE=""      # right-aligned date for right pane

# File header styling — set by the caller for a custom look, or leave empty for default
SHELLFRAME_DIFF_VIEW_FILE_HDR_ON=""     # ANSI sequence to start file header
SHELLFRAME_DIFF_VIEW_FILE_HDR_OFF=""    # ANSI sequence to end file header

# Gutter width: line number (4) + indicator (1) + space (1)
_SHELLFRAME_DV_GUTTER=6

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

    # Update scroll viewport
    shellframe_scroll_resize "$_scroll_ctx" "$_height" "$_content_w"

    local _scroll_top
    shellframe_scroll_top "$_scroll_ctx" _scroll_top

    local _reset="${SHELLFRAME_RESET:-}"
    local _gray="${SHELLFRAME_GRAY:-}"
    local _bold="${SHELLFRAME_BOLD:-}"
    local _reverse="${SHELLFRAME_REVERSE:-}"

    # Unified muted colors for all change types (add, del, chg)
    # Very dark backgrounds with dim text — looks like a subtle tint
    local _add_on=$'\033[48;5;235m\033[38;5;108m'     # dim green text, near-black bg
    local _del_on=$'\033[48;5;235m\033[38;5;131m'     # dim red text, near-black bg
    local _add_ind=$'\033[38;5;108m'                   # indicator color (no bg)
    local _del_ind=$'\033[38;5;131m'                   # indicator color (no bg)

    # When unfocused, dim all content so the focused widget stands out
    local _dim="" _undim=""
    if (( ! SHELLFRAME_DIFF_VIEW_FOCUSED )); then
        _dim=$'\033[2m'      # ANSI dim/faint attribute
        _undim="${_reset}"
    fi

    # Build all output into a buffer (no subshells), then write once
    local _buf="" _tmp=""

    local _fh_on="${SHELLFRAME_DIFF_VIEW_FILE_HDR_ON:-${_bold}${_reverse}}"
    local _fh_off="${SHELLFRAME_DIFF_VIEW_FILE_HDR_OFF:-${_reset}}"

    local _r
    for (( _r=0; _r < _height; _r++ )); do
        local _row_idx=$(( _scroll_top + _r ))
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
                # Look up file status for this header row
                local _fstatus="modified" _fi
                for (( _fi=0; _fi < ${#SHELLFRAME_DIFF_FILE_ROWS[@]}; _fi++ )); do
                    if (( SHELLFRAME_DIFF_FILE_ROWS[_fi] == _row_idx )); then
                        _fstatus="${SHELLFRAME_DIFF_FILE_STATUS[$_fi]:-modified}"
                        break
                    fi
                done

                local _status_label=""
                if [[ "$_side" == "left" ]]; then
                    case "$_fstatus" in
                        deleted) _status_label=" [deleted]" ;;
                        added)   _status_label="" ;;
                        *)       _status_label="" ;;
                    esac
                else
                    case "$_fstatus" in
                        added)   _status_label=" [added]" ;;
                        deleted) _status_label="" ;;
                        *)       _status_label="" ;;
                    esac
                fi

                local _hdr_text="${_text}${_status_label}"
                printf -v _tmp '%s %-*.*s%s' "$_fh_on" \
                    "$(( _width - 1 ))" "$(( _width - 1 ))" "$_hdr_text" "$_fh_off"
                _buf+="${_tmp}${_undim}"
                continue
                ;;
            file_sep)
                # Full-width horizontal rule between files
                local _rule="" _rc
                for (( _rc=0; _rc < _width; _rc++ )); do _rule+="─"; done
                _buf+="${_gray}${_rule}${_reset}${_undim}"
                continue
                ;;
            sep)
                local _pad=$(( (_width - 5) / 2 ))
                (( _pad < 0 )) && _pad=0
                printf -v _tmp '%s%*s·····%s' "$_gray" "$_pad" "" "$_reset"
                _buf+="${_tmp}${_undim}"
                continue
                ;;
        esac

        # Gutter: line number + indicator column (+/-/space)
        local _indicator=" "
        case "$_type" in
            add) [[ "$_side" == "right" ]] && _indicator="+" ;;
            del) [[ "$_side" == "left" ]]  && _indicator="-" ;;
            chg) if [[ "$_side" == "left" ]]; then _indicator="-"; else _indicator="+"; fi ;;
        esac

        local _ind_color=""
        case "$_indicator" in
            "+") _ind_color="$_add_ind" ;;
            "-") _ind_color="$_del_ind" ;;
        esac

        if [[ -n "$_lnum" ]]; then
            _buf+="${_gray}$(printf '%4s' "$_lnum")${_reset}${_ind_color}${_indicator}${_reset} "
        else
            _buf+="    ${_ind_color}${_indicator}${_reset} "
        fi

        # Content
        local _display="${_text:0:$_content_w}"
        local _fill_n=$(( _content_w - ${#_display} ))
        (( _fill_n < 0 )) && _fill_n=0

        case "$_type" in
            ctx)
                _buf+="$_display"
                ;;
            add)
                if [[ "$_side" == "right" ]]; then
                    printf -v _tmp '%s%s%*s%s' "$_add_on" "$_display" "$_fill_n" "" "$_reset"
                    _buf+="$_tmp"
                fi
                ;;
            del)
                if [[ "$_side" == "left" ]]; then
                    printf -v _tmp '%s%s%*s%s' "$_del_on" "$_display" "$_fill_n" "" "$_reset"
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
