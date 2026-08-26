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
