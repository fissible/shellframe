#!/usr/bin/env bash
# shellframe/src/scroll.sh — Scroll container state model
#
# COMPATIBILITY: bash 3.2+ (macOS default).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Manages scroll offset and viewport state for any list-like or grid-like
# content.  Scrolling logic must NOT be baked into individual widgets —
# they use this module instead.
#
# State is keyed by a context name ($ctx) so multiple independent scroll
# viewports can coexist on screen (e.g. sidebar + main pane).
# Context names must match [a-zA-Z0-9_]+.
#
# Coordinates are 0-based row/col indices into content space.  The viewport
# is a window of (VROWS × VCOLS) starting at (TOP, LEFT).
#
# ── Dynamic globals (internal; do not access directly) ────────────────────────
#
#   _SHELLFRAME_SCROLL_${ctx}_TOP    — first visible content row (0-based)
#   _SHELLFRAME_SCROLL_${ctx}_LEFT   — first visible content col (0-based)
#   _SHELLFRAME_SCROLL_${ctx}_ROWS   — total content rows
#   _SHELLFRAME_SCROLL_${ctx}_COLS   — total content cols
#   _SHELLFRAME_SCROLL_${ctx}_VROWS  — viewport height (visible rows)
#   _SHELLFRAME_SCROLL_${ctx}_VCOLS  — viewport width (visible cols)
#
# ── Public API ─────────────────────────────────────────────────────────────────
#
#   shellframe_scroll_init ctx total_rows total_cols viewport_rows viewport_cols
#     Initialise (or reset) a scroll context.  Offset starts at (0, 0).
#
#   shellframe_scroll_top ctx [out_var]
#     Get current vertical scroll offset.
#
#   shellframe_scroll_left ctx [out_var]
#     Get current horizontal scroll offset.
#
#   shellframe_scroll_resize ctx viewport_rows viewport_cols
#     Update viewport dimensions (e.g. on terminal resize).  Re-clamps offset.
#
#   shellframe_scroll_move ctx direction [amount]
#     Move scroll offset.  direction:
#       up | down | page_up | page_down | home | end  (vertical)
#       left | right | h_home | h_end                 (horizontal)
#     amount defaults to 1 (page_up/page_down default to viewport height).
#     Offset is clamped; boundary no-ops are not errors.
#
#   shellframe_scroll_ensure_row ctx row
#     If $row is outside the vertical viewport, scroll the minimum amount to
#     bring it into view.  Used to keep the selected item visible.
#
#   shellframe_scroll_ensure_col ctx col
#     Same as ensure_row but for horizontal scroll.
#
#   shellframe_scroll_row_visible ctx row
#     Return 0 (true) if $row is within the current vertical viewport.
#
#   shellframe_scroll_col_visible ctx col
#     Return 0 (true) if $col is within the current horizontal viewport.

# ── Internal helper ───────────────────────────────────────────────────────────

_shellframe_scroll_validate_ctx() {
    local _ctx="$1"
    if [[ -z "$_ctx" || ! "$_ctx" =~ ^[a-zA-Z0-9_]+$ ]]; then
        printf 'shellframe_scroll: invalid context name: %q\n' "$_ctx" >&2
        return 1
    fi
}

# ── shellframe_scroll_init ────────────────────────────────────────────────────

shellframe_scroll_init() {
    local _ctx="$1" _rows="$2" _cols="$3" _vrows="$4" _vcols="$5"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_TOP"   '%d' 0
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_LEFT"  '%d' 0
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_ROWS"  '%d' "$_rows"
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_COLS"  '%d' "$_cols"
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_VROWS" '%d' "$_vrows"
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_VCOLS" '%d' "$_vcols"
}

# ── shellframe_scroll_top / shellframe_scroll_left ────────────────────────────

shellframe_scroll_top() {
    local _ctx="$1" _out="${2:-}"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1
    local _var="_SHELLFRAME_SCROLL_${_ctx}_TOP"
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%d' "${!_var:-0}"
    else
        printf '%d\n' "${!_var:-0}"
    fi
}

