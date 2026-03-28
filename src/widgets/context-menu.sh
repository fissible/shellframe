#!/usr/bin/env bash
# shellframe/src/widgets/context-menu.sh — Pop-over context menu (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/selection.sh, src/scroll.sh, src/panel.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# A floating menu anchored at a screen coordinate.  Renders a bordered list of
# actions and returns the selected index on Enter (rc=2) or dismisses on Esc
# (rc=2 with RESULT=-1).  Supports keyboard navigation and scroll wheel.
#
# The menu auto-positions itself to stay within the terminal.  If it would
# overflow the right or bottom edge, it shifts left or upward.
#
# ── Typical usage ────────────────────────────────────────────────────────────
#
#   1. Set SHELLFRAME_CMENU_ITEMS and SHELLFRAME_CMENU_ANCHOR_ROW/COL.
#   2. Call shellframe_cmenu_init to initialise selection state.
#   3. Register as a focusable region via shellframe_shell_region.
#   4. Read SHELLFRAME_CMENU_RESULT after on_key returns 2.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_CMENU_ITEMS[@]      — menu item labels
#   SHELLFRAME_CMENU_CTX           — selection/scroll context (default: "cmenu")
#   SHELLFRAME_CMENU_ANCHOR_ROW    — screen row of the anchor point (click pos)
#   SHELLFRAME_CMENU_ANCHOR_COL    — screen col of the anchor point
#   SHELLFRAME_CMENU_FOCUSED       — 0 (default) | 1
#   SHELLFRAME_CMENU_FOCUSABLE     — 1 (default) | 0
#   SHELLFRAME_CMENU_STYLE         — border style: single (default) | rounded
#   SHELLFRAME_CMENU_MAX_HEIGHT    — max visible items before scrolling (default: 10)
#   SHELLFRAME_CMENU_BG            — background ANSI prefix (default: "")
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_CMENU_RESULT        — set when on_key returns 2:
#                                    selected item index (0-based) on Enter,
#                                    -1 on Escape dismiss.
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_cmenu_init [ctx]
#     Initialise selection and scroll state for the current items array.
#
#   shellframe_cmenu_render top left width height
#     Render the menu anchored near ANCHOR_ROW/COL within the bounding region.
#     The bounding region (top/left/width/height) is the full-screen area used
#     for clipping — the menu positions itself within this space.
#
#   shellframe_cmenu_on_key key
#     Returns: 0 (handled), 1 (unhandled), 2 (Enter/Esc: read RESULT)
#
#   shellframe_cmenu_on_mouse button action mrow mcol rtop rleft rwidth rheight
#     Returns: 0 (handled click/scroll), 1 (click outside menu → dismiss)
#
#   shellframe_cmenu_on_focus focused
#
#   shellframe_cmenu_size
#     Print "min_w min_h pref_w pref_h" for current items.

SHELLFRAME_CMENU_ITEMS=()
SHELLFRAME_CMENU_CTX="cmenu"
SHELLFRAME_CMENU_ANCHOR_ROW=1
SHELLFRAME_CMENU_ANCHOR_COL=1
SHELLFRAME_CMENU_FOCUSED=0
SHELLFRAME_CMENU_FOCUSABLE=1
SHELLFRAME_CMENU_STYLE="single"
SHELLFRAME_CMENU_MAX_HEIGHT=10
SHELLFRAME_CMENU_BG=""
SHELLFRAME_CMENU_RESULT=-1

# ── shellframe_cmenu_init ────────────────────────────────────────────────────

