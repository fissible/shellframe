#!/usr/bin/env bash
# shellframe/src/clip.sh — String measurement and clipping utilities
#
# COMPATIBILITY: bash 3.2+ (macOS default).
#
# ── Convention: raw + rendered ─────────────────────────────────────────────────
#
# Every function accepts two representations of the same string:
#
#   raw      — plain-text (no ANSI codes). Its byte length equals its visible
#              character count, so ${#raw} gives the correct visible width
#              without any ANSI stripping.
#
#   rendered — the same content with ANSI escape codes (colors, bold, etc.)
#              interspersed. Longer in bytes; identical in visible width.
#
# This convention avoids ANSI stripping entirely, which sidesteps a class of
# locale-dependent regex portability bugs in bash 3.2.
#
# ── Public functions ───────────────────────────────────────────────────────────
#
#   shellframe_str_len       raw
#     → prints visible character count
#
#   shellframe_str_clip      raw rendered width
#     → prints rendered hard-clipped to at most `width` visible chars
#
#   shellframe_str_clip_ellipsis  raw rendered width
#     → prints rendered clipped to `width` visible chars, last char replaced
#       by '…' if truncation occurred
#
#   shellframe_str_pad       raw rendered width
#     → prints rendered left-aligned in a field of `width` visible chars
#       (space-padded on the right). Replacement for shellframe_pad_left.
#
# ── ANSI detection ─────────────────────────────────────────────────────────────
#
# The internal clip walker recognises CSI sequences (ESC [) and treats the
# following bytes as non-visible until a terminator is seen. The terminator
# set covers every sequence shellframe itself emits: SGR (m), cursor movement
# (A B C D H f), erase (J K), and mode switches (h l). Bytes in the ESC
# sequence body do not count toward visible width.
#
# ── Limitations ────────────────────────────────────────────────────────────────
# Multi-byte Unicode (emoji, CJK wide chars) is not handled. ${#raw} counts
# bytes in bash 3.2 under a single-byte locale; callers are responsible for
# ensuring one visible column == one byte in `raw`.

# ── shellframe_str_len ─────────────────────────────────────────────────────────

# Print the visible character count of $raw.
# Named function documents the raw+rendered convention at call sites.
#
# Usage: shellframe_str_len "$raw"
shellframe_str_len() {
    printf '%d' "${#1}"
}

# ── Internal clip walker ───────────────────────────────────────────────────────

# Walk $rendered byte-by-byte, keeping at most $limit visible characters.
# Appends '\033[0m' (SGR reset) only if actual truncation occurred (i.e. some
# bytes from $rendered were left unread), to prevent color bleed.
# Prints result to stdout; intended for capture with $(...).
_shellframe_clip_walk() {
    local _rendered="$1" _limit="$2"
    local _n="${#_rendered}" _i=0 _vis=0 _c _in_esc=0 _had_esc=0 _out=""
    while (( _i < _n && _vis < _limit )); do
        _c="${_rendered:$_i:1}"
        _out+="$_c"
        if (( _in_esc )); then
            # End of CSI sequence: any letter or common single-char terminator.
            # Covers all sequences emitted by shellframe (SGR, cursor, erase).
            case "$_c" in
                m|A|B|C|D|H|J|K|f|h|l|r|s|u) _in_esc=0 ;;
            esac
        elif [[ "$_c" == $'\x1b' ]]; then
            _in_esc=1
            _had_esc=1
        else
            (( _vis++ )) || true
        fi
        (( _i++ )) || true
    done
    # Append SGR reset only when truncation occurred AND there were ANSI sequences
    # in the consumed portion. Plain-text strings get a clean substring with no
    # extra bytes; ANSI strings get the reset to prevent color bleed.
    if (( _i < _n && _had_esc )); then
        printf '%s\033[0m' "$_out"
    else
        printf '%s' "$_out"
    fi
}

# ── shellframe_str_clip ────────────────────────────────────────────────────────

# Hard-clip $rendered to at most $width visible characters.
# If the visible length of $raw is already ≤ $width, $rendered is printed
# unchanged (fast path — no byte-walking).
# If $width ≤ 0, prints nothing.
#
# Usage:
#   local clipped
#   clipped=$(shellframe_str_clip "$raw" "$rendered" "$col_width")
#   printf '%s' "$clipped"
shellframe_str_clip() {
    local _raw="$1" _rendered="$2" _width="$3"
    if (( _width <= 0 )); then
        return
    fi
    if (( ${#_raw} <= _width )); then
        printf '%s' "$_rendered"
    else
        _shellframe_clip_walk "$_rendered" "$_width"
    fi
}

# ── shellframe_str_clip_ellipsis ───────────────────────────────────────────────

# Clip $rendered to $width visible characters, replacing the last character
# with '…' when truncation occurs.
# If the visible length of $raw is already ≤ $width, $rendered is printed
# unchanged. If $width ≤ 0, prints nothing. If $width == 1, prints just '…'.
#
# Usage:
#   local clipped
#   clipped=$(shellframe_str_clip_ellipsis "$raw" "$rendered" "$col_width")
#   printf '%s' "$clipped"
shellframe_str_clip_ellipsis() {
    local _raw="$1" _rendered="$2" _width="$3"
    if (( _width <= 0 )); then
        return
    fi
    if (( ${#_raw} <= _width )); then
        printf '%s' "$_rendered"
        return
    fi
    if (( _width == 1 )); then
        printf '…'
        return
    fi
    # Clip to (width - 1) visible chars to make room for the ellipsis.
    _shellframe_clip_walk "$_rendered" "$(( _width - 1 ))"
    printf '…'
}

# ── shellframe_str_pad ─────────────────────────────────────────────────────────

# Left-align $rendered in a field of $width visible characters, padding with
# spaces on the right. Replacement for shellframe_pad_left with consistent
# naming. Does not truncate — if visible length > width, $rendered is
# printed as-is (no clipping). Combine with shellframe_str_clip first if
# truncation before padding is desired.
#
# $raw must be the plain-text version of $rendered (same visible content,
# no ANSI codes) so that ${#raw} == visible width.
#
# Usage:
#   printf '%s' "$(shellframe_str_pad "$raw" "$rendered" 20)"
shellframe_str_pad() {
    local _raw="$1" _rendered="$2" _width="$3"
    local _pad=$(( _width - ${#_raw} ))
    (( _pad < 0 )) && _pad=0
    printf '%s%*s' "$_rendered" "$_pad" ''
}
