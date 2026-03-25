#!/usr/bin/env bash
# shellframe/src/widgets/list.sh — Selectable list widget (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/selection.sh, src/scroll.sh, src/draw.sh.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a scrollable list of items with a highlighted cursor row.  Supports
# single-select (cursor only) and multi-select (Space to toggle items).
#
# Call shellframe_list_init before first use or after changing SHELLFRAME_LIST_ITEMS.
# Multiple list instances can coexist with different SHELLFRAME_LIST_CTX values.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_LIST_ITEMS[@]   — display label per row
#   SHELLFRAME_LIST_CTX        — selection/scroll context name (default: "list")
#   SHELLFRAME_LIST_MULTISELECT — 0 (default) | 1 (Space toggles selection)
#   SHELLFRAME_LIST_FOCUSED    — 0 (default) | 1
#   SHELLFRAME_LIST_FOCUSABLE  — 1 (default) | 0
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_list_init [ctx] [viewport_rows]
#     Initialise selection and scroll state for the current SHELLFRAME_LIST_ITEMS.
#     Must be called after any change to SHELLFRAME_LIST_ITEMS.
#     viewport_rows defaults to 10; render updates it automatically via resize.
#
#   shellframe_list_render top left width height
#     Draw visible items within the given region.  Output to /dev/tty.
#
#   shellframe_list_on_key key
#     Returns:
#       0  — key handled (app shell should redraw)
#       1  — key not handled (pass to next handler)
#       2  — Enter pressed (item confirmed; read cursor via shellframe_sel_cursor)
#
#   shellframe_list_on_focus focused  — set SHELLFRAME_LIST_FOCUSED
#
#   shellframe_list_size              — print "1 1 0 0"

SHELLFRAME_LIST_CTX="list"
SHELLFRAME_LIST_MULTISELECT=0
SHELLFRAME_LIST_FOCUSED=0
SHELLFRAME_LIST_FOCUSABLE=1
SHELLFRAME_LIST_CURSOR_STYLE=""
SHELLFRAME_LIST_BG=""
SHELLFRAME_LIST_ITEMS=()

# ── shellframe_list_init ─────────────────────────────────────────────────────

shellframe_list_init() {
    local _ctx="${1:-${SHELLFRAME_LIST_CTX:-list}}"
    local _vrows="${2:-10}"
    local _n=${#SHELLFRAME_LIST_ITEMS[@]}
    shellframe_sel_init  "$_ctx" "$_n"
    shellframe_scroll_init "$_ctx" "$_n" 1 "$_vrows" 1
}

# ── shellframe_list_render ────────────────────────────────────────────────────

shellframe_list_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _ctx="${SHELLFRAME_LIST_CTX:-list}"
    local _focused="${SHELLFRAME_LIST_FOCUSED:-0}"
    local _multi="${SHELLFRAME_LIST_MULTISELECT:-0}"
    local _n=${#SHELLFRAME_LIST_ITEMS[@]}

    # Keep scroll viewport in sync with current render height
    shellframe_scroll_resize "$_ctx" "$_height" 1

    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"
    local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"

    local _scroll_top
    shellframe_scroll_top "$_ctx" _scroll_top

    local _cursor
    shellframe_sel_cursor "$_ctx" _cursor 2>/dev/null || _cursor=$(shellframe_sel_cursor "$_ctx")

    local _r
    for (( _r=0; _r<_height; _r++ )); do
        local _row=$(( _top + _r ))
        local _item_idx=$(( _scroll_top + _r ))

        # Clear this row (only within the list's own column range)
        local _lbg="${SHELLFRAME_LIST_BG:-}"
        printf '\033[%d;%dH%s%*s' "$_row" "$_left" "$_lbg" "$_width" '' >&3

        [[ $_item_idx -ge $_n ]] && continue

        local _label="${SHELLFRAME_LIST_ITEMS[$_item_idx]}"

        # Checkbox prefix for multiselect
        local _prefix=""
        if (( _multi )); then
            if shellframe_sel_is_selected "$_ctx" "$_item_idx"; then
                _prefix="[x] "
            else
                _prefix="[ ] "
            fi
        fi

        local _text="${_prefix}${_label}"
        local _clipped
        _clipped=$(shellframe_str_clip_ellipsis "$_text" "$_text" "$_width")

        printf '\033[%d;%dH' "$_row" "$_left" >&3

        if (( _item_idx == _cursor )); then
            # Highlight cursor row: custom style, reverse, or dim bg
            local _hl
            if [[ -n "${SHELLFRAME_LIST_CURSOR_STYLE:-}" ]] && (( _focused )); then
                _hl="$SHELLFRAME_LIST_CURSOR_STYLE"
            elif (( _focused )); then
                _hl="$_rev"
            else
                # Dark gray background (236) with normal text — subtle indicator
                _hl=$'\033[48;5;236m'
            fi
            printf '%s' "$_hl" >&3
            printf '%s' "$_clipped" >&3
            # Pad to full width under highlight
            local _clen=${#_clipped}
            local _k=0
            while (( _k < _width - _clen )); do
                printf ' ' >&3
                (( _k++ ))
            done
            printf '%s' "$_rst" >&3
        else
            printf '%s' "$_clipped" >&3
        fi
    done

    # Leave cursor at last row, col left (component contract)
    printf '\033[%d;%dH' "$(( _top + _height - 1 ))" "$_left" >&3
}

# ── shellframe_list_on_key ────────────────────────────────────────────────────

shellframe_list_on_key() {
    local _key="$1"
    local _ctx="${SHELLFRAME_LIST_CTX:-list}"

    # Read viewport rows from scroll state (set by init/resize)
    local _vr_var="_SHELLFRAME_SCROLL_${_ctx}_VROWS"
    local _vrows="${!_vr_var:-10}"

    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"

    if [[ "$_key" == $'\r' ]] || [[ "$_key" == $'\n' ]]; then
        shellframe_shell_mark_dirty
        return 2    # Enter: item confirmed
    elif [[ "$_key" == "$_k_down" ]]; then
        shellframe_sel_move "$_ctx" down
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_up" ]]; then
        shellframe_sel_move "$_ctx" up
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_pgdn" ]]; then
        shellframe_sel_move "$_ctx" page_down "$_vrows"
        shellframe_scroll_move "$_ctx" page_down
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_pgup" ]]; then
        shellframe_sel_move "$_ctx" page_up "$_vrows"
        shellframe_scroll_move "$_ctx" page_up
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_home" ]]; then
        shellframe_sel_move "$_ctx" home
        shellframe_scroll_move "$_ctx" home
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == "$_k_end" ]]; then
        shellframe_sel_move "$_ctx" end
        shellframe_scroll_move "$_ctx" end
        shellframe_shell_mark_dirty
        return 0
    elif [[ "$_key" == " " ]] && (( ${SHELLFRAME_LIST_MULTISELECT:-0} )); then
        shellframe_sel_toggle "$_ctx"
        shellframe_shell_mark_dirty
        return 0
    fi

    return 1
}

