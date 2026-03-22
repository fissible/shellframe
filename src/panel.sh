#!/usr/bin/env bash
# shellframe/src/panel.sh — Box/Panel with border, title, and focus state
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh sourced first.
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Draws a bordered container with an optional title.  Used as the visual
# frame for most v2 widgets.  The panel itself is focusable and shows a
# visual focus indicator (bold/bright border when focused).
#
# Set SHELLFRAME_PANEL_* globals then call shellframe_panel_render.
# Use shellframe_panel_inner to get the content region inside the border.
#
# ── Border styles ─────────────────────────────────────────────────────────────
#
#   single   ┌─────────────┐     double   ╔═════════════╗
#            │             │              ║             ║
#            └─────────────┘              ╚═════════════╝
#
#   rounded  ╭─────────────╮     none     (spaces — no visual border)
#            │             │
#            ╰─────────────╯
#
# NOTE: box-drawing characters are multi-byte UTF-8 but each displays as
# exactly 1 terminal column.  Widths are tracked by loop count, not ${#char}.
#
# ── Input globals ──────────────────────────────────────────────────────────────
#
#   SHELLFRAME_PANEL_STYLE        — single (default) | double | rounded | none
#   SHELLFRAME_PANEL_TITLE        — title text (empty → no title shown)
#   SHELLFRAME_PANEL_TITLE_ALIGN  — left (default) | center | right
#   SHELLFRAME_PANEL_FOCUSED      — 0 (default) | 1 (bold border when focused)
#   SHELLFRAME_PANEL_FOCUSABLE    — 1 (default) | 0 (skip in Tab traversal)
#   SHELLFRAME_PANEL_MODE         — framed (default) | windowed
#   SHELLFRAME_PANEL_TITLE_BG     — ANSI bg escape for title bar row (windowed mode only)
#
# ── Public API ─────────────────────────────────────────────────────────────────
#
#   shellframe_panel_render top left width height
#     Draw the border and title within the region.  In framed mode (default),
#     the title is embedded in the top border line.  In windowed mode
#     (SHELLFRAME_PANEL_MODE=windowed), the title is rendered in a dedicated
#     full-width row inside the top border, styled with SHELLFRAME_PANEL_TITLE_BG.
#     Inner content area is NOT cleared — call shellframe_panel_inner to get
#     bounds and render child content yourself.  Output goes to fd 3.
#
#   shellframe_panel_inner top left width height out_top out_left out_width out_height
#     Compute the inner (content) region for the given panel region.
#     Stores results in the four named out_* variables (printf -v).
#     Accounts for border (1 cell each side) and SHELLFRAME_PANEL_PADDING.
#
#   shellframe_panel_on_key key
#     Always returns 1 (not handled) — panels delegate key handling to children.
#
#   shellframe_panel_on_focus focused
#     Set SHELLFRAME_PANEL_FOCUSED.  App shell calls render after this.
#
#   shellframe_panel_size
#     Print "min_width min_height preferred_width preferred_height".
#     min = 2×2 (border only); preferred = 0 (no constraint).

SHELLFRAME_PANEL_STYLE="single"
SHELLFRAME_PANEL_TITLE=""
SHELLFRAME_PANEL_TITLE_ALIGN="left"
SHELLFRAME_PANEL_FOCUSED=0
SHELLFRAME_PANEL_FOCUSABLE=1
SHELLFRAME_PANEL_MODE="framed"    # framed (default) | windowed
SHELLFRAME_PANEL_TITLE_BG=""      # ANSI escape for title bar background (windowed mode only)

# ── Internal: border character sets ───────────────────────────────────────────

# _shellframe_panel_chars style  →  sets _tl _hr _tr _vr _bl _br
# (top-left, horiz-rule, top-right, vert-rule, bot-left, bot-right)
_shellframe_panel_chars() {
    local _style="${1:-single}"
    case "$_style" in
        double)
            _tl='╔'; _hr='═'; _tr='╗'; _vr='║'; _bl='╚'; _br='╝' ;;
        rounded)
            _tl='╭'; _hr='─'; _tr='╮'; _vr='│'; _bl='╰'; _br='╯' ;;
        none)
            _tl=' '; _hr=' '; _tr=' '; _vr=' '; _bl=' '; _br=' ' ;;
        *)  # single (default)
            _tl='┌'; _hr='─'; _tr='┐'; _vr='│'; _bl='└'; _br='┘' ;;
    esac
}

# ── Internal: draw one horizontal border row ─────────────────────────────────

