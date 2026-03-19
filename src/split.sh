#!/usr/bin/env bash
# shellframe/src/split.sh — Composable split-pane layout
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/scroll.sh sourced first (for validation pattern reference).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Divides a rectangular area into 2 or 3 child panes separated by 1-cell
# box-drawing separators.  This is a layout helper, not a widget — it
# computes bounds and draws separators, while shell.sh manages focus across
# child regions via its existing Tab traversal.
#
# ── Orientation ─────────────────────────────────────────────────────────────
#
#   Vertical ("v") — children side by side:
#     ┌──────┬──────┐          ┌──────┬──────┬──────┐
#     │  C0  │  C1  │    or    │  C0  │  C1  │  C2  │
#     └──────┴──────┘          └──────┴──────┴──────┘
#
#   Horizontal ("h") — children stacked:
#     ┌──────────────┐         ┌──────────────┐
#     │      C0      │         │      C0      │
#     ├──────────────┤         ├──────────────┤
#     │      C1      │   or    │      C1      │
#     └──────────────┘         ├──────────────┤
#                              │      C2      │
#                              └──────────────┘
#
# ── Size spec ───────────────────────────────────────────────────────────────
#
# Sizes are colon-separated: "30:0" or "20:0:15".
#   - A positive integer is a fixed size (columns for "v", rows for "h").
#   - 0 means flex — takes the remaining space after fixed sizes and
#     separators are allocated.  Multiple flex children split equally;
#     the last flex child absorbs any integer remainder.
#
# ── Dynamic globals (internal; do not access directly) ─────────────────────
#
#   _SHELLFRAME_SPLIT_${ctx}_DIR     — "v" | "h"
#   _SHELLFRAME_SPLIT_${ctx}_COUNT   — 2 | 3
#   _SHELLFRAME_SPLIT_${ctx}_SIZES   — colon-separated size spec
#   _SHELLFRAME_SPLIT_${ctx}_BORDER  — "single" | "none"
#
# ── Public API ──────────────────────────────────────────────────────────────
#
#   shellframe_split_init ctx direction count sizes
#     Initialise a split context.
#
#   shellframe_split_set_border ctx style
#     Set separator style: "single" (default) or "none".
#
#   shellframe_split_bounds ctx index top left width height out_top out_left out_w out_h
#     Compute child[index] bounds within the container (top,left,width,height).
#     Stores results via printf -v into the four out_* variables.
#
#   shellframe_split_render ctx top left width height
#     Draw separator lines between children.  Does NOT render children.
#
#   shellframe_split_regions ctx top left width height name_0 [focus_0] name_1 [focus_1] [name_2 [focus_2]]
#     Convenience: calls shellframe_shell_region for each child with computed
#     bounds.  focus_N defaults to "focus".

# ── Internal helper ─────────────────────────────────────────────────────────

_shellframe_split_validate_ctx() {
    local _ctx="$1"
    if [[ -z "$_ctx" || ! "$_ctx" =~ ^[a-zA-Z0-9_]+$ ]]; then
        printf 'shellframe_split: invalid context name: %q\n' "$_ctx" >&2
        return 1
    fi
}

# ── _shellframe_split_compute ───────────────────────────────────────────────
#
# Core layout computation.  Given container bounds, computes each child's
# bounds accounting for separator gaps.  Results are stored in:
#   _SHELLFRAME_SPLIT_${ctx}_C${i}_TOP / LEFT / W / H
#   _SHELLFRAME_SPLIT_${ctx}_SEP${i}_POS   (separator position for sep i)
#
# Separator count = count - 1.  Each separator is 1 cell wide/tall.

