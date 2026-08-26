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

# Apply the default theme via per-capability tput queries.
#
# Note (review round 2 verification): a batched `tput -S` call does NOT work
# here — tput emits capability results consecutively with no separators, so
# there is no reliable way to split them back apart, and a line-count guard
# simply routes every load through the fallback. Ten forks cost ~10 ms of
# one-time load; correctness and honest comments beat that win.
_shellframe_theme_apply_default() {
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
