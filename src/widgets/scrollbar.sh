#!/usr/bin/env bash
# shellframe/src/widgets/scrollbar.sh — Vertical scrollbar indicator
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/scroll.sh, src/screen.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a 1-column vertical scrollbar that visualises the current scroll
# position of a scroll.sh context.  The scrollbar consists of a track (dim
# background character) and a thumb (bright block character) whose position
# and size reflect the viewport's position within the total content.
#
# The scrollbar is purely decorative — it does not handle input.  It only
# renders when content exceeds the viewport (i.e. total_rows > viewport_rows).
#
# ── Characters ────────────────────────────────────────────────────────────────
#
#   Track:  ░  (U+2591 LIGHT SHADE)   — or space, configurable
#   Thumb:  █  (U+2588 FULL BLOCK)    — solid indicator
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_SCROLLBAR_TRACK   — track character (default: "░")
#   SHELLFRAME_SCROLLBAR_THUMB   — thumb character (default: "█")
#   SHELLFRAME_SCROLLBAR_STYLE   — ANSI prefix for track cells (default: dim)
#   SHELLFRAME_SCROLLBAR_THUMB_STYLE — ANSI prefix for thumb cells (default: "")
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_scrollbar_render ctx col top height [style] [thumb_style]
#     Render the scrollbar for scroll context $ctx in a single column at
#     terminal column $col, spanning rows $top..$top+$height-1.
#     Only renders if content overflows the viewport.
#     Returns 0 if rendered, 1 if content fits (nothing drawn).
#

SHELLFRAME_SCROLLBAR_TRACK="░"
SHELLFRAME_SCROLLBAR_THUMB="█"
SHELLFRAME_SCROLLBAR_STYLE=""
SHELLFRAME_SCROLLBAR_THUMB_STYLE=""

# ── shellframe_scrollbar_render ───────────────────────────────────────────────

shellframe_scrollbar_render() {
    local _ctx="$1" _col="$2" _top="$3" _height="$4"
    local _style="${5:-${SHELLFRAME_SCROLLBAR_STYLE:-}}"
    local _tstyle="${6:-${SHELLFRAME_SCROLLBAR_THUMB_STYLE:-}}"

    # Read scroll state
    local _rows_var="_SHELLFRAME_SCROLL_${_ctx}_ROWS"
    local _vrows_var="_SHELLFRAME_SCROLL_${_ctx}_VROWS"
    local _top_var="_SHELLFRAME_SCROLL_${_ctx}_TOP"

    local _total="${!_rows_var:-0}"
    local _vrows="${!_vrows_var:-0}"
    local _scroll_top="${!_top_var:-0}"

    # Don't render if content fits in viewport
    (( _total <= _vrows )) && return 1

    local _track="${SHELLFRAME_SCROLLBAR_TRACK:-░}"
    local _thumb="${SHELLFRAME_SCROLLBAR_THUMB:-█}"

    # Compute thumb size: proportional to viewport/total, minimum 1 row
    local _thumb_h=$(( _height * _vrows / _total ))
    (( _thumb_h < 1 )) && _thumb_h=1
    (( _thumb_h > _height )) && _thumb_h="$_height"

    # Compute thumb position: proportional to scroll offset
    local _max_scroll=$(( _total - _vrows ))
    local _track_space=$(( _height - _thumb_h ))
    local _thumb_top=0
    if (( _max_scroll > 0 && _track_space > 0 )); then
        _thumb_top=$(( _scroll_top * _track_space / _max_scroll ))
        (( _thumb_top > _track_space )) && _thumb_top="$_track_space"
    fi

    # Render track + thumb
    local _r
    for (( _r=0; _r<_height; _r++ )); do
        local _row=$(( _top + _r ))
        if (( _r >= _thumb_top && _r < _thumb_top + _thumb_h )); then
            shellframe_fb_put "$_row" "$_col" "${_tstyle}${_thumb}"
        else
            shellframe_fb_put "$_row" "$_col" "${_style}${_track}"
        fi
    done
    return 0
}