_shellframe_split_compute() {
    local _ctx="$1" _top="$2" _left="$3" _width="$4" _height="$5"

    local _dir_var="_SHELLFRAME_SPLIT_${_ctx}_DIR"
    local _count_var="_SHELLFRAME_SPLIT_${_ctx}_COUNT"
    local _sizes_var="_SHELLFRAME_SPLIT_${_ctx}_SIZES"

    local _dir="${!_dir_var:-v}"
    local _count="${!_count_var:-2}"
    local _sizes="${!_sizes_var:-0:0}"

    # Parse sizes into positional locals
    local _s0 _s1 _s2
    _s0="${_sizes%%:*}"
    local _rest="${_sizes#*:}"
    _s1="${_rest%%:*}"
    _s2="${_rest#*:}"
    [[ "$_s2" == "$_s1" ]] && _s2=0   # no third element
    (( _count < 3 )) && _s2=0

    local _sep_count=$(( _count - 1 ))

    # Total space along the split axis
    local _total
    if [[ "$_dir" == "v" ]]; then
        _total="$_width"
    else
        _total="$_height"
    fi

    # Compute flex distribution
    local _total_fixed=$(( _s0 + _s1 + _s2 ))
    local _flex_space=$(( _total - _total_fixed - _sep_count ))
    (( _flex_space < 0 )) && _flex_space=0

    local _flex_count=0
    (( _s0 == 0 )) && (( _flex_count++ ))
    (( _s1 == 0 )) && (( _flex_count++ ))
    (( _count >= 3 && _s2 == 0 )) && (( _flex_count++ ))

    local _flex_each=0 _flex_remainder=0
    if (( _flex_count > 0 )); then
        _flex_each=$(( _flex_space / _flex_count ))
        _flex_remainder=$(( _flex_space - _flex_each * _flex_count ))
    fi

    # Resolve sizes: replace 0 with flex_each, last flex child gets remainder
    local _resolved_0="$_s0" _resolved_1="$_s1" _resolved_2="$_s2"
    local _flex_assigned=0

    if (( _s0 == 0 )); then
        _resolved_0="$_flex_each"
        (( _flex_assigned++ ))
    fi
    if (( _s1 == 0 )); then
        _resolved_1="$_flex_each"
        (( _flex_assigned++ ))
    fi
    if (( _count >= 3 && _s2 == 0 )); then
        _resolved_2="$_flex_each"
        (( _flex_assigned++ ))
    fi

    # Give remainder to the last flex child
    if (( _flex_remainder > 0 )); then
        if (( _count >= 3 && _s2 == 0 )); then
            _resolved_2=$(( _resolved_2 + _flex_remainder ))
        elif (( _s1 == 0 )); then
            _resolved_1=$(( _resolved_1 + _flex_remainder ))
        elif (( _s0 == 0 )); then
            _resolved_0=$(( _resolved_0 + _flex_remainder ))
        fi
    fi

    # Clamp to minimum 1
    (( _resolved_0 < 1 )) && _resolved_0=1
    (( _resolved_1 < 1 )) && _resolved_1=1
    (( _count >= 3 && _resolved_2 < 1 )) && _resolved_2=1

    # Compute child bounds
    if [[ "$_dir" == "v" ]]; then
        # Vertical: children side by side, share width
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C0_TOP"  '%d' "$_top"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C0_LEFT" '%d' "$_left"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C0_W"    '%d' "$_resolved_0"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C0_H"    '%d' "$_height"

        local _sep0_col=$(( _left + _resolved_0 ))
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_SEP0_POS" '%d' "$_sep0_col"

        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C1_TOP"  '%d' "$_top"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C1_LEFT" '%d' "$(( _sep0_col + 1 ))"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C1_W"    '%d' "$_resolved_1"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C1_H"    '%d' "$_height"

        if (( _count >= 3 )); then
            local _sep1_col=$(( _sep0_col + 1 + _resolved_1 ))
            printf -v "_SHELLFRAME_SPLIT_${_ctx}_SEP1_POS" '%d' "$_sep1_col"

            printf -v "_SHELLFRAME_SPLIT_${_ctx}_C2_TOP"  '%d' "$_top"
            printf -v "_SHELLFRAME_SPLIT_${_ctx}_C2_LEFT" '%d' "$(( _sep1_col + 1 ))"
            printf -v "_SHELLFRAME_SPLIT_${_ctx}_C2_W"    '%d' "$_resolved_2"
            printf -v "_SHELLFRAME_SPLIT_${_ctx}_C2_H"    '%d' "$_height"
        fi
    else
        # Horizontal: children stacked, share height
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C0_TOP"  '%d' "$_top"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C0_LEFT" '%d' "$_left"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C0_W"    '%d' "$_width"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C0_H"    '%d' "$_resolved_0"

        local _sep0_row=$(( _top + _resolved_0 ))
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_SEP0_POS" '%d' "$_sep0_row"

        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C1_TOP"  '%d' "$(( _sep0_row + 1 ))"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C1_LEFT" '%d' "$_left"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C1_W"    '%d' "$_width"
        printf -v "_SHELLFRAME_SPLIT_${_ctx}_C1_H"    '%d' "$_resolved_1"

        if (( _count >= 3 )); then
            local _sep1_row=$(( _sep0_row + 1 + _resolved_1 ))
            printf -v "_SHELLFRAME_SPLIT_${_ctx}_SEP1_POS" '%d' "$_sep1_row"

            printf -v "_SHELLFRAME_SPLIT_${_ctx}_C2_TOP"  '%d' "$(( _sep1_row + 1 ))"
            printf -v "_SHELLFRAME_SPLIT_${_ctx}_C2_LEFT" '%d' "$_left"
            printf -v "_SHELLFRAME_SPLIT_${_ctx}_C2_W"    '%d' "$_width"
            printf -v "_SHELLFRAME_SPLIT_${_ctx}_C2_H"    '%d' "$_resolved_2"
        fi
    fi
}