# _shellframe_panel_hline row col width left_char fill_char right_char [title] [title_align]
# Draws to stdout.  Visual column count is tracked explicitly (not ${#char}).
_shellframe_panel_hline() {
    local _row="$1" _col="$2" _width="$3" _lc="$4" _fc="$5" _rc="$6"
    local _title="${7:-}" _talign="${8:-left}"

    # Inner fill space = width - 2  (one col for each corner character)
    local _inner=$(( _width - 2 ))

    printf '\033[%d;%dH' "$_row" "$_col" >&3
    printf '%s' "$_lc" >&3

    if [[ -z "$_title" || $_inner -le 2 ]]; then
        # No title or no room: plain fill
        local _k=0
        while (( _k < _inner )); do
            printf '%s' "$_fc" >&3
            (( _k++ ))
        done
    else
        # Title section: " title " padded with fill char on each side.
        # Reserve at least 1 fill char on each side.
        local _ts=" ${_title} "
        local _ts_len=$(( ${#_title} + 2 ))
        local _avail=$(( _inner - 2 ))   # max title section width

        if (( _ts_len > _avail )); then
            # Clip title to fit
            local _clip_len=$(( _avail - 2 ))
            (( _clip_len < 0 )) && _clip_len=0
            _title="${_title:0:$_clip_len}"
            _ts=" ${_title} "
            _ts_len=$(( ${#_title} + 2 ))
        fi

        local _fill=$(( _inner - _ts_len ))
        local _lf=1 _rf=$(( _fill - 1 ))
        case "$_talign" in
            right)  _lf=$(( _fill - 1 )); _rf=1 ;;
            center) _lf=$(( _fill / 2 ));  _rf=$(( _fill - _lf )) ;;
        esac

        local _k=0
        while (( _k < _lf )); do printf '%s' "$_fc" >&3; (( _k++ )); done
        printf '%s' "$_ts" >&3
        _k=0
        while (( _k < _rf )); do printf '%s' "$_fc" >&3; (( _k++ )); done
    fi

    printf '%s' "$_rc" >&3
}

# ── shellframe_panel_render ────────────────────────────────────────────────────

shellframe_panel_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _style="${SHELLFRAME_PANEL_STYLE:-single}"
    local _title="${SHELLFRAME_PANEL_TITLE:-}"
    local _talign="${SHELLFRAME_PANEL_TITLE_ALIGN:-left}"
    local _focused="${SHELLFRAME_PANEL_FOCUSED:-0}"

    local _tl _hr _tr _vr _bl _br
    _shellframe_panel_chars "$_style"

    local _border=0
    [[ "$_style" != "none" ]] && _border=1

    # Apply focus color to border characters via ANSI bold (if tput gave us something)
    local _on="" _off=""
    if (( _focused )) && [[ -n "${SHELLFRAME_BOLD:-}" ]]; then
        _on="${SHELLFRAME_BOLD}"
        _off="${SHELLFRAME_RESET}"
    fi

    # Top border (with optional title)
    printf '%s' "$_on" >&3

    local _mode="${SHELLFRAME_PANEL_MODE:-framed}"
    if [[ "$_mode" == "windowed" ]]; then
        # Top border: no title embedded
        _shellframe_panel_hline "$_top" "$_left" "$_width" "$_tl" "$_hr" "$_tr"

        # Title bar row: full-width colored row immediately inside top border
        local _title_row=$(( _top + _border ))
        local _title_bg="${SHELLFRAME_PANEL_TITLE_BG:-}"
        local _title_rst="${SHELLFRAME_RESET:-$'\033[0m'}"
        local _title_text=" ${_title}"
        local _title_tlen=$(( ${#_title} + 1 ))
        local _inner_w=$(( _width - _border * 2 ))
        local _title_pad=$(( _inner_w - _title_tlen ))
        (( _title_pad < 0 )) && _title_pad=0
        local _title_spaces
        printf -v _title_spaces '%*s' "$_title_pad" ''
        printf '\033[%d;%dH%s%s%s%s%s' \
            "$_title_row" "$(( _left + _border ))" \
            "${_on}${_vr}${_off}" \
            "$_title_bg" "$_title_text" "$_title_spaces" "$_title_rst" >&3
        printf '\033[%d;%dH%s' \
            "$_title_row" "$(( _left + _width - 1 ))" \
            "${_on}${_vr}${_off}" >&3
    else
        # framed mode: title embedded in top border line (existing behaviour)
        _shellframe_panel_hline "$_top" "$_left" "$_width" "$_tl" "$_hr" "$_tr" "$_title" "$_talign"
    fi

    # Side borders
    local _r
    for (( _r=1; _r<_height-1; _r++ )); do
        local _row=$(( _top + _r ))
        printf '\033[%d;%dH%s' "$_row" "$_left" "$_vr" >&3
        printf '\033[%d;%dH%s' "$_row" "$(( _left + _width - 1 ))" "$_vr" >&3
    done

    # Bottom border
    _shellframe_panel_hline "$(( _top + _height - 1 ))" "$_left" "$_width" "$_bl" "$_hr" "$_br"
    printf '%s' "$_off" >&3

    # Leave cursor at last row, column left (component contract)
    printf '\033[%d;%dH' "$(( _top + _height - 1 ))" "$_left" >&3
}

# ── shellframe_panel_inner ─────────────────────────────────────────────────────

# Compute inner content region accounting for border (1 cell each side).
# Stores results via printf -v into the four named out_* variables.
#
# Usage:
#   local inner_top inner_left inner_w inner_h
#   shellframe_panel_inner "$top" "$left" "$width" "$height" \
#       inner_top inner_left inner_w inner_h
shellframe_panel_inner() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _out_top="$5" _out_left="$6" _out_width="$7" _out_height="$8"

    local _border=0
    [[ "${SHELLFRAME_PANEL_STYLE:-single}" != "none" ]] && _border=1

    local _title_row=0
    [[ "${SHELLFRAME_PANEL_MODE:-framed}" == "windowed" ]] && _title_row=1

    printf -v "$_out_top"    '%d' "$(( _top    + _border + _title_row ))"
    printf -v "$_out_left"   '%d' "$(( _left   + _border ))"
    printf -v "$_out_width"  '%d' "$(( _width  - _border * 2 ))"
    printf -v "$_out_height" '%d' "$(( _height - _border * 2 - _title_row ))"
}

# ── shellframe_panel_on_key ────────────────────────────────────────────────────

# Panels never consume keys themselves — always return 1 (not handled).
shellframe_panel_on_key() {
    return 1
}

# ── shellframe_panel_on_focus ──────────────────────────────────────────────────

shellframe_panel_on_focus() {
    SHELLFRAME_PANEL_FOCUSED="${1:-0}"
}

# ── shellframe_panel_size ──────────────────────────────────────────────────────

# min_width=2, min_height=2 (border only, no content).
# preferred = 0 (unconstrained — fills whatever region the layout assigns).
shellframe_panel_size() {
    printf '%d %d %d %d' 2 2 0 0
}
