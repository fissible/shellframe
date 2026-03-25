#!/usr/bin/env bash
# shellframe/src/hitbox.sh — Widget bounding-box registry
#
# COMPATIBILITY: bash 3.2+ (macOS default).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Maps terminal coordinates (row, col) back to the named widget that occupies
# them. Used by the mouse routing layer to hit-test pointer events.
#
# Widgets are registered with their top-left origin and dimensions. Overlap
# resolution uses last-registered-wins: shellframe_widget_at returns the most
# recently registered widget that contains the point.
#
# ── Internal state ────────────────────────────────────────────────────────────
#
#   _SHELLFRAME_HITBOX_NAMES    — indexed array of widget names (insertion order)
#   _SHELLFRAME_HITBOX_TOP      — indexed array of top row per entry
#   _SHELLFRAME_HITBOX_LEFT     — indexed array of left col per entry
#   _SHELLFRAME_HITBOX_WIDTH    — indexed array of width per entry
#   _SHELLFRAME_HITBOX_HEIGHT   — indexed array of height per entry
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_widget_register name top left width height
#     Register widget NAME occupying rows [top, top+height-1] and
#     cols [left, left+width-1]. Does NOT deduplicate — call
#     shellframe_widget_clear NAME first for idempotent registration.
#
#   shellframe_widget_at row col [out_var]
#     Return the name of the most-recently-registered widget containing
#     (row, col), or empty string if no widget covers the point.
#     With out_var: sets that variable instead of printing to stdout.
#
#   shellframe_widget_clear [name]
#     No arguments: remove all registrations.
#     With NAME: remove all registrations for that specific widget name.

_SHELLFRAME_HITBOX_NAMES=()
_SHELLFRAME_HITBOX_TOP=()
_SHELLFRAME_HITBOX_LEFT=()
_SHELLFRAME_HITBOX_WIDTH=()
_SHELLFRAME_HITBOX_HEIGHT=()

shellframe_widget_register() {
    local _name="$1" _top="$2" _left="$3" _width="$4" _height="$5"
    local _n="${#_SHELLFRAME_HITBOX_NAMES[@]}"
    _SHELLFRAME_HITBOX_NAMES[$_n]="$_name"
    _SHELLFRAME_HITBOX_TOP[$_n]="$_top"
    _SHELLFRAME_HITBOX_LEFT[$_n]="$_left"
    _SHELLFRAME_HITBOX_WIDTH[$_n]="$_width"
    _SHELLFRAME_HITBOX_HEIGHT[$_n]="$_height"
}

shellframe_widget_at() {
    local _row="$1" _col="$2" _out_var="${3:-}"
    local _hit="" _i _count _top _left _width _height
    _count="${#_SHELLFRAME_HITBOX_NAMES[@]}"
    # Search backwards so last-registered entry wins on overlap
    for (( _i = _count - 1; _i >= 0; _i-- )); do
        _top="${_SHELLFRAME_HITBOX_TOP[$_i]}"
        _left="${_SHELLFRAME_HITBOX_LEFT[$_i]}"
        _width="${_SHELLFRAME_HITBOX_WIDTH[$_i]}"
        _height="${_SHELLFRAME_HITBOX_HEIGHT[$_i]}"
        if (( _row >= _top && _row < _top + _height &&
              _col >= _left && _col < _left + _width )); then
            _hit="${_SHELLFRAME_HITBOX_NAMES[$_i]}"
            break
        fi
    done
    if [[ -n "$_out_var" ]]; then
        printf -v "$_out_var" '%s' "$_hit"
    else
        printf '%s\n' "$_hit"
    fi
}

shellframe_widget_clear() {
    local _name="${1:-}"
    if [[ -z "$_name" ]]; then
        _SHELLFRAME_HITBOX_NAMES=()
        _SHELLFRAME_HITBOX_TOP=()
        _SHELLFRAME_HITBOX_LEFT=()
        _SHELLFRAME_HITBOX_WIDTH=()
        _SHELLFRAME_HITBOX_HEIGHT=()
        return 0
    fi
    local _i _count="${#_SHELLFRAME_HITBOX_NAMES[@]}"
    local _new_names=() _new_top=() _new_left=() _new_width=() _new_height=()
    for (( _i = 0; _i < _count; _i++ )); do
        if [[ "${_SHELLFRAME_HITBOX_NAMES[$_i]}" != "$_name" ]]; then
            _new_names+=("${_SHELLFRAME_HITBOX_NAMES[$_i]}")
            _new_top+=("${_SHELLFRAME_HITBOX_TOP[$_i]}")
            _new_left+=("${_SHELLFRAME_HITBOX_LEFT[$_i]}")
            _new_width+=("${_SHELLFRAME_HITBOX_WIDTH[$_i]}")
            _new_height+=("${_SHELLFRAME_HITBOX_HEIGHT[$_i]}")
        fi
    done
    _SHELLFRAME_HITBOX_NAMES=("${_new_names[@]+"${_new_names[@]}"}")
    _SHELLFRAME_HITBOX_TOP=("${_new_top[@]+"${_new_top[@]}"}")
    _SHELLFRAME_HITBOX_LEFT=("${_new_left[@]+"${_new_left[@]}"}")
    _SHELLFRAME_HITBOX_WIDTH=("${_new_width[@]+"${_new_width[@]}"}")
    _SHELLFRAME_HITBOX_HEIGHT=("${_new_height[@]+"${_new_height[@]}"}")
}