# ── shellframe_split_init ───────────────────────────────────────────────────

shellframe_split_init() {
    local _ctx="$1" _dir="$2" _count="$3" _sizes="$4"
    _shellframe_split_validate_ctx "$_ctx" || return 1
    printf -v "_SHELLFRAME_SPLIT_${_ctx}_DIR"    '%s' "$_dir"
    printf -v "_SHELLFRAME_SPLIT_${_ctx}_COUNT"  '%d' "$_count"
    printf -v "_SHELLFRAME_SPLIT_${_ctx}_SIZES"  '%s' "$_sizes"
    printf -v "_SHELLFRAME_SPLIT_${_ctx}_BORDER" '%s' "single"
}

# ── shellframe_split_set_border ─────────────────────────────────────────────

shellframe_split_set_border() {
    local _ctx="$1" _style="$2"
    _shellframe_split_validate_ctx "$_ctx" || return 1
    printf -v "_SHELLFRAME_SPLIT_${_ctx}_BORDER" '%s' "$_style"
}

# ── shellframe_split_bounds ─────────────────────────────────────────────────

# Compute child[index] bounds within a container region.
# Usage:
#   local ct cl cw ch
#   shellframe_split_bounds "my_split" 0  $top $left $width $height  ct cl cw ch
shellframe_split_bounds() {
    local _ctx="$1" _index="$2"
    local _top="$3" _left="$4" _width="$5" _height="$6"
    local _out_top="$7" _out_left="$8" _out_w="$9"
    shift 9
    local _out_h="$1"

    _shellframe_split_compute "$_ctx" "$_top" "$_left" "$_width" "$_height"

    local _ct_var="_SHELLFRAME_SPLIT_${_ctx}_C${_index}_TOP"
    local _cl_var="_SHELLFRAME_SPLIT_${_ctx}_C${_index}_LEFT"
    local _cw_var="_SHELLFRAME_SPLIT_${_ctx}_C${_index}_W"
    local _ch_var="_SHELLFRAME_SPLIT_${_ctx}_C${_index}_H"

    printf -v "$_out_top"  '%d' "${!_ct_var}"
    printf -v "$_out_left" '%d' "${!_cl_var}"
    printf -v "$_out_w"    '%d' "${!_cw_var}"
    printf -v "$_out_h"    '%d' "${!_ch_var}"
}