shellframe_scroll_left() {
    local _ctx="$1" _out="${2:-}"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1
    local _var="_SHELLFRAME_SCROLL_${_ctx}_LEFT"
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%d' "${!_var:-0}"
    else
        printf '%d\n' "${!_var:-0}"
    fi
}

# ── shellframe_scroll_resize ───────────────────────────────────────────────────

# Update viewport dimensions and re-clamp the current offset.
shellframe_scroll_resize() {
    local _ctx="$1" _vrows="$2" _vcols="$3"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_VROWS" '%d' "$_vrows"
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_VCOLS" '%d' "$_vcols"
    # Re-clamp by moving 0 in the current directions
    shellframe_scroll_move "$_ctx" down 0
    shellframe_scroll_move "$_ctx" right 0
}

# ── shellframe_scroll_move ────────────────────────────────────────────────────

# Move scroll offset in $direction by $amount (default 1).
# page_up / page_down default to the viewport height.
# Offset is clamped to valid range; no-ops at boundaries are not errors.
shellframe_scroll_move() {
    local _ctx="$1" _dir="$2" _amt="${3:-1}"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1

    local _top_var="_SHELLFRAME_SCROLL_${_ctx}_TOP"
    local _left_var="_SHELLFRAME_SCROLL_${_ctx}_LEFT"
    local _rows_var="_SHELLFRAME_SCROLL_${_ctx}_ROWS"
    local _cols_var="_SHELLFRAME_SCROLL_${_ctx}_COLS"
    local _vrows_var="_SHELLFRAME_SCROLL_${_ctx}_VROWS"
    local _vcols_var="_SHELLFRAME_SCROLL_${_ctx}_VCOLS"

    local _top="${!_top_var:-0}"
    local _left="${!_left_var:-0}"
    local _rows="${!_rows_var:-0}"
    local _cols="${!_cols_var:-0}"
    local _vrows="${!_vrows_var:-0}"
    local _vcols="${!_vcols_var:-0}"

    # Maximum valid offsets (can be 0 when content fits in viewport)
    local _max_top=$(( _rows - _vrows ))
    local _max_left=$(( _cols - _vcols ))
    (( _max_top < 0 ))  && _max_top=0
    (( _max_left < 0 )) && _max_left=0

    case "$_dir" in
        up)
            _top=$(( _top - _amt ))
            ;;
        down)
            _top=$(( _top + _amt ))
            ;;
        page_up)
            local _page=$(( _vrows > 0 ? _vrows : 1 ))
            _top=$(( _top - _page ))
            ;;
        page_down)
            local _page=$(( _vrows > 0 ? _vrows : 1 ))
            _top=$(( _top + _page ))
            ;;
        home)
            _top=0
            ;;
        end)
            _top="$_max_top"
            ;;
        left)
            _left=$(( _left - _amt ))
            ;;
        right)
            _left=$(( _left + _amt ))
            ;;
        h_home)
            _left=0
            ;;
        h_end)
            _left="$_max_left"
            ;;
        *)
            printf 'shellframe_scroll_move: unknown direction: %s\n' "$_dir" >&2
            return 1
            ;;
    esac

    # Clamp
    (( _top  < 0 ))        && _top=0
    (( _top  > _max_top )) && _top="$_max_top"
    (( _left < 0 ))        && _left=0
    (( _left > _max_left )) && _left="$_max_left"

    printf -v "$_top_var"  '%d' "$_top"
    printf -v "$_left_var" '%d' "$_left"
}

# ── shellframe_scroll_ensure_row ──────────────────────────────────────────────

# Scroll the minimum amount to bring $row into the vertical viewport.
# If already visible, no-op.  Used for keep-selected-item-visible behavior.
shellframe_scroll_ensure_row() {
    local _ctx="$1" _row="$2"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1

    local _top_var="_SHELLFRAME_SCROLL_${_ctx}_TOP"
    local _vrows_var="_SHELLFRAME_SCROLL_${_ctx}_VROWS"
    local _rows_var="_SHELLFRAME_SCROLL_${_ctx}_ROWS"

    local _top="${!_top_var:-0}"
    local _vrows="${!_vrows_var:-0}"
    local _rows="${!_rows_var:-0}"
    local _max_top=$(( _rows - _vrows ))
    (( _max_top < 0 )) && _max_top=0

    if (( _row < _top )); then
        _top="$_row"
    elif (( _vrows > 0 && _row >= _top + _vrows )); then
        _top=$(( _row - _vrows + 1 ))
    fi

    (( _top < 0 ))        && _top=0
    (( _top > _max_top )) && _top="$_max_top"
    printf -v "$_top_var" '%d' "$_top"
}

