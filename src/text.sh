#!/usr/bin/env bash
# shellframe/src/text.sh — Text rendering primitive
#
# COMPATIBILITY: bash 3.2+ (macOS default).
# REQUIRES: src/clip.sh sourced first (shellframe_str_clip_ellipsis, shellframe_str_len).
#
# ── Overview ──────────────────────────────────────────────────────────────────
#
# Renders a single block of text into a terminal region.  Used by labels,
# titles, status lines, list items, and table cells.
#
# Set SHELLFRAME_TEXT_* globals before calling shellframe_text_render.
# The component is display-only (FOCUSABLE=0) and has no on_key handler.
#
# ── Input globals ──────────────────────────────────────────────────────────────
#
#   SHELLFRAME_TEXT_CONTENT   — plain text to display (may contain \n for multi-line)
#   SHELLFRAME_TEXT_RENDERED  — ANSI-styled version; empty → use CONTENT verbatim
#   SHELLFRAME_TEXT_ALIGN     — left (default) | center | right
#   SHELLFRAME_TEXT_WRAP      — 0 = clip+ellipsis (default) | 1 = word-wrap
#   SHELLFRAME_TEXT_FOCUSABLE — always 0; text is display-only
#
# ── Public API ─────────────────────────────────────────────────────────────────
#
#   shellframe_text_render top left width height
#     Render SHELLFRAME_TEXT_CONTENT within the given region.  All output goes
#     to /dev/tty.  Leaves cursor at (top+height-1, left) per component contract.
#
#   shellframe_text_size
#     Print "min_w min_h pref_w pref_h" for the current SHELLFRAME_TEXT_CONTENT.
#     pref_w = longest line; pref_h = number of lines.
#
# ── Internal helpers (testable without /dev/tty) ──────────────────────────────
#
#   _shellframe_text_align raw rendered width [align]
#     Render one line into a field of exactly $width visible columns:
#     clips with ellipsis if text exceeds width, pads with spaces to fill.
#     Outputs to stdout.
#
#   _shellframe_text_wrap_words raw width
#     Split $raw at word boundaries so each output line fits in $width columns.
#     Outputs lines to stdout, each terminated with \n.
#     Only operates on plain text; ANSI is not supported in wrap mode.

SHELLFRAME_TEXT_CONTENT=""
SHELLFRAME_TEXT_RENDERED=""
SHELLFRAME_TEXT_ALIGN="left"
SHELLFRAME_TEXT_WRAP=0
SHELLFRAME_TEXT_FOCUSABLE=0

# ── _shellframe_text_align ─────────────────────────────────────────────────────

_shellframe_text_align() {
    local _raw="$1" _rendered="$2" _width="$3" _align="${4:-left}"
    local _vis="${#_raw}" _out _out_vis

    if (( _vis > _width )); then
        shellframe_str_clip_ellipsis "$_raw" "$_rendered" "$_width" _out
        _out_vis="$_width"
    else
        _out="$_rendered"
        _out_vis="$_vis"
    fi

    local _pad=$(( _width - _out_vis )) _lp=0 _rp=0
    case "$_align" in
        right)  _lp="$_pad" ;;
        center) _lp=$(( _pad / 2 )); _rp=$(( _pad - _lp )) ;;
        *)      _rp="$_pad" ;;   # left (default)
    esac

    (( _lp > 0 )) && printf '%*s' "$_lp" ''
    printf '%s' "$_out"
    (( _rp > 0 )) && printf '%*s' "$_rp" ''
}

# ── _shellframe_text_wrap_words ────────────────────────────────────────────────

