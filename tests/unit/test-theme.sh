#!/usr/bin/env bash
# tests/unit/test-theme.sh — theme loading and isolation (#53)
#
# Environment honesty: on hosts without usable terminfo (containers with no
# TERM, dumb terminals) the DEFAULT theme legitimately produces EMPTY color
# constants — that is the documented degradation contract. Tests therefore
# distinguish "declared" from "non-empty", and use custom full-palette files
# when exact values must be asserted deterministically.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

_all_declared() {
    local _v
    for _v in GREEN RED YELLOW PURPLE GRAY WHITE BOLD DIM RESET REVERSE; do
        [[ -n "${+_SHELLFRAME_$_v}" ]] || return 1
    done
}

ptyunit_test_begin "theme #53: default loads at source time — all constants declared"
assert_true _all_declared
assert_eq "default" "$SHELLFRAME_THEME"

ptyunit_test_begin "theme #53: mono strips ALL colors on any platform"
shellframe_theme_load mono
for _c in GREEN RED YELLOW PURPLE GRAY WHITE; do
    eval "[[ -z \${SHELLFRAME_$_c} ]]" || { ptyunit_fail "$_c is non-empty under mono"; break; }
done

ptyunit_test_begin "theme #53: default restores after mono (all declared, name tracked)"
shellframe_theme_load default
assert_eq "default" "$SHELLFRAME_THEME"
assert_true _all_declared

ptyunit_test_begin "theme #53: custom full-palette file round-trips exactly"
_tf=$(mktemp)
{
    printf 'SHELLFRAME_GREEN=%q\n'  $'\033[32m'
    printf 'SHELLFRAME_RED=%q\n'    $'\033[31m'
    printf 'SHELLFRAME_GRAY=%q\n'   $'\033[90m'
} > "$_tf"
shellframe_theme_load "$_tf"
assert_eq $'\033[32m' "$SHELLFRAME_GREEN"
assert_eq $'\033[90m' "$SHELLFRAME_GRAY"
rm -f "$_tf"
shellframe_theme_load default

ptyunit_test_begin "theme #53: overlay semantics — partial file keeps other constants"
_prev_gray="$SHELLFRAME_GRAY"
_pf=$(mktemp)
printf 'SHELLFRAME_RED=%q\n' $'\033[31m' > "$_pf"
shellframe_theme_load "$_pf"
assert_eq "$_prev_gray" "$SHELLFRAME_GRAY"
rm -f "$_pf"
shellframe_theme_load default

ptyunit_test_begin "theme r3: draw.sh sources standalone under set -u"
out=$( bash -uc 'source "'"$SHELLFRAME_DIR"'/src/draw.sh"; printf "%s%b" "${SHELLFRAME_RESET+D}" "${SHELLFRAME_THEME:-}"' )
assert_contains "$out" "D"
assert_contains "$out" "default"

ptyunit_test_begin "theme r3: broken custom file -> rc 1, palette fully intact"
shellframe_theme_load default
_before=$(printf '%s|%s' "$SHELLFRAME_RED" "$SHELLFRAME_GRAY")
_broken=$(mktemp)
printf 'SHELLFRAME_RED=%s\n' "$(printf '\033[31m')" > "$_broken"
printf '\nthis is not valid bash ]]]\n' >> "$_broken"
if shellframe_theme_load "$_broken" 2>/dev/null; then
    ptyunit_fail "broken theme returned 0"
else
    ptyunit_pass
fi
_after=$(printf '%s|%s' "$SHELLFRAME_RED" "$SHELLFRAME_GRAY")
assert_eq "$_before" "$_after"
rm -f "$_broken"

ptyunit_test_begin "theme r3: mono suppresses widget dash-form fallbacks (rendered)"
shellframe_theme_load mono
v="${SHELLFRAME_RED-$'\033[31m'}"
assert_eq "0" "${#v}"

ptyunit_test_begin "theme r3: lint — no theme constant uses :- ANSI fallback in widgets"
_lint_hits=$(grep -rnE '\$\{SHELLFRAME_(GREEN|RED|YELLOW|PURPLE|GRAY|WHITE|BOLD|DIM|RESET|REVERSE):-' \
    "$SHELLFRAME_DIR/src/widgets/" | wc -l | tr -d ' ')
assert_eq "0" "$_lint_hits"

ptyunit_test_begin "theme r3: TERM=dumb degrades to empty colors, not raw SGR"
( export TERM=dumb
  source "$SHELLFRAME_DIR/src/draw.sh"
  _shellframe_theme_apply_default
  printf 'g=%d y=%d' "${#SHELLFRAME_GREEN}" "${#SHELLFRAME_YELLOW}" ) > /tmp/sf-dumb.txt
assert_eq "g=0 y=0" "$(cat /tmp/sf-dumb.txt)"

ptyunit_test_summary