# ── shellframe_scroll_ensure_col ──────────────────────────────────────────────

# Scroll the minimum amount to bring $col into the horizontal viewport.
shellframe_scroll_ensure_col() {
    local _ctx="$1" _col="$2"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1

    local _left_var="_SHELLFRAME_SCROLL_${_ctx}_LEFT"
    local _vcols_var="_SHELLFRAME_SCROLL_${_ctx}_VCOLS"
    local _cols_var="_SHELLFRAME_SCROLL_${_ctx}_COLS"

    local _left="${!_left_var:-0}"
    local _vcols="${!_vcols_var:-0}"
    local _cols="${!_cols_var:-0}"
    local _max_left=$(( _cols - _vcols ))
    (( _max_left < 0 )) && _max_left=0

    if (( _col < _left )); then
        _left="$_col"
    elif (( _vcols > 0 && _col >= _left + _vcols )); then
        _left=$(( _col - _vcols + 1 ))
    fi

    (( _left < 0 ))         && _left=0
    (( _left > _max_left )) && _left="$_max_left"
    printf -v "$_left_var" '%d' "$_left"
}

# ── shellframe_scroll_row_visible ─────────────────────────────────────────────

# Return 0 (true) if $row is within the current vertical viewport.
shellframe_scroll_row_visible() {
    local _ctx="$1" _row="$2"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1
    local _top_var="_SHELLFRAME_SCROLL_${_ctx}_TOP"
    local _vrows_var="_SHELLFRAME_SCROLL_${_ctx}_VROWS"
    local _top="${!_top_var:-0}"
    local _vrows="${!_vrows_var:-0}"
    (( _row >= _top && _row < _top + _vrows ))
}

# ── shellframe_scroll_col_visible ─────────────────────────────────────────────

# Return 0 (true) if $col is within the current horizontal viewport.
shellframe_scroll_col_visible() {
    local _ctx="$1" _col="$2"
    _shellframe_scroll_validate_ctx "$_ctx" || return 1
    local _left_var="_SHELLFRAME_SCROLL_${_ctx}_LEFT"
    local _vcols_var="_SHELLFRAME_SCROLL_${_ctx}_VCOLS"
    local _left="${!_left_var:-0}"
    local _vcols="${!_vcols_var:-0}"
    (( _col >= _left && _col < _left + _vcols ))
}

# ── Mouse scroll step ─────────────────────────────────────────────────────────

# Number of rows to scroll per mouse wheel tick.  Default 3.
# Override in your app to tune scroll speed.
SHELLFRAME_SCROLL_MOUSE_STEP=3

# ── shellframe_scroll_on_mouse ─────────────────────────────────────────────────

# Generic scroll-wheel handler for widgets that use scroll.sh (editor, grid).
# Caller passes the context name as the first argument, followed by the standard
# on_mouse arguments from shellframe_shell dispatch.
#
#   shellframe_scroll_on_mouse ctx button action [remaining args ignored]
#
# Only handles scroll-wheel presses (buttons 64/65).  Returns 0 if handled,
# 1 otherwise.
shellframe_scroll_on_mouse() {
    local _ctx="$1" _button="$2" _action="$3"
    local _step="${SHELLFRAME_SCROLL_MOUSE_STEP:-3}"
    [[ "$_action" != "press" ]] && return 1
    if (( _button == 64 )); then
        shellframe_scroll_move "$_ctx" up "$_step"
        shellframe_shell_mark_dirty
        return 0
    elif (( _button == 65 )); then
        shellframe_scroll_move "$_ctx" down "$_step"
        shellframe_shell_mark_dirty
        return 0
    fi
    return 1
}
