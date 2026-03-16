#!/usr/bin/env bash
# tests/unit/test-panel.sh — Unit tests for src/panel.sh
# (Rendering tests require PTY; these cover inner-bounds and focus state only.)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/panel.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── shellframe_panel_inner: single border style ───────────────────────────────

_inner() {
    local t l w h
    SHELLFRAME_PANEL_STYLE="single"
    shellframe_panel_inner "$1" "$2" "$3" "$4" t l w h
    printf '%d %d %d %d' "$t" "$l" "$w" "$h"
}

ptyunit_test_begin "panel_inner: single — top offset by 1"
result=$(_inner 1 1 20 10)
it=$(printf '%s' "$result" | awk '{print $1}')
assert_eq "2" "$it" "inner top = outer top + 1"

ptyunit_test_begin "panel_inner: single — left offset by 1"
result=$(_inner 1 1 20 10)
il=$(printf '%s' "$result" | awk '{print $2}')
assert_eq "2" "$il" "inner left = outer left + 1"

ptyunit_test_begin "panel_inner: single — width reduced by 2"
result=$(_inner 1 1 20 10)
iw=$(printf '%s' "$result" | awk '{print $3}')
assert_eq "18" "$iw" "inner width = outer width - 2"

ptyunit_test_begin "panel_inner: single — height reduced by 2"
result=$(_inner 1 1 20 10)
ih=$(printf '%s' "$result" | awk '{print $4}')
assert_eq "8" "$ih" "inner height = outer height - 2"

# ── shellframe_panel_inner: none border style ─────────────────────────────────

ptyunit_test_begin "panel_inner: none — inner equals outer"
SHELLFRAME_PANEL_STYLE="none"
_it="" _il="" _iw="" _ih=""
shellframe_panel_inner 3 5 20 10 _it _il _iw _ih
assert_eq "3"  "$_it" "none: top unchanged"
assert_eq "5"  "$_il" "none: left unchanged"
assert_eq "20" "$_iw" "none: width unchanged"
assert_eq "10" "$_ih" "none: height unchanged"

# ── shellframe_panel_inner: non-origin region ─────────────────────────────────

ptyunit_test_begin "panel_inner: non-origin region with single border"
SHELLFRAME_PANEL_STYLE="single"
_ot="" _ol="" _ow="" _oh=""
shellframe_panel_inner 5 10 30 15 _ot _ol _ow _oh
assert_eq "6"  "$_ot" "top = 5+1"
assert_eq "11" "$_ol" "left = 10+1"
assert_eq "28" "$_ow" "width = 30-2"
assert_eq "13" "$_oh" "height = 15-2"

# ── shellframe_panel_on_focus ─────────────────────────────────────────────────

ptyunit_test_begin "panel_on_focus: sets FOCUSED=1"
SHELLFRAME_PANEL_FOCUSED=0
shellframe_panel_on_focus 1
assert_eq "1" "$SHELLFRAME_PANEL_FOCUSED" "focused set to 1"

ptyunit_test_begin "panel_on_focus: sets FOCUSED=0"
SHELLFRAME_PANEL_FOCUSED=1
shellframe_panel_on_focus 0
assert_eq "0" "$SHELLFRAME_PANEL_FOCUSED" "focused set to 0"

# ── shellframe_panel_on_key ───────────────────────────────────────────────────

ptyunit_test_begin "panel_on_key: always returns 1 (not handled)"
shellframe_panel_on_key "x"
assert_eq "1" "$?" "on_key returns 1"

# ── shellframe_panel_size ─────────────────────────────────────────────────────

ptyunit_test_begin "panel_size: min 2x2, preferred unconstrained"
assert_output "2 2 0 0" shellframe_panel_size

ptyunit_test_summary