# ── shellframe_split_render ─────────────────────────────────────────────────

# Draw separator lines between children.  Does NOT render child content.
shellframe_split_render() {
    local _ctx="$1" _top="$2" _left="$3" _width="$4" _height="$5"

    local _border_var="_SHELLFRAME_SPLIT_${_ctx}_BORDER"
    local _border="${!_border_var:-single}"
    [[ "$_border" == "none" ]] && return 0

    _shellframe_split_compute "$_ctx" "$_top" "$_left" "$_width" "$_height"

    local _dir_var="_SHELLFRAME_SPLIT_${_ctx}_DIR"
    local _count_var="_SHELLFRAME_SPLIT_${_ctx}_COUNT"
    local _dir="${!_dir_var:-v}"
    local _count="${!_count_var:-2}"

    local _color="${SHELLFRAME_GRAY:-}"
    local _reset="${SHELLFRAME_RESET:-}"

    local _i
    for (( _i=0; _i < _count - 1; _i++ )); do
        local _pos_var="_SHELLFRAME_SPLIT_${_ctx}_SEP${_i}_POS"
        local _pos="${!_pos_var}"

        if [[ "$_dir" == "v" ]]; then
            # Vertical separator: column of │
            local _r
            for (( _r=0; _r < _height; _r++ )); do
                printf '\033[%d;%dH%s│%s' \
                    "$(( _top + _r ))" "$_pos" "$_color" "$_reset" >/dev/tty
            done
        else
            # Horizontal separator: row of ─
            printf '\033[%d;%dH%s' "$_pos" "$_left" "$_color" >/dev/tty
            local _c
            for (( _c=0; _c < _width; _c++ )); do
                printf '─' >/dev/tty
            done
            printf '%s' "$_reset" >/dev/tty
        fi
    done
}

# ── shellframe_split_regions ────────────────────────────────────────────────

# Convenience: register shell.sh regions for each child pane.
# Call from within PREFIX_SCREEN_render().
#
# Usage (2 panes):
#   shellframe_split_regions "my_split" $top $left $w $h \
#       "left_pane" "focus" "right_pane" "focus"
#
# Usage (3 panes, middle is nofocus):
#   shellframe_split_regions "my_split" $top $left $w $h \
#       "left" "focus" "center" "nofocus" "right" "focus"
shellframe_split_regions() {
    local _ctx="$1" _top="$2" _left="$3" _width="$4" _height="$5"
    shift 5

    local _count_var="_SHELLFRAME_SPLIT_${_ctx}_COUNT"
    local _count="${!_count_var:-2}"

    _shellframe_split_compute "$_ctx" "$_top" "$_left" "$_width" "$_height"

    local _i
    for (( _i=0; _i < _count; _i++ )); do
        local _name="${1:-child${_i}}"
        shift || true
        local _focus="${1:-focus}"
        # Only shift if the next arg looks like a focus keyword, not a region name
        if [[ "$_focus" == "focus" || "$_focus" == "nofocus" ]]; then
            shift || true
        else
            _focus="focus"
        fi

        local _ct_var="_SHELLFRAME_SPLIT_${_ctx}_C${_i}_TOP"
        local _cl_var="_SHELLFRAME_SPLIT_${_ctx}_C${_i}_LEFT"
        local _cw_var="_SHELLFRAME_SPLIT_${_ctx}_C${_i}_W"
        local _ch_var="_SHELLFRAME_SPLIT_${_ctx}_C${_i}_H"

        shellframe_shell_region "$_name" \
            "${!_ct_var}" "${!_cl_var}" "${!_cw_var}" "${!_ch_var}" "$_focus"
    done
}