# Split $raw into lines of at most $width columns, breaking at spaces.
# Words longer than $width are hard-broken at the width boundary.
# Each output line is terminated with \n.  Plain text only (no ANSI support).
_shellframe_text_wrap_words() {
    local _raw="$1" _width="$2"
    local _line="" _word="" _i _c

    for (( _i=0; _i<=${#_raw}; _i++ )); do
        _c="${_raw:$_i:1}"
        if [[ "$_c" == ' ' || $_i -eq ${#_raw} ]]; then
            if [[ -n "$_word" ]]; then
                if [[ -z "$_line" ]]; then
                    _line="$_word"
                elif (( ${#_line} + 1 + ${#_word} <= _width )); then
                    _line+=" $_word"
                else
                    printf '%s\n' "$_line"
                    _line="$_word"
                fi
                _word=""
            fi
        else
            _word+="$_c"
            # Hard-break a word that exactly fills the width
            if (( ${#_word} == _width )); then
                if [[ -z "$_line" ]]; then
                    printf '%s\n' "$_word"
                else
                    printf '%s\n' "$_line"
                    printf '%s\n' "$_word"
                    _line=""
                fi
                _word=""
            fi
        fi
    done
    [[ -n "$_line" ]] && printf '%s\n' "$_line"
}

# ── shellframe_text_render ─────────────────────────────────────────────────────

shellframe_text_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _content="${SHELLFRAME_TEXT_CONTENT:-}"
    local _rendered="${SHELLFRAME_TEXT_RENDERED:-}"
    local _align="${SHELLFRAME_TEXT_ALIGN:-left}"
    local _wrap="${SHELLFRAME_TEXT_WRAP:-0}"

    [[ -z "$_rendered" ]] && _rendered="$_content"

    # ── Build line arrays ──────────────────────────────────────────────────────
    # Bash 3.2-safe split: use parameter expansion to split on literal \n.
    # In wrap mode, word-wrap each paragraph using process substitution.
    local -a _raw_lines _ren_lines
    local _raw_rest="$_content" _ren_rest="$_rendered" _i=0

    if (( _wrap )); then
        # Word-wrap mode: split on \n into paragraphs, then word-wrap each.
        # RENDERED is ignored in wrap mode (word boundaries in ANSI are ambiguous).
        while true; do
            local _para
            if [[ "$_raw_rest" == *$'\n'* ]]; then
                _para="${_raw_rest%%$'\n'*}"
                _raw_rest="${_raw_rest#*$'\n'}"
            else
                _para="$_raw_rest"
                _raw_rest=""
            fi
            local _wl
            while IFS= read -r _wl; do
                _raw_lines[$_i]="$_wl"
                _ren_lines[$_i]="$_wl"
                (( _i++ ))
            done < <(_shellframe_text_wrap_words "$_para" "$_width")
            [[ -z "$_raw_rest" ]] && break
        done
    else
        # No-wrap mode: split on \n, each line clipped independently.
        while true; do
            local _raw_line _ren_line
            if [[ "$_raw_rest" == *$'\n'* ]]; then
                _raw_line="${_raw_rest%%$'\n'*}"
                _raw_rest="${_raw_rest#*$'\n'}"
                _ren_line="${_ren_rest%%$'\n'*}"
                _ren_rest="${_ren_rest#*$'\n'}"
            else
                _raw_line="$_raw_rest"
                _ren_line="$_ren_rest"
                _raw_rest=""
            fi
            _raw_lines[$_i]="$_raw_line"
            _ren_lines[$_i]="$_ren_line"
            (( _i++ ))
            [[ -z "$_raw_rest" ]] && break
        done
    fi

    # ── Render each row ────────────────────────────────────────────────────────
    local _r
    for (( _r=0; _r<_height; _r++ )); do
        local _row=$(( _top + _r ))
        local _row_raw="${_raw_lines[$_r]:-}"
        local _row_ren="${_ren_lines[$_r]:-}"
        local _line
        _line=$(_shellframe_text_align "$_row_raw" "$_row_ren" "$_width" "$_align")
        shellframe_fb_print_ansi "$_row" "$_left" "$_line"
    done
}

# ── shellframe_text_size ───────────────────────────────────────────────────────

# Print "min_width min_height preferred_width preferred_height" for the current
# SHELLFRAME_TEXT_CONTENT.  preferred_width = longest line, preferred_height = line count.
shellframe_text_size() {
    local _content="${SHELLFRAME_TEXT_CONTENT:-}"
    local _max_w=0 _lines=1 _line_w=0 _i _c
    for (( _i=0; _i<${#_content}; _i++ )); do
        _c="${_content:$_i:1}"
        if [[ "$_c" == $'\n' ]]; then
            (( _line_w > _max_w )) && _max_w="$_line_w"
            _line_w=0
            (( _lines++ ))
        else
            (( _line_w++ ))
        fi
    done
    (( _line_w > _max_w )) && _max_w="$_line_w"
    printf '%d %d %d %d' 0 1 "$_max_w" "$_lines"
}
