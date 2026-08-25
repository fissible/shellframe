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
    local _rendered="$1" _limit="$2" _out_var="${3:-}"
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
        _out+=$'\033[0m'
    fi
    if [[ -n "$_out_var" ]]; then
        printf -v "$_out_var" '%s' "$_out"
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
    local _raw="$1" _rendered="$2" _width="$3" _out_var="${4:-}"
    local _result=""
    if (( _width <= 0 )); then
        _result=""
    elif (( ${#_raw} <= _width )); then
        _result="$_rendered"
    else
        _shellframe_clip_walk "$_rendered" "$_width" _result
    fi
    if [[ -n "$_out_var" ]]; then
        printf -v "$_out_var" '%s' "$_result"
    else
        printf '%s' "$_result"
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
    local _raw="$1" _rendered="$2" _width="$3" _out_var="${4:-}"
    local _result=""
    if (( _width <= 0 )); then
        _result=""
    elif (( ${#_raw} <= _width )); then
        _result="$_rendered"
    elif (( _width == 1 )); then
        _result="…"
    else
        # Clip to (width - 1) visible chars to make room for the ellipsis.
        _shellframe_clip_walk "$_rendered" "$(( _width - 1 ))" _result
        _result+="…"
    fi
    if [[ -n "$_out_var" ]]; then
        printf -v "$_out_var" '%s' "$_result"
    else
        printf '%s' "$_result"
    fi
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

# ── shellframe_sanitize ────────────────────────────────────────────────────────

# Strip ANSI escape sequences and C0 control characters from untrusted text,
# keeping only printable characters plus \n and \t. Handles complete CSI
# sequences, string sequences (OSC/DCS/SOS/PM/APC — terminated by BEL or ST),
# two-byte Fe sequences, and a trailing truncated escape. Also drops DEL.
#
# Intended for content that did not originate from the application (pasted
# text, file names) before it enters an editor buffer or the render path (#45).
# Literal characters are never interpreted: a backslash-n stays two chars.
#
# Collation note (review 2026-08-25): the CSI final-byte class [@-~] relies
# on byte-ordered range matching. Under bash 3.2 with a UTF-8 locale,
# bracket ranges follow collation order and letters fall outside [@-~] —
# so a CSI would never terminate and everything after the first escape was
# dropped. LC_COLLATE=C is pinned for the whole function.
#
# Usage:
#   sanitized=$(shellframe_sanitize "$raw")        # prints result
#   shellframe_sanitize "$raw" out_var             # or sets out_var
shellframe_sanitize() {
    local _raw="$1" _out_var="${2:-}"
    local LC_COLLATE=C

    # Fast path (#45 review): nothing to strip when there is no ESC and no
    # control character besides \n and \t — which are kept verbatim anyway.
    # Two O(n) pattern scans in C beat the per-character bash loop by orders
    # of magnitude on typical (clean) pastes.
    local _probe="${_raw//$'\n'/}"
    _probe="${_probe//$'\t'/}"
    if [[ "$_probe" != *$'\x1b'* && "$_probe" != *[[:cntrl:]]* ]]; then
        if [[ -n "$_out_var" ]]; then
            printf -v "$_out_var" '%s' "$_raw"
        else
            printf '%s' "$_raw"
        fi
        return 0
    fi

    local _n="${#_raw}" _i=0 _c="" _state=0 _out=""
    # Bracket class of C0 controls + DEL, built via printf because $'..'
    # escapes do not expand inside case-pattern bracket expressions.
    local _c0_class="[$(printf '\001-\037\177')]"
    # _state 0 = plain text, 1 = got ESC, 2 = CSI body, 3 = string seq body,
    # 4 = string seq saw ESC (expecting the '\' of ST)
    while (( _i < _n )); do
        _c="${_raw:$_i:1}"
        case "$_state" in
            0)
                case "$_c" in
                    $'\x1b')                       _state=1 ;;
                    $'\n'|$'\t')                   _out+="$_c" ;;
                    $_c0_class)                    ;;   # other C0 + DEL: drop
                    *)                             _out+="$_c" ;;
                esac ;;
            1)
                case "$_c" in
                    '[')                        _state=2 ;;
                    ']'|'P'|'X'|'^'|'_')        _state=3 ;;
                    *)                          _state=0 ;;   # Fe: consumed
                esac ;;
            2)
                [[ "$_c" == [@-~] ]] && _state=0 ;;
            3)
                if [[ "$_c" == $'\x07' ]]; then
                    _state=0                                  # BEL terminator
                elif [[ "$_c" == $'\x1b' ]]; then
                    _state=4                                  # ESC of ST
                fi ;;
            4) _state=0 ;;                                    # '\' of ST
        esac
        (( _i++ ))
    done
    if [[ -n "$_out_var" ]]; then
        printf -v "$_out_var" '%s' "$_out"
    else
        printf '%s' "$_out"
    fi
}