# ── shellframe_list_on_mouse ──────────────────────────────────────────────────
#
# Mouse handler for the list widget.  Called by shellframe_shell when an SGR
# mouse event lands inside the list's registered region.
#
#   shellframe_list_on_mouse button action mrow mcol rtop rleft rwidth rheight
#
#   button  — 0=left, 1=middle, 2=right, 64=scroll-up, 65=scroll-down
#   action  — "press" or "release"
#   mrow    — 1-based terminal row of the event
#   mcol    — 1-based terminal column
#   rtop    — top terminal row of the list region (1-based)
#   rleft   — left terminal col of the list region
#   rwidth  — region width
#   rheight — region height
#
# Returns: 0 if handled, 1 otherwise.

shellframe_list_on_mouse() {
    local _button="$1" _action="$2" _mrow="$3" _mcol="$4"
    local _rtop="$5"
    local _ctx="${SHELLFRAME_LIST_CTX:-list}"

    # Only act on press events
    [[ "$_action" != "press" ]] && return 1

    # Scroll wheel: move viewport without moving cursor
    if (( _button == 64 )); then
        shellframe_scroll_move "$_ctx" up
        shellframe_shell_mark_dirty
        return 0
    elif (( _button == 65 )); then
        shellframe_scroll_move "$_ctx" down
        shellframe_shell_mark_dirty
        return 0
    fi

    # Left/middle/right click: move cursor to clicked item
    if (( _button <= 2 )); then
        local _scroll_top
        shellframe_scroll_top "$_ctx" _scroll_top
        local _item_idx=$(( _scroll_top + _mrow - _rtop ))
        local _n=${#SHELLFRAME_LIST_ITEMS[@]}
        if (( _item_idx >= 0 && _item_idx < _n )); then
            shellframe_sel_set "$_ctx" "$_item_idx"
            shellframe_scroll_ensure_row "$_ctx" "$_item_idx"
            shellframe_shell_mark_dirty
            return 0
        fi
    fi

    return 1
}

# ── shellframe_list_on_focus ──────────────────────────────────────────────────

shellframe_list_on_focus() {
    SHELLFRAME_LIST_FOCUSED="${1:-0}"
}

# ── shellframe_list_size ──────────────────────────────────────────────────────

# min: 1×1; preferred: fill all available space (0×0)
shellframe_list_size() {
    printf '%d %d %d %d' 1 1 0 0
}
