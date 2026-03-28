#!/usr/bin/env bash
# shellframe/src/widgets/tab-bar.sh — Horizontal tab bar widget (v2 composable)
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh, src/draw.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a row of tab labels.  The active tab is highlighted with reverse
# video.  Left/Right arrows change the active tab.  Tabs that overflow the
# available width are clipped with an ellipsis.
#
# ── Input globals ─────────────────────────────────────────────────────────────
#
#   SHELLFRAME_TABBAR_LABELS[@]  — tab label strings (caller sets before render)
#   SHELLFRAME_TABBAR_ACTIVE     — index of the active tab (0-based)
#   SHELLFRAME_TABBAR_FOCUSED    — 0 | 1
#   SHELLFRAME_TABBAR_FOCUSABLE  — 1 (default) | 0
#
# ── Output globals ────────────────────────────────────────────────────────────
#
#   SHELLFRAME_TABBAR_ACTIVE  — updated by on_key when the active tab changes
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#   shellframe_tabbar_render top left width height
#     Draw labels in the first row of the region.  Output to /dev/tty.
#     Fills remaining columns with spaces.
#
#   shellframe_tabbar_on_key key
#     Left/Right: change active tab, return 0 (handled).
#     All other keys: return 1 (not handled).
#
#   shellframe_tabbar_on_focus focused  — set SHELLFRAME_TABBAR_FOCUSED
#
#   shellframe_tabbar_size              — print "3 1 0 1"

SHELLFRAME_TABBAR_ACTIVE=0
SHELLFRAME_TABBAR_FOCUSED=0
SHELLFRAME_TABBAR_FOCUSABLE=1
SHELLFRAME_TABBAR_LABELS=()
SHELLFRAME_TABBAR_BG=""   # override inactive-tab + fill background; empty = use SHELLFRAME_REVERSE

# Tab separator: │ (1 terminal column, UTF-8 box-drawing)
_SHELLFRAME_TABBAR_SEP='│'

# ── shellframe_tabbar_render ────────────────────────────────────────────────

shellframe_tabbar_render() {
    local _top="$1" _left="$2" _width="$3"
    # height param accepted; tab bar always occupies exactly 1 row
    local _active="${SHELLFRAME_TABBAR_ACTIVE:-0}"
    local _n=${#SHELLFRAME_TABBAR_LABELS[@]}

    # Clear the row
    shellframe_fb_fill "$_top" "$_left" "$_width"

    [[ $_n -eq 0 ]] && return 0

    # Clamp active to valid range
    (( _active >= _n )) && _active=$(( _n - 1 )) || true
    (( _active < 0 ))   && _active=0             || true

    local _rev="${SHELLFRAME_REVERSE:-$'\033[7m'}"
    local _bg="${SHELLFRAME_TABBAR_BG:-$_rev}"
    local _bold="${SHELLFRAME_BOLD:-$'\033[1m'}"

    local _remaining="$_width" _c="$_left" _i
    for (( _i=0; _i<_n; _i++ )); do
        (( _remaining <= 0 )) && break

        local _lbl="${SHELLFRAME_TABBAR_LABELS[$_i]}"
        local _tab=" ${_lbl} "
        local _tlen=$(( ${#_lbl} + 2 ))

        # Clip if tab doesn't fit in remaining space
        if (( _tlen > _remaining )); then
            if (( _remaining >= 3 )); then
                local _tc=$(( _remaining - 2 ))
                local _tc_clip
                shellframe_str_clip_ellipsis "$_lbl" "$_lbl" "$_tc" _tc_clip
                _tab=" ${_tc_clip} "
            elif (( _remaining == 2 )); then
                _tab=" …"
            elif (( _remaining == 1 )); then
                _tab="…"
            else
                break
            fi
            _tlen=$_remaining
        fi

        # Active tab: bold, default background (clear).
        # Inactive tabs: _bg (reverse video by default, overridable via SHELLFRAME_TABBAR_BG).
        if (( _i == _active )); then
            shellframe_fb_print "$_top" "$_c" "$_tab" "$_bold"
        else
            shellframe_fb_print "$_top" "$_c" "$_tab" "$_bg"
        fi
        (( _c += _tlen ))
        (( _remaining -= _tlen ))

        # Separator between tabs (1 terminal column)
        if (( _i < _n-1 && _remaining > 0 )); then
            shellframe_fb_put "$_top" "$_c" "$_SHELLFRAME_TABBAR_SEP"
            (( _c++ ))
            (( _remaining-- ))
        fi
    done

    # Fill remaining space with _bg to complete the solid bar.
    (( _remaining > 0 )) && shellframe_fb_fill "$_top" "$_c" "$_remaining" " " "$_bg"
}

# ── shellframe_tabbar_on_key ────────────────────────────────────────────────

shellframe_tabbar_on_key() {
    local _key="$1"
    local _n=${#SHELLFRAME_TABBAR_LABELS[@]}

    [[ $_n -eq 0 ]] && return 1

    local _active="${SHELLFRAME_TABBAR_ACTIVE:-0}"
    local _k_left="${SHELLFRAME_KEY_LEFT:-$'\033[D'}"
    local _k_right="${SHELLFRAME_KEY_RIGHT:-$'\033[C'}"

    if [[ "$_key" == "$_k_left" ]]; then
        (( _active > 0 )) && (( SHELLFRAME_TABBAR_ACTIVE-- )) || true
        shellframe_shell_mark_dirty; return 0
    fi

    if [[ "$_key" == "$_k_right" ]]; then
        (( _active < _n-1 )) && (( SHELLFRAME_TABBAR_ACTIVE++ )) || true
        shellframe_shell_mark_dirty; return 0
    fi

    return 1
}

# ── shellframe_tabbar_on_focus ───────────────────────────────────────────────

shellframe_tabbar_on_focus() {
    SHELLFRAME_TABBAR_FOCUSED="${1:-0}"
}

# ── shellframe_tabbar_size ───────────────────────────────────────────────────

# min: 3×1 (smallest useful tab " X "), preferred: full-width (0) × 1 row
shellframe_tabbar_size() {
    printf '%d %d %d %d' 3 1 0 1
}
