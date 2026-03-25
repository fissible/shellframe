#!/usr/bin/env bash
# shellframe/src/widgets/tree.sh — Tree view widget (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/selection.sh, src/scroll.sh, src/draw.sh.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a scrollable tree of nodes with expand/collapse, cursor highlight,
# and keyboard navigation.  Nodes are provided as three parallel arrays in
# pre-order (parent before its children):
#
#   SHELLFRAME_TREE_ITEMS[@]       — display label per node
#   SHELLFRAME_TREE_DEPTHS[@]      — depth level per node (0 = root level)
#   SHELLFRAME_TREE_HASCHILDREN[@] — "1" if node has children, "0" otherwise
#
# Expand/collapse works by maintaining a flat "view" array of visible node
# indices.  A collapsed node hides all subsequent items at a deeper depth until
# the next item at the same or shallower depth.
#
# Multiple tree instances can coexist with different SHELLFRAME_TREE_CTX values.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_TREE_ITEMS[@]       — display labels (parallel to DEPTHS/HASCHILDREN)
#   SHELLFRAME_TREE_DEPTHS[@]      — depth of each node (0 = root level)
#   SHELLFRAME_TREE_HASCHILDREN[@] — "1" if node has children
#   SHELLFRAME_TREE_CTX            — context name (default: "tree")
#   SHELLFRAME_TREE_FOCUSED        — 0 (default) | 1
#   SHELLFRAME_TREE_FOCUSABLE      — 1 (default) | 0
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_TREE_RESULT         — node index (into SHELLFRAME_TREE_ITEMS) of
#                                    confirmed selection; set on Enter (rc=2)
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_tree_init [ctx] [viewport_rows]
#     Build initial view: all nodes visible, all parent nodes collapsed.
#     Call again after changing SHELLFRAME_TREE_ITEMS/DEPTHS/HASCHILDREN.
#
#   shellframe_tree_render top left width height
#     Draw visible items.  Output to /dev/tty.
#
#   shellframe_tree_on_key key
#     Returns:
#       0  — key handled (app shell should redraw)
#       1  — key not handled (pass to next handler)
#       2  — Enter pressed (node confirmed; read SHELLFRAME_TREE_RESULT)
#
#   shellframe_tree_on_focus focused  — set SHELLFRAME_TREE_FOCUSED
#
#   shellframe_tree_size              — print "1 1 0 0"
#
# ── Keyboard bindings ─────────────────────────────────────────────────────────
#
#   ↑ / ↓             — move cursor
#   → (Right)          — expand node (no-op if already expanded or leaf)
#   ← (Left)           — collapse expanded node; otherwise jump to parent
#   Space              — toggle expand/collapse
#   Page Up / Page Down — scroll by viewport height
#   Home / End         — jump to first / last visible node
#   Enter              — confirm selection (rc=2)

SHELLFRAME_TREE_CTX="tree"
SHELLFRAME_TREE_FOCUSED=0
SHELLFRAME_TREE_FOCUSABLE=1
SHELLFRAME_TREE_ITEMS=()
SHELLFRAME_TREE_DEPTHS=()
SHELLFRAME_TREE_HASCHILDREN=()
SHELLFRAME_TREE_RESULT=""

# ── Internal: expanded-state string (one "0"/"1" char per node index) ─────────

_shellframe_tree_get_expanded() {
    local _ctx="$1" _i="$2"
    local _var="_SHELLFRAME_TREE_${_ctx}_EXPANDED"
    local _str="${!_var:-}"
    printf '%s' "${_str:$_i:1}"
}

_shellframe_tree_set_expanded() {
    local _ctx="$1" _i="$2" _val="$3"
    local _var="_SHELLFRAME_TREE_${_ctx}_EXPANDED"
    local _str="${!_var:-}"
    local _new="${_str:0:$_i}${_val}${_str:$(( _i + 1 ))}"
    printf -v "$_var" '%s' "$_new"
}

# ── Internal: build the visible-node view ─────────────────────────────────────
#
# Walks SHELLFRAME_TREE_ITEMS in pre-order.  Skips items inside collapsed
# subtrees.  Stores result as a space-separated string of node indices in
# _SHELLFRAME_TREE_${ctx}_VIEW.

