#!/usr/bin/env bash
# shellframe/src/selection.sh — Shared cursor + multi-select state model
#
# COMPATIBILITY: bash 3.2+ (macOS default).
#
# ── Overview ───────────────────────────────────────────────────────────────────
#
# Manages two orthogonal selection concepts for list-like components:
#
#   cursor    — the currently highlighted row index (single integer, 0-based).
#               Always valid; clamped to [0, count-1].
#
#   multi-select — a set of row indices the user has explicitly toggled on.
#               Independent of the cursor. Empty by default.
#
# State is stored in dynamically named globals keyed by a context name
# ($ctx). This allows multiple independent selection states to coexist
# on screen (e.g. a sidebar list and a main-panel list running simultaneously).
#
# Context names must match [a-zA-Z0-9_]+ to keep the global names safe for
# eval and indirect reference.
#
# ── Dynamic global names (internal; do not access directly) ───────────────────
#
#   _SHELLFRAME_SEL_${ctx}_CURSOR   — cursor row index (int)
#   _SHELLFRAME_SEL_${ctx}_COUNT    — total row count (int)
#   _SHELLFRAME_SEL_${ctx}_FLAGS    — multi-select bitmap string ("0"/"1" per row)
#
# ── Public API ─────────────────────────────────────────────────────────────────
#
#   shellframe_sel_init ctx count
#     Initialise (or reset) a selection context. Must be called before any
#     other function for a given ctx. Clears multi-select; sets cursor to 0.
#
#   shellframe_sel_move ctx direction [page_size]
#     Move the cursor. direction: up | down | home | end | page_up | page_down
#     page_size defaults to 10.
#
#   shellframe_sel_toggle ctx [index]
#     Toggle the multi-select flag for the given index (default: cursor row).
#
#   shellframe_sel_select_all ctx
#   shellframe_sel_clear_all ctx
#     Set all flags to 1 (or 0).
#
#   shellframe_sel_cursor ctx
#     Print current cursor index to stdout.
#
#   shellframe_sel_count ctx
#     Print total row count to stdout.
#
#   shellframe_sel_selected ctx
#     Print space-separated list of selected (flag=1) indices to stdout.
#     Prints an empty line if nothing is selected.
#
#   shellframe_sel_selected_count ctx
#     Print the count of selected items to stdout.
#
#   shellframe_sel_is_selected ctx index
#     Return 0 if the item at index is selected (flag=1), 1 otherwise.

# ── Internal helpers ───────────────────────────────────────────────────────────

# Validate ctx: must be non-empty and match [a-zA-Z0-9_]+
# Prints an error to stderr and returns 1 on failure.
_shellframe_sel_validate_ctx() {
    local _ctx="$1"
    if [[ -z "$_ctx" || ! "$_ctx" =~ ^[a-zA-Z0-9_]+$ ]]; then
        printf 'shellframe_sel: invalid context name: %q (must match [a-zA-Z0-9_]+)\n' \
            "$_ctx" >&2
        return 1
    fi
}

# Get the multi-select flag for item at index $2 in context $1.
# Prints "0" or "1" to stdout.
_shellframe_sel_get_flag() {
    local _ctx="$1" _i="$2"
    local _flags_var="_SHELLFRAME_SEL_${_ctx}_FLAGS"
    local _flags="${!_flags_var}"
    printf '%s' "${_flags:$_i:1}"
}

# Set the multi-select flag for item at index $3 in context $1 to value $3.
# Value must be "0" or "1".
_shellframe_sel_set_flag() {
    local _ctx="$1" _i="$2" _val="$3"
    local _flags_var="_SHELLFRAME_SEL_${_ctx}_FLAGS"
    local _flags="${!_flags_var}"
    local _new="${_flags:0:$_i}${_val}${_flags:$(( _i + 1 ))}"
    printf -v "$_flags_var" '%s' "$_new"
}

# ── shellframe_sel_init ────────────────────────────────────────────────────────

# Initialise selection state for context $ctx with $count items.
# Resets cursor to 0 and clears all multi-select flags.
# Must be called before any other selection function for a new context.
shellframe_sel_init() {
    local _ctx="$1" _count="${2:-0}"
    _shellframe_sel_validate_ctx "$_ctx" || return 1
    printf -v "_SHELLFRAME_SEL_${_ctx}_CURSOR" '%d' 0
    printf -v "_SHELLFRAME_SEL_${_ctx}_COUNT"  '%d' "$_count"
    # Build a flags bitmap of all-0 with length = count.
    local _flags="" _i
    for (( _i=0; _i<_count; _i++ )); do _flags+="0"; done
    printf -v "_SHELLFRAME_SEL_${_ctx}_FLAGS" '%s' "$_flags"
}

# ── shellframe_sel_move ────────────────────────────────────────────────────────

# Move the cursor in direction $dir. Cursor is clamped to [0, count-1].
# page_up / page_down move by $page_size rows (default 10).
#
# Directions: up | down | home | end | page_up | page_down
shellframe_sel_move() {
    local _ctx="$1" _dir="$2" _page="${3:-10}"
    _shellframe_sel_validate_ctx "$_ctx" || return 1

    local _cursor_var="_SHELLFRAME_SEL_${_ctx}_CURSOR"
    local _count_var="_SHELLFRAME_SEL_${_ctx}_COUNT"
    local _cursor="${!_cursor_var}"
    local _count="${!_count_var}"

    # Guard: nothing to move in an empty list.
    (( _count <= 0 )) && return 0

    case "$_dir" in
        up)
            (( _cursor > 0 )) && (( _cursor-- )) || true
            ;;
        down)
            (( _cursor < _count - 1 )) && (( _cursor++ )) || true
            ;;
        home)
            _cursor=0
            ;;
        end)
            _cursor=$(( _count - 1 ))
            ;;
        page_up)
            _cursor=$(( _cursor - _page ))
            (( _cursor < 0 )) && _cursor=0 || true
            ;;
        page_down)
            _cursor=$(( _cursor + _page ))
            (( _cursor >= _count )) && _cursor=$(( _count - 1 )) || true
            ;;
        *)
            printf 'shellframe_sel_move: unknown direction: %s\n' "$_dir" >&2
            return 1
            ;;
    esac

    printf -v "$_cursor_var" '%d' "$_cursor"
}

