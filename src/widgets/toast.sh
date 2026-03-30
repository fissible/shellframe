#!/usr/bin/env bash
# shellframe/src/widgets/toast.sh — Transient status toast notifications
#
# COMPATIBILITY: bash 3.2+
# REQUIRES: src/draw.sh, src/screen.sh sourced first.
#
# ── State ─────────────────────────────────────────────────────────────────────
#
#   _SHELLFRAME_TOAST_QUEUE[@]  — entries: "message<TAB>style<TAB>ttl"
#                                 newest entry at index 0 (prepend on add)
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_toast_show message [style] [duration]
#     Queue a toast. style: info|success|error|warning (default: info).
#     duration: render-cycle TTL (default: 30).
#
#   shellframe_toast_tick
#     Decrement all TTLs. Remove expired entries. Call once per event loop.
#
#   shellframe_toast_render top left width height
#     Draw all queued toasts (newest on top) at bottom-right of region.
#     Must be called at the end of the screen render pass.
#
#   shellframe_toast_clear
#     Empty the queue (useful for testing and screen teardown).

_SHELLFRAME_TOAST_QUEUE=()
_SHELLFRAME_TOAST_MAX=3
_SHELLFRAME_TOAST_DEFAULT_TTL=30

# ── shellframe_toast_clear ────────────────────────────────────────────────────

shellframe_toast_clear() {
    _SHELLFRAME_TOAST_QUEUE=()
}

# ── shellframe_toast_show ─────────────────────────────────────────────────────

shellframe_toast_show() {
    local _msg="$1"
    local _style="${2:-info}"
    local _ttl="${3:-${_SHELLFRAME_TOAST_DEFAULT_TTL}}"

    # Prepend (newest first) and cap at max
    local _entry="${_msg}"$'\t'"${_style}"$'\t'"${_ttl}"
    local _new_queue=("$_entry")
    local _i
    for (( _i=0; _i<${#_SHELLFRAME_TOAST_QUEUE[@]}; _i++ )); do
        (( (_i + 1) >= _SHELLFRAME_TOAST_MAX )) && break
        _new_queue+=("${_SHELLFRAME_TOAST_QUEUE[$_i]}")
    done
    _SHELLFRAME_TOAST_QUEUE=("${_new_queue[@]}")
}

# ── shellframe_toast_tick ─────────────────────────────────────────────────────

shellframe_toast_tick() {
    local _new_queue=()
    local _entry
    for _entry in "${_SHELLFRAME_TOAST_QUEUE[@]+"${_SHELLFRAME_TOAST_QUEUE[@]}"}"; do
        local _ttl="${_entry##*$'\t'}"
        local _rest="${_entry%$'\t'*}"
        (( _ttl-- ))
        if (( _ttl > 0 )); then
            _new_queue+=("${_rest}"$'\t'"${_ttl}")
        fi
    done
    _SHELLFRAME_TOAST_QUEUE=("${_new_queue[@]+"${_new_queue[@]}"}")
}

# ── shellframe_toast_render ───────────────────────────────────────────────────

shellframe_toast_render() {
    local _rtop="$1" _rleft="$2" _rw="$3" _rh="$4"
    local _n=${#_SHELLFRAME_TOAST_QUEUE[@]}
    (( _n == 0 )) && return 0

    # Each toast: 1 row high, max 40 chars wide, right-aligned with 1-col margin
    local _toast_max_w=40
    local _toast_w=$(( _toast_max_w < _rw - 2 ? _toast_max_w : _rw - 2 ))
    (( _toast_w < 10 )) && return 0

    local _col=$(( _rleft + _rw - _toast_w - 1 ))
    local _i
    for (( _i=0; _i<_n; _i++ )); do
        local _row=$(( _rtop + _rh - 1 - _i ))
        (( _row < _rtop )) && break

        local _entry="${_SHELLFRAME_TOAST_QUEUE[$_i]}"
        local _msg="${_entry%%$'\t'*}"
        local _rest="${_entry#*$'\t'}"
        local _style="${_rest%%$'\t'*}"

        # Style → color
        local _color=""
        case "$_style" in
            success) _color="${SHELLFRAME_GREEN:-$'\033[32m'}" ;;
            error)   _color="${SHELLFRAME_RED:-$'\033[31m'}" ;;
            warning) _color="${SHELLFRAME_YELLOW:-$'\033[33m'}" ;;
            *)       _color="${SHELLFRAME_GRAY:-$'\033[2m'}" ;;
        esac

        # Clip message to fit (accounting for 1 padding space each side)
        local _inner_w=$(( _toast_w - 2 ))
        (( _inner_w < 1 )) && _inner_w=1
        local _clipped="$_msg"
        if (( ${#_clipped} > _inner_w )); then
            _clipped="${_clipped:0:$(( _inner_w - 1 ))}…"
        fi

        shellframe_fb_fill "$_row" "$_col" "$_toast_w" " " "$_color"
        shellframe_fb_print "$_row" "$(( _col + 1 ))" "$_clipped" "$_color"
    done
}
