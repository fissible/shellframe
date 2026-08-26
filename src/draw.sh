#!/usr/bin/env bash
# shellframe/src/draw.sh — ANSI-aware rendering utilities

# ── Column padding ────────────────────────────────────────────────────────────
#
# GOTCHA: printf field-width specifiers (%-20s, %*s) count raw bytes, not
# visible characters. ANSI escape codes add bytes without adding visual width,
# so colored strings appear shorter to printf and get under-padded. The
# solution is to pass both the raw (plain) version of the string for width
# measurement and the rendered (ANSI-colored) version for output.

# Left-align $rendered in a column of $width visible characters.
# $raw must be the plain-text version of $rendered (same visible content,
# no escape codes) so its byte length equals its visible character count.
#
# Usage:
#   local raw="~/bin/gflow"
#   local rendered="${GRAY}~/bin/${RESET}${BOLD}gflow${RESET}"
#   printf '%s' "$(shellframe_pad_left "$raw" "$rendered" 20)"
shellframe_pad_left() {
    local raw="$1" rendered="$2" width="$3"
    local pad=$(( width - ${#raw} ))
    (( pad < 0 )) && pad=0
    printf '%s%*s' "$rendered" "$pad" ''
}

# ── Color constants & theming (#53) ──────────────────────────────────────────
#
# The SHELLFRAME_* presentation globals are plain variables read at render
# time, so a theme is just reassignment. This file must source STANDALONE
# (the LEGO rule): it resolves its own directory rather than relying on
# shellframe.sh's SHELLFRAME_DIR, which does not exist in that path.
_SF_DRAW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SHELLFRAME_THEME="default"

# Degradation contract: when terminfo cannot supply a capability the
# constant becomes EMPTY — plain text, never raw SGR bytes (TERM=dumb,
# cron, CI). Custom themes may choose otherwise; shipped themes do not.

# Apply the default theme: ONE tput -S fork for all ten capabilities
# (~9x cheaper than ten forks; this dominated library load time on 3.2).
# The batch is validated by LINE COUNT — tools like busybox date exit 0
# while silently degrading output, so anything short of exactly 10 lines
# falls back to per-capability queries, which degrade to empty strings.
_shellframe_theme_apply_default() {
    local _caps _line
    local -a _v=()
    if _caps=$(printf 'bold\ndim\nsgr0\nrev\nsetaf 2\nsetaf 1\nsetaf 3\nsetaf 5\nsetaf 8\nsetaf 7\n' | tput -S 2>/dev/null) \
       && [[ $(grep -c '' <<< "$_caps") -eq 10 ]]; then
        while IFS= read -r _line; do _v+=("$_line"); done <<< "$_caps"
        SHELLFRAME_BOLD="${_v[0]}"
        SHELLFRAME_DIM="${_v[1]}"
        SHELLFRAME_RESET="${_v[2]}"
        SHELLFRAME_REVERSE="${_v[3]}"
        SHELLFRAME_GREEN="${_v[4]}"
        SHELLFRAME_RED="${_v[5]}"
        SHELLFRAME_YELLOW="${_v[6]}"
        SHELLFRAME_PURPLE="${_v[7]}"
        SHELLFRAME_GRAY="${_v[8]}"
        SHELLFRAME_WHITE="${_v[9]}"
        return 0
    fi
    # Per-capability fallback for mixed-support terminals: empty on failure.
    SHELLFRAME_BOLD=$(tput bold     2>/dev/null || true)
    SHELLFRAME_DIM=$(tput dim       2>/dev/null || true)
    SHELLFRAME_RESET=$(tput sgr0    2>/dev/null || true)
    SHELLFRAME_REVERSE=$(tput rev   2>/dev/null || true)
    SHELLFRAME_GREEN=$(tput setaf 2 2>/dev/null || true)
    SHELLFRAME_RED=$(tput setaf 1   2>/dev/null || true)
    SHELLFRAME_YELLOW=$(tput setaf 3 2>/dev/null || true)
    SHELLFRAME_PURPLE=$(tput setaf 5 2>/dev/null || true)
    SHELLFRAME_GRAY=$(tput setaf 8 2>/dev/null || true)
    SHELLFRAME_WHITE=$(tput setaf 7 2>/dev/null || true)
}

# Apply the mono theme: attributes survive, every color is deliberately
# EMPTY. Widget sites read these with ${VAR-fallback} (dash form), so an
# empty value suppresses color instead of triggering hardcoded ANSI.
_shellframe_theme_apply_mono() {
    SHELLFRAME_BOLD=$(tput bold  2>/dev/null || true)
    SHELLFRAME_DIM=$(tput dim    2>/dev/null || true)
    SHELLFRAME_RESET=$(tput sgr0 2>/dev/null || true)
    SHELLFRAME_REVERSE=$(tput rev 2>/dev/null || true)
    SHELLFRAME_GREEN=""
    SHELLFRAME_RED=""
    SHELLFRAME_YELLOW=""
    SHELLFRAME_PURPLE=""
    SHELLFRAME_GRAY=""
    SHELLFRAME_WHITE=""
}

# Snapshot/restore so a failed custom-theme source cannot leave a
# half-applied palette (review round: source status was ignored).
# Apply defaults at source time so the library is fully colored on load.
_shellframe_theme_apply_default

_shellframe_palette_save() {
    _SF_PB="$SHELLFRAME_BOLD";   _SF_PD="$SHELLFRAME_DIM"
    _SF_PR="$SHELLFRAME_RESET";  _SF_PV="$SHELLFRAME_REVERSE"
    _SF_PG="$SHELLFRAME_GREEN";  _SF_PRD="$SHELLFRAME_RED"
    _SF_PY="$SHELLFRAME_YELLOW"; _SF_PP="$SHELLFRAME_PURPLE"
    _SF_PGY="$SHELLFRAME_GRAY";  _SF_PW="$SHELLFRAME_WHITE"
}
_shellframe_palette_restore() {
    SHELLFRAME_BOLD="$_SF_PB";   SHELLFRAME_DIM="$_SF_PD"
    SHELLFRAME_RESET="$_SF_PR";  SHELLFRAME_REVERSE="$_SF_PV"
    SHELLFRAME_GREEN="$_SF_PG";  SHELLFRAME_RED="$_SF_PRD"
    SHELLFRAME_YELLOW="$_SF_PY"; SHELLFRAME_PURPLE="$_SF_PP"
    SHELLFRAME_GRAY="$_SF_PGY";  SHELLFRAME_WHITE="$_SF_PW"
}

# List shipped themes (one per line). Custom themes live outside the library
# and are not enumerated.
shellframe_theme_list() {
    printf 'default\nmono\n'
}

# Load a built-in theme by name or a custom theme by file path.
#
# Path rule: custom themes must contain a "/" (absolute or ./relative) —
# bare names are reserved for shipped themes.
#
# Overlay semantics: a custom theme file may assign any SUBSET of the
# constants; unassigned constants keep their current values. Source the
# default first if a full reset is wanted.
#
# Failure semantics: a missing file or a file that fails to source leaves
# the previously loaded palette fully intact (snapshot + restore).
shellframe_theme_load() {
    local _name="${1:-default}"

    case "$_name" in
        default|mono|*/*) ;;
        *)
            printf 'shellframe: unknown theme: %s (shipped: default, mono; custom paths must contain "/")\n' "$_name" >&2
            return 1 ;;
    esac
    if [[ "$_name" == */* && ! -f "$_name" ]]; then
        printf 'shellframe: theme file not found: %s\n' "$_name" >&2
        return 1
    fi

    _shellframe_palette_save

    case "$_name" in
        default) _shellframe_theme_apply_default ;;
        mono)    _shellframe_theme_apply_mono ;;
        *)       source "$_name" || { _shellframe_palette_restore
                                  printf 'shellframe: theme failed to load, previous palette restored: %s\n' "$_name" >&2
                                  return 1
                              } ;;
    esac
    SHELLFRAME_THEME="$_name"
}