# ── shellframe_sel_toggle ──────────────────────────────────────────────────────

# Toggle the multi-select flag for item at $index (default: current cursor).
# If the item is selected, it becomes deselected, and vice versa.
shellframe_sel_toggle() {
    local _ctx="$1" _index="${2:-}"
    _shellframe_sel_validate_ctx "$_ctx" || return 1

    local _cursor_var="_SHELLFRAME_SEL_${_ctx}_CURSOR"
    local _count_var="_SHELLFRAME_SEL_${_ctx}_COUNT"
    local _count="${!_count_var}"
    local _i="${_index:-${!_cursor_var}}"

    if (( _i < 0 || _i >= _count )); then
        printf 'shellframe_sel_toggle: index %d out of range [0, %d)\n' \
            "$_i" "$_count" >&2
        return 1
    fi

    local _cur_flag
    _cur_flag=$(_shellframe_sel_get_flag "$_ctx" "$_i")
    if [[ "$_cur_flag" == "1" ]]; then
        _shellframe_sel_set_flag "$_ctx" "$_i" "0"
    else
        _shellframe_sel_set_flag "$_ctx" "$_i" "1"
    fi
}

# ── shellframe_sel_select_all / shellframe_sel_clear_all ──────────────────────

# Set all multi-select flags to 1.
shellframe_sel_select_all() {
    local _ctx="$1"
    _shellframe_sel_validate_ctx "$_ctx" || return 1
    local _count_var="_SHELLFRAME_SEL_${_ctx}_COUNT"
    local _count="${!_count_var}"
    local _flags="" _i
    for (( _i=0; _i<_count; _i++ )); do _flags+="1"; done
    printf -v "_SHELLFRAME_SEL_${_ctx}_FLAGS" '%s' "$_flags"
}

# Set all multi-select flags to 0.
shellframe_sel_clear_all() {
    local _ctx="$1"
    _shellframe_sel_validate_ctx "$_ctx" || return 1
    local _count_var="_SHELLFRAME_SEL_${_ctx}_COUNT"
    local _count="${!_count_var}"
    local _flags="" _i
    for (( _i=0; _i<_count; _i++ )); do _flags+="0"; done
    printf -v "_SHELLFRAME_SEL_${_ctx}_FLAGS" '%s' "$_flags"
}

# ── shellframe_sel_cursor ──────────────────────────────────────────────────────

# Print the current cursor index to stdout.
shellframe_sel_cursor() {
    local _ctx="$1"
    _shellframe_sel_validate_ctx "$_ctx" || return 1
    local _cursor_var="_SHELLFRAME_SEL_${_ctx}_CURSOR"
    printf '%d' "${!_cursor_var:-0}"
}

# ── shellframe_sel_count ───────────────────────────────────────────────────────

# Print the total row count to stdout.
shellframe_sel_count() {
    local _ctx="$1"
    _shellframe_sel_validate_ctx "$_ctx" || return 1
    local _count_var="_SHELLFRAME_SEL_${_ctx}_COUNT"
    printf '%d' "${!_count_var:-0}"
}

# ── shellframe_sel_selected ────────────────────────────────────────────────────

# Print a space-separated list of selected (flag=1) row indices to stdout.
# Prints an empty line if nothing is selected.
shellframe_sel_selected() {
    local _ctx="$1"
    _shellframe_sel_validate_ctx "$_ctx" || return 1
    local _flags_var="_SHELLFRAME_SEL_${_ctx}_FLAGS"
    local _flags="${!_flags_var}"
    local _len="${#_flags}" _i _first=1
    for (( _i=0; _i<_len; _i++ )); do
        if [[ "${_flags:$_i:1}" == "1" ]]; then
            (( _first )) || printf ' '
            printf '%d' "$_i"
            _first=0
        fi
    done
    printf '\n'
}

# ── shellframe_sel_selected_count ─────────────────────────────────────────────

# Print the count of selected items (flag=1) to stdout.
shellframe_sel_selected_count() {
    local _ctx="$1"
    _shellframe_sel_validate_ctx "$_ctx" || return 1
    local _flags_var="_SHELLFRAME_SEL_${_ctx}_FLAGS"
    local _flags="${!_flags_var}"
    local _len="${#_flags}" _i _count=0
    for (( _i=0; _i<_len; _i++ )); do
        [[ "${_flags:$_i:1}" == "1" ]] && (( _count++ )) || true
    done
    printf '%d' "$_count"
}

# ── shellframe_sel_is_selected ─────────────────────────────────────────────────

# Return 0 if the item at $index has its flag set to 1, 1 otherwise.
# Suitable for: shellframe_sel_is_selected ctx 3 && echo "item 3 is selected"
shellframe_sel_is_selected() {
    local _ctx="$1" _index="$2"
    _shellframe_sel_validate_ctx "$_ctx" || return 1
    local _flag
    _flag=$(_shellframe_sel_get_flag "$_ctx" "$_index")
    [[ "$_flag" == "1" ]]
}
