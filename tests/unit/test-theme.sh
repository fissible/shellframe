#!/usr/bin/env bash
# tests/unit/test-theme.sh — theme loading and isolation (#53)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

ptyunit_test_begin "theme #53: default loads at source time"
assert_eq "default" "$SHELLFRAME_THEME"
assert_not_null "$SHELLFRAME_RESET"

ptyunit_test_begin "theme #53: mono strips all colors, keeps attributes"
shellframe_theme_load mono
assert_eq "mono" "$SHELLFRAME_THEME"
assert_null "$SHELLFRAME_GRAY"
assert_null "$SHELLFRAME_RED"
assert_not_null "$SHELLFRAME_BOLD"
assert_not_null "$SHELLFRAME_RESET"

ptyunit_test_begin "theme #53: default restores colors after mono"
shellframe_theme_load default
assert_eq "default" "$SHELLFRAME_THEME"
assert_not_null "$SHELLFRAME_GRAY"

ptyunit_test_begin "theme #53: custom file overrides specific constants"
_theme_f=$(mktemp)
printf 'SHELLFRAME_GRAY=%q\n' "$(printf '\033[38;5;240m')" > "$_theme_f"
shellframe_theme_load "$_theme_f"
assert_eq "240m" "${SHELLFRAME_GRAY##*38;5;}"
rm -f "$_theme_f"

ptyunit_test_begin "theme #53: unknown name fails without changing active theme"
shellframe_theme_load default
if shellframe_theme_load "no-such-theme" 2>/dev/null; then
    ptyunit_fail "unknown theme returned 0"
else
    assert_eq "default" "$SHELLFRAME_THEME"
fi

ptyunit_test_begin "theme #53: missing path fails cleanly"
if shellframe_theme_load "/nonexistent/theme.sh" 2>/dev/null; then
    ptyunit_fail "missing theme file returned 0"
else
    ptyunit_pass
fi

ptyunit_test_begin "theme #53: theme_list enumerates shipped themes"
assert_contains "$(shellframe_theme_list)" "mono"

ptyunit_test_summary

# ── review round: standalone source, degradation, broken files, mono render ──

ptyunit_test_begin "theme r3: draw.sh sources standalone under set -u"
out=$( bash -uc 'source "'"$SHELLFRAME_DIR"'/src/draw.sh"; printf "%s" "$SHELLFRAME_RESET"' )
assert_not_null "$out"

ptyunit_test_begin "theme r3: TERM=dumb degrades to empty colors, not raw SGR"
( export TERM=dumb
  source "$SHELLFRAME_DIR/src/draw.sh"
  _shellframe_theme_apply_default
  printf 'g=%d y=%d' "${#SHELLFRAME_GREEN}" "${#SHELLFRAME_YELLOW}" ) > /tmp/sf-dumb.txt
assert_eq "g=0 y=0" "$(cat /tmp/sf-dumb.txt)"

ptyunit_test_begin "theme r3: broken custom file -> rc 1, palette fully intact"
shellframe_theme_load default
_broken=$(mktemp)
printf 'SHELLFRAME_RED=%s\n' "$(printf '\\033[31m')" > "$_broken"
printf '\nthis is not valid bash ]]]\n' >> "$_broken"
if shellframe_theme_load "$_broken" 2>/dev/null; then
    ptyunit_fail "broken theme returned 0"
else
    ptyunit_pass
fi
assert_eq "default" "$SHELLFRAME_THEME"
assert_not_null "$SHELLFRAME_RED"
rm -f "$_broken"

ptyunit_test_begin "theme r3: mono suppresses widget dash-form fallbacks (rendered)"
shellframe_theme_load mono
v="${SHELLFRAME_RED-$'\033[31m'}"
assert_eq "0" "${#v}"

ptyunit_test_begin "theme r3: lint — no theme constant uses :- ANSI fallback in widgets"
_lint_hits=$(grep -rnE '\$\{SHELLFRAME_(GREEN|RED|YELLOW|PURPLE|GRAY|WHITE|BOLD|DIM|RESET|REVERSE):-' \
    "$SHELLFRAME_DIR/src/widgets/" | wc -l | tr -d ' ')
assert_eq "0" "$_lint_hits"

ptyunit_test_summary
