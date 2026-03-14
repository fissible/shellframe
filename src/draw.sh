#!/usr/bin/env bash
# clui/src/draw.sh — ANSI-aware rendering utilities

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
#   printf '%b' "$(clui_pad_left "$raw" "$rendered" 20)"
clui_pad_left() {
    local raw="$1" rendered="$2" width="$3"
    local pad=$(( width - ${#raw} ))
    (( pad < 0 )) && pad=0
    printf '%b%*s' "$rendered" "$pad" ''
}

# ── Color constants ───────────────────────────────────────────────────────────

CLUI_BOLD=$(tput bold   2>/dev/null || true)
CLUI_RESET=$(tput sgr0  2>/dev/null || true)
CLUI_GREEN=$(tput setaf 2 2>/dev/null || true)
CLUI_RED=$(tput setaf 1   2>/dev/null || true)
CLUI_PURPLE=$(tput setaf 5 2>/dev/null || true)
CLUI_GRAY=$(tput setaf 8 2>/dev/null || tput setaf 7 2>/dev/null || true)
CLUI_WHITE=$(tput setaf 7 2>/dev/null || true)