shellframe_cmenu_init() {
    local _ctx="${1:-${SHELLFRAME_CMENU_CTX:-cmenu}}"
    local _n=${#SHELLFRAME_CMENU_ITEMS[@]}
    local _max="${SHELLFRAME_CMENU_MAX_HEIGHT:-10}"
    local _vrows="$_max"
    (( _n < _vrows )) && _vrows="$_n"
    (( _vrows < 1 )) && _vrows=1
    shellframe_sel_init  "$_ctx" "$_n"
    shellframe_scroll_init "$_ctx" "$_n" 1 "$_vrows" 1
}

# ── _shellframe_cmenu_dims ───────────────────────────────────────────────────
# Compute menu dimensions and final position.  Sets caller locals via out_vars.

_shellframe_cmenu_dims() {
    local _bound_top="$1" _bound_left="$2" _bound_w="$3" _bound_h="$4"
    local _out_mtop="$5" _out_mleft="$6" _out_mw="$7" _out_mh="$8"

    local _n=${#SHELLFRAME_CMENU_ITEMS[@]}
    local _max="${SHELLFRAME_CMENU_MAX_HEIGHT:-10}"
    local _vis_items="$_n"
    (( _vis_items > _max )) && _vis_items="$_max"
    (( _vis_items < 1 )) && _vis_items=1

    # Menu width = longest item + 2 (left/right border) + 2 (1-char padding each side)
    local _max_label=0 _i
    for (( _i=0; _i<_n; _i++ )); do
        local _len=${#SHELLFRAME_CMENU_ITEMS[$_i]}
        (( _len > _max_label )) && _max_label="$_len"
    done
    local _menu_w=$(( _max_label + 4 ))
    (( _menu_w < 8 )) && _menu_w=8

    # Menu height = visible items + 2 (top/bottom border)
    local _menu_h=$(( _vis_items + 2 ))

    # Position: try below-right of anchor
    local _arow="${SHELLFRAME_CMENU_ANCHOR_ROW:-1}"
    local _acol="${SHELLFRAME_CMENU_ANCHOR_COL:-1}"
    local _pos_top="$_arow"
    local _pos_left="$_acol"

    # Shift up if overflows bottom
    local _bottom=$(( _pos_top + _menu_h ))
    local _bound_bottom=$(( _bound_top + _bound_h ))
    if (( _bottom > _bound_bottom )); then
        _pos_top=$(( _bound_bottom - _menu_h ))
        (( _pos_top < _bound_top )) && _pos_top="$_bound_top"
    fi

    # Shift left if overflows right
    local _right=$(( _pos_left + _menu_w ))
    local _bound_right=$(( _bound_left + _bound_w ))
    if (( _right > _bound_right )); then
        _pos_left=$(( _bound_right - _menu_w ))
        (( _pos_left < _bound_left )) && _pos_left="$_bound_left"
    fi

    printf -v "$_out_mtop"  '%d' "$_pos_top"
    printf -v "$_out_mleft" '%d' "$_pos_left"
    printf -v "$_out_mw"    '%d' "$_menu_w"
    printf -v "$_out_mh"    '%d' "$_menu_h"
}

# ── shellframe_cmenu_render ──────────────────────────────────────────────────

shellframe_cmenu_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _ctx="${SHELLFRAME_CMENU_CTX:-cmenu}"
    local _focused="${SHELLFRAME_CMENU_FOCUSED:-0}"
    local _bg="${SHELLFRAME_CMENU_BG:-}"
    local _n=${#SHELLFRAME_CMENU_ITEMS[@]}

    local _mtop _mleft _mw _mh
    _shellframe_cmenu_dims "$_top" "$_left" "$_width" "$_height" _mtop _mleft _mw _mh

    # Draw border via panel
    SHELLFRAME_PANEL_STYLE="${SHELLFRAME_CMENU_STYLE:-single}"
    SHELLFRAME_PANEL_TITLE=""
    SHELLFRAME_PANEL_FOCUSED="$_focused"
    SHELLFRAME_PANEL_CELL_ATTRS="$_bg"
    shellframe_panel_render "$_mtop" "$_mleft" "$_mw" "$_mh"

    # Inner content area
    local _it _il _iw _ih
    shellframe_panel_inner "$_mtop" "$_mleft" "$_mw" "$_mh" _it _il _iw _ih

    # Update scroll viewport to match actual visible rows
    shellframe_scroll_resize "$_ctx" "$_ih" 1

    local _cursor=0
    shellframe_sel_cursor "$_ctx" _cursor 2>/dev/null || true
    local _scroll_top=0
    shellframe_scroll_top "$_ctx" _scroll_top

    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"
    local _r
    for (( _r=0; _r<_ih; _r++ )); do
        local _row=$(( _it + _r ))
        local _idx=$(( _scroll_top + _r ))

        # Fill row with background
        shellframe_fb_fill "$_row" "$_il" "$_iw" " " "$_bg"

        (( _idx >= _n )) && continue

        local _label=" ${SHELLFRAME_CMENU_ITEMS[$_idx]}"
        local _clipped
        shellframe_str_clip_ellipsis "$_label" "$_label" "$_iw" _clipped

        if (( _idx == _cursor && _focused )); then
            shellframe_fb_print "$_row" "$_il" "$_clipped" "${_bg}${_rev}"
            # Pad remainder of cursor row with reverse
            local _clen=${#_clipped}
            if (( _clen < _iw )); then
                shellframe_fb_fill "$_row" "$(( _il + _clen ))" "$(( _iw - _clen ))" " " "${_bg}${_rev}"
            fi
        else
            shellframe_fb_print "$_row" "$_il" "$_clipped" "$_bg"
        fi
    done
}

# ── shellframe_cmenu_on_key ──────────────────────────────────────────────────

shellframe_cmenu_on_key() {
    local _key="$1"
    local _ctx="${SHELLFRAME_CMENU_CTX:-cmenu}"

    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"

    # Enter → confirm selection
    if [[ "$_key" == $'\r' ]] || [[ "$_key" == $'\n' ]]; then
        shellframe_sel_cursor "$_ctx" SHELLFRAME_CMENU_RESULT 2>/dev/null || SHELLFRAME_CMENU_RESULT=0
        shellframe_shell_mark_dirty
        return 2
    fi

    # Esc → dismiss
    if [[ "$_key" == $'\033' ]]; then
        SHELLFRAME_CMENU_RESULT=-1
        shellframe_shell_mark_dirty
        return 2
    fi

    # Navigation
    if [[ "$_key" == "$_k_up" ]]; then
        shellframe_sel_move "$_ctx" up
        local _cur; shellframe_sel_cursor "$_ctx" _cur 2>/dev/null || _cur=0
        shellframe_scroll_ensure_row "$_ctx" "$_cur"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_down" ]]; then
        shellframe_sel_move "$_ctx" down
        local _cur; shellframe_sel_cursor "$_ctx" _cur 2>/dev/null || _cur=0
        shellframe_scroll_ensure_row "$_ctx" "$_cur"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_home" ]]; then
        shellframe_sel_set "$_ctx" 0
        local _cur; shellframe_sel_cursor "$_ctx" _cur 2>/dev/null || _cur=0
        shellframe_scroll_ensure_row "$_ctx" "$_cur"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_end" ]]; then
        local _n=${#SHELLFRAME_CMENU_ITEMS[@]}
        shellframe_sel_set "$_ctx" "$(( _n - 1 ))"
        local _cur; shellframe_sel_cursor "$_ctx" _cur 2>/dev/null || _cur=0
        shellframe_scroll_ensure_row "$_ctx" "$_cur"
        shellframe_shell_mark_dirty
        return 0
    fi

    return 1
}

# ── shellframe_cmenu_on_mouse ────────────────────────────────────────────────

shellframe_cmenu_on_mouse() {
    local _button="$1" _action="$2" _mrow="$3" _mcol="$4"
    local _rtop="$5" _rleft="$6" _rwidth="$7" _rheight="$8"
    local _ctx="${SHELLFRAME_CMENU_CTX:-cmenu}"

    [[ "$_action" != "press" ]] && return 0

    # Compute actual menu bounds (menu may be smaller than the registered region)
    local _mtop=0 _mleft=0 _mw=0 _mh=0
    _shellframe_cmenu_dims "$_rtop" "$_rleft" "$_rwidth" "$_rheight" _mtop _mleft _mw _mh

    local _it=0 _il=0 _iw=0 _ih=0
    SHELLFRAME_PANEL_STYLE="${SHELLFRAME_CMENU_STYLE:-single}"
    shellframe_panel_inner "$_mtop" "$_mleft" "$_mw" "$_mh" _it _il _iw _ih

    # Scroll wheel within menu bounds
    if (( _mrow >= _mtop && _mrow < _mtop + _mh && _mcol >= _mleft && _mcol < _mleft + _mw )); then
        if (( _button == 64 )); then
            shellframe_scroll_move "$_ctx" up
            shellframe_shell_mark_dirty
            return 0
        elif (( _button == 65 )); then
            shellframe_scroll_move "$_ctx" down
            shellframe_shell_mark_dirty
            return 0
        fi
    fi

    # Click inside item area
    if (( _button <= 2 && _mrow >= _it && _mrow < _it + _ih && _mcol >= _il && _mcol < _il + _iw )); then
        local _scroll_top=0
        shellframe_scroll_top "$_ctx" _scroll_top
        local _item_idx=$(( _scroll_top + _mrow - _it ))
        local _n=${#SHELLFRAME_CMENU_ITEMS[@]}
        if (( _item_idx >= 0 && _item_idx < _n )); then
            shellframe_sel_set "$_ctx" "$_item_idx"
            SHELLFRAME_CMENU_RESULT="$_item_idx"
            shellframe_shell_mark_dirty
            return 2   # Click selects and confirms
        fi
    fi

    # Click outside menu → dismiss
    SHELLFRAME_CMENU_RESULT=-1
    shellframe_shell_mark_dirty
    return 2
}

# ── shellframe_cmenu_on_focus ────────────────────────────────────────────────

shellframe_cmenu_on_focus() {
    SHELLFRAME_CMENU_FOCUSED="${1:-0}"
}

# ── shellframe_cmenu_size ────────────────────────────────────────────────────

shellframe_cmenu_size() {
    local _n=${#SHELLFRAME_CMENU_ITEMS[@]}
    local _max_label=0 _i
    for (( _i=0; _i<_n; _i++ )); do
        local _len=${#SHELLFRAME_CMENU_ITEMS[$_i]}
        (( _len > _max_label )) && _max_label="$_len"
    done
    local _w=$(( _max_label + 4 ))
    local _h=$(( _n + 2 ))
    printf '%d %d %d %d' "$_w" 3 "$_w" "$_h"
}