_shellframe_tree_build_view() {
    local _ctx="$1"
    local _n=${#SHELLFRAME_TREE_ITEMS[@]}
    local _view="" _i _skip_depth=-1

    for (( _i=0; _i<_n; _i++ )); do
        local _d="${SHELLFRAME_TREE_DEPTHS[$_i]:-0}"

        # Inside a collapsed subtree — skip until depth falls back to skip_depth
        if (( _skip_depth >= 0 )); then
            if (( _d > _skip_depth )); then
                continue
            else
                _skip_depth=-1
            fi
        fi

        _view="${_view:+$_view }$_i"

        # If this node has children and is collapsed, hide its subtree
        local _hc="${SHELLFRAME_TREE_HASCHILDREN[$_i]:-0}"
        local _exp
        _exp=$(_shellframe_tree_get_expanded "$_ctx" "$_i")
        if [[ "$_hc" == "1" && "$_exp" != "1" ]]; then
            _skip_depth="$_d"
        fi
    done

    printf -v "_SHELLFRAME_TREE_${_ctx}_VIEW" '%s' "$_view"
}

# ── Internal: split VIEW string into array ────────────────────────────────────

_shellframe_tree_parse_view() {
    # Usage: _shellframe_tree_parse_view ctx arr_name
    # Populates the named array variable with node indices from the VIEW string.
    local _ctx="$1" _arr_name="$2"
    local _view_var="_SHELLFRAME_TREE_${_ctx}_VIEW"
    local _view="${!_view_var:-}"
    if [[ -z "$_view" ]]; then
        eval "${_arr_name}=()"
        return
    fi
    local _old_IFS="$IFS"
    IFS=' ' read -r -a "$_arr_name" <<< "$_view"
    IFS="$_old_IFS"
}

# ── Internal: count visible view rows ────────────────────────────────────────

_shellframe_tree_view_count() {
    local _ctx="$1"
    local _view_var="_SHELLFRAME_TREE_${_ctx}_VIEW"
    local _view="${!_view_var:-}"
    if [[ -z "$_view" ]]; then
        printf '0'
        return
    fi
    local _arr
    _shellframe_tree_parse_view "$_ctx" _arr
    printf '%d' "${#_arr[@]}"
}

# ── Internal: convert view cursor position → node index ──────────────────────

_shellframe_tree_view_to_node() {
    local _ctx="$1" _vcursor="$2" _out="${3:-}"
    local _arr
    _shellframe_tree_parse_view "$_ctx" _arr
    local _node="${_arr[$_vcursor]:-0}"
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%d' "$_node"
    else
        printf '%d' "$_node"
    fi
}

# ── Internal: find view cursor position for a given node index ────────────────

_shellframe_tree_node_to_view() {
    local _ctx="$1" _node_idx="$2" _out="${3:-}"
    local _arr
    _shellframe_tree_parse_view "$_ctx" _arr
    local _vi _result=0
    for (( _vi=0; _vi<${#_arr[@]}; _vi++ )); do
        if [[ "${_arr[$_vi]}" == "$_node_idx" ]]; then
            _result="$_vi"
            break
        fi
    done
    if [[ -n "$_out" ]]; then
        printf -v "$_out" '%d' "$_result"
    else
        printf '%d' "$_result"
    fi
}

# ── Internal: rebuild sel + scroll state after view changes ──────────────────
#
# Preserves current node identity: after view rebuilds, places the cursor
# on the same node it was on before (or its nearest visible ancestor).

_shellframe_tree_sync_state() {
    local _ctx="$1" _node_idx="$2"

    local _vcount
    _vcount=$(_shellframe_tree_view_count "$_ctx")

    # Find where the given node_idx appears in the new view
    local _new_vcursor=0
    _shellframe_tree_node_to_view "$_ctx" "$_node_idx" _new_vcursor

    # Clamp to new count
    (( _new_vcursor >= _vcount && _vcount > 0 )) && _new_vcursor=$(( _vcount - 1 ))
    (( _new_vcursor < 0 )) && _new_vcursor=0

    # Update selection state (single-select only; rebuild flags at new length)
    local _flags="" _fi
    for (( _fi=0; _fi<_vcount; _fi++ )); do _flags+="0"; done
    printf -v "_SHELLFRAME_SEL_${_ctx}_COUNT"  '%d' "$_vcount"
    printf -v "_SHELLFRAME_SEL_${_ctx}_FLAGS"  '%s' "$_flags"
    printf -v "_SHELLFRAME_SEL_${_ctx}_CURSOR" '%d' "$_new_vcursor"

    # Update scroll total rows; re-clamp; ensure cursor visible
    printf -v "_SHELLFRAME_SCROLL_${_ctx}_ROWS" '%d' "$_vcount"
    shellframe_scroll_move "$_ctx" down 0
    shellframe_scroll_ensure_row "$_ctx" "$_new_vcursor"
}

# ── Internal: toggle expand/collapse for the cursor node ─────────────────────

_shellframe_tree_toggle_node() {
    local _ctx="$1"
    local _vcursor
    shellframe_sel_cursor "$_ctx" _vcursor

    local _node_idx
    _shellframe_tree_view_to_node "$_ctx" "$_vcursor" _node_idx

    local _hc="${SHELLFRAME_TREE_HASCHILDREN[$_node_idx]:-0}"
    [[ "$_hc" != "1" ]] && return 0   # leaf: nothing to toggle

    local _exp
    _exp=$(_shellframe_tree_get_expanded "$_ctx" "$_node_idx")
    if [[ "$_exp" == "1" ]]; then
        _shellframe_tree_set_expanded "$_ctx" "$_node_idx" "0"
    else
        _shellframe_tree_set_expanded "$_ctx" "$_node_idx" "1"
    fi

    _shellframe_tree_build_view "$_ctx"
    _shellframe_tree_sync_state "$_ctx" "$_node_idx"
}

# ── shellframe_tree_init ──────────────────────────────────────────────────────

shellframe_tree_init() {
    local _ctx="${1:-${SHELLFRAME_TREE_CTX:-tree}}"
    local _vrows="${2:-10}"
    local _n=${#SHELLFRAME_TREE_ITEMS[@]}

    # All nodes start collapsed
    local _expanded="" _i
    for (( _i=0; _i<_n; _i++ )); do _expanded+="0"; done
    printf -v "_SHELLFRAME_TREE_${_ctx}_EXPANDED" '%s' "$_expanded"

    _shellframe_tree_build_view "$_ctx"

    local _vcount
    _vcount=$(_shellframe_tree_view_count "$_ctx")
    shellframe_sel_init    "$_ctx" "$_vcount"
    shellframe_scroll_init "$_ctx" "$_vcount" 1 "$_vrows" 1
}

# ── shellframe_tree_render ────────────────────────────────────────────────────

shellframe_tree_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _ctx="${SHELLFRAME_TREE_CTX:-tree}"

    shellframe_scroll_resize "$_ctx" "$_height" 1

    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"
    local _rst="${SHELLFRAME_RESET:-$'\033[0m'}"

    local _view_arr
    _shellframe_tree_parse_view "$_ctx" _view_arr
    local _vcount="${#_view_arr[@]}"

    local _scroll_top
    shellframe_scroll_top "$_ctx" _scroll_top

    local _vcursor
    shellframe_sel_cursor "$_ctx" _vcursor

    local _r
    for (( _r=0; _r<_height; _r++ )); do
        local _row=$(( _top + _r ))
        local _vi=$(( _scroll_top + _r ))

        printf '\033[%d;%dH%*s' "$_row" "$_left" "$_width" '' >&3

        [[ $_vi -ge $_vcount ]] && continue

        local _node_idx="${_view_arr[$_vi]}"
        local _depth="${SHELLFRAME_TREE_DEPTHS[$_node_idx]:-0}"
        local _label="${SHELLFRAME_TREE_ITEMS[$_node_idx]:-}"
        local _hc="${SHELLFRAME_TREE_HASCHILDREN[$_node_idx]:-0}"

        local _exp
        _exp=$(_shellframe_tree_get_expanded "$_ctx" "$_node_idx")

        # Indent: 2 spaces per depth level
        local _indent="" _di=0
        while (( _di < _depth )); do
            _indent+="  "
            (( _di++ ))
        done

        # Expand/collapse icon
        local _icon
        if [[ "$_hc" == "1" ]]; then
            [[ "$_exp" == "1" ]] && _icon="▼ " || _icon="▶ "
        else
            _icon="  "
        fi

        local _text="${_indent}${_icon}${_label}"
        local _clipped
        _clipped=$(shellframe_str_clip_ellipsis "$_text" "$_text" "$_width")

        printf '\033[%d;%dH' "$_row" "$_left" >&3

        if (( _vi == _vcursor )); then
            printf '%s' "$_rev" >&3
            printf '%s' "$_clipped" >&3
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

    printf '\033[%d;%dH' "$(( _top + _height - 1 ))" "$_left" >&3
}

# ── shellframe_tree_on_key ────────────────────────────────────────────────────

shellframe_tree_on_key() {
    local _key="$1"
    local _ctx="${SHELLFRAME_TREE_CTX:-tree}"

    local _vr_var="_SHELLFRAME_SCROLL_${_ctx}_VROWS"
    local _vrows="${!_vr_var:-10}"

    local _k_up="${SHELLFRAME_KEY_UP:-$'\033[A'}"
    local _k_down="${SHELLFRAME_KEY_DOWN:-$'\033[B'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_pgup="${SHELLFRAME_KEY_PAGE_UP:-$'\033[5~'}"
    local _k_pgdn="${SHELLFRAME_KEY_PAGE_DOWN:-$'\033[6~'}"
    local _k_home="${SHELLFRAME_KEY_HOME:-$'\033[H'}"
    local _k_end="${SHELLFRAME_KEY_END:-$'\033[F'}"

    if [[ "$_key" == $'\r' ]] || [[ "$_key" == $'\n' ]]; then
        local _vcursor
        shellframe_sel_cursor "$_ctx" _vcursor
        _shellframe_tree_view_to_node "$_ctx" "$_vcursor" SHELLFRAME_TREE_RESULT
        shellframe_shell_mark_dirty
        return 2

    elif [[ "$_key" == "$_k_down" ]]; then
        shellframe_sel_move "$_ctx" down
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        shellframe_shell_mark_dirty; return 0

    elif [[ "$_key" == "$_k_up" ]]; then
        shellframe_sel_move "$_ctx" up
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        shellframe_shell_mark_dirty; return 0

    elif [[ "$_key" == "$_k_right" ]]; then
        # Expand the current node if it has children and is currently collapsed
        local _vcursor
        shellframe_sel_cursor "$_ctx" _vcursor
        local _node_idx
        _shellframe_tree_view_to_node "$_ctx" "$_vcursor" _node_idx
        local _hc="${SHELLFRAME_TREE_HASCHILDREN[$_node_idx]:-0}"
        local _exp
        _exp=$(_shellframe_tree_get_expanded "$_ctx" "$_node_idx")
        if [[ "$_hc" == "1" && "$_exp" != "1" ]]; then
            _shellframe_tree_toggle_node "$_ctx"
        fi
        shellframe_shell_mark_dirty; return 0

    elif [[ "$_key" == "$_k_left" ]]; then
        local _vcursor
        shellframe_sel_cursor "$_ctx" _vcursor
        local _node_idx
        _shellframe_tree_view_to_node "$_ctx" "$_vcursor" _node_idx
        local _hc="${SHELLFRAME_TREE_HASCHILDREN[$_node_idx]:-0}"
        local _exp
        _exp=$(_shellframe_tree_get_expanded "$_ctx" "$_node_idx")

        if [[ "$_hc" == "1" && "$_exp" == "1" ]]; then
            # Collapse the expanded node
            _shellframe_tree_toggle_node "$_ctx"
        else
            # Jump to parent: search backwards in view for shallower depth
            local _depth="${SHELLFRAME_TREE_DEPTHS[$_node_idx]:-0}"
            if (( _depth > 0 )); then
                local _view_arr
                _shellframe_tree_parse_view "$_ctx" _view_arr
                local _vi
                for (( _vi=_vcursor-1; _vi>=0; _vi-- )); do
                    local _pnode="${_view_arr[$_vi]}"
                    local _pdepth="${SHELLFRAME_TREE_DEPTHS[$_pnode]:-0}"
                    if (( _pdepth < _depth )); then
                        printf -v "_SHELLFRAME_SEL_${_ctx}_CURSOR" '%d' "$_vi"
                        shellframe_scroll_ensure_row "$_ctx" "$_vi"
                        break
                    fi
                done
            fi
        fi
        shellframe_shell_mark_dirty; return 0

    elif [[ "$_key" == " " ]]; then
        _shellframe_tree_toggle_node "$_ctx"
        shellframe_shell_mark_dirty; return 0

    elif [[ "$_key" == "$_k_pgdn" ]]; then
        shellframe_sel_move "$_ctx" page_down "$_vrows"
        shellframe_scroll_move "$_ctx" page_down
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        shellframe_shell_mark_dirty; return 0

    elif [[ "$_key" == "$_k_pgup" ]]; then
        shellframe_sel_move "$_ctx" page_up "$_vrows"
        shellframe_scroll_move "$_ctx" page_up
        shellframe_scroll_ensure_row "$_ctx" "$(shellframe_sel_cursor "$_ctx")"
        shellframe_shell_mark_dirty; return 0

    elif [[ "$_key" == "$_k_home" ]]; then
        shellframe_sel_move "$_ctx" home
        shellframe_scroll_move "$_ctx" home
        shellframe_shell_mark_dirty; return 0

    elif [[ "$_key" == "$_k_end" ]]; then
        shellframe_sel_move "$_ctx" end
        shellframe_scroll_move "$_ctx" end
        shellframe_shell_mark_dirty; return 0
    fi

    return 1
}

# ── shellframe_tree_on_focus ──────────────────────────────────────────────────

shellframe_tree_on_focus() {
    SHELLFRAME_TREE_FOCUSED="${1:-0}"
}

# ── shellframe_tree_size ──────────────────────────────────────────────────────

# min: 1×1; preferred: fill all available space (0×0)
shellframe_tree_size() {
    printf '%d %d %d %d' 1 1 0 0
}
