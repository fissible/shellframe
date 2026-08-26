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
# time, so loading a theme is just reassigning them. Shipped themes live in
# src/themes/; custom themes are any file that assigns those globals.
# All render sites use %s with these values (see #42), so real-byte ANSI in
# theme files and literal text in consumer data cannot cross-contaminate.

_SF_THEMES_DIR="$SHELLFRAME_DIR/src/themes"
SHELLFRAME_THEME="default"
source "$_SF_THEMES_DIR/default.sh"

# List shipped themes (one per line). Custom themes live outside the library
# and are not enumerated.
shellframe_theme_list() {
    printf 'default\nmono\n'
}

# Load a built-in theme by name or a custom theme by file path.
# On failure the previously loaded theme remains active (fail-open-free:
# nothing changes unless the new theme sources successfully).
shellframe_theme_load() {
    local _name="${1:-default}"
    case "$_name" in
        default|mono)
            source "$_SF_THEMES_DIR/$_name.sh" ;;
        */*)
            [[ -f "$_name" ]] || {
                printf 'shellframe: theme file not found: %s\n' "$_name" >&2
                return 1
            }
            source "$_name" ;;
        *)
            printf 'shellframe: unknown theme: %s (shipped: default, mono)\n' "$_name" >&2
            return 1 ;;
    esac
    SHELLFRAME_THEME="$_name"
}
