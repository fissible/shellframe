#!/usr/bin/env bash
# tests/unit/test-confirm.sh — Unit tests for _shellframe_confirm_on_key

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

_reset_confirm() {
    SHELLFRAME_CONFIRM_SELECTED=0
    SHELLFRAME_CONFIRM_RESULT=-1
}

# ── Left / Right toggle ──────────────────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: Right arrow selects No"
_reset_confirm
_shellframe_confirm_on_key "$SHELLFRAME_KEY_RIGHT"
assert_eq "0" "$?" "returns 0 (redraw)"
assert_eq "1" "$SHELLFRAME_CONFIRM_SELECTED" "No selected"

ptyunit_test_begin "confirm_on_key: Left arrow selects Yes"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=1
_shellframe_confirm_on_key "$SHELLFRAME_KEY_LEFT"
assert_eq "0" "$?" "returns 0 (redraw)"
assert_eq "0" "$SHELLFRAME_CONFIRM_SELECTED" "Yes selected"

ptyunit_test_begin "confirm_on_key: h selects Yes"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=1
_shellframe_confirm_on_key "h"
assert_eq "0" "$SHELLFRAME_CONFIRM_SELECTED" "h → Yes"

ptyunit_test_begin "confirm_on_key: l selects No"
_reset_confirm
_shellframe_confirm_on_key "l"
assert_eq "1" "$SHELLFRAME_CONFIRM_SELECTED" "l → No"

# ── Quick-select keys ────────────────────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: y → RESULT=0, returns 2"
_reset_confirm
_shellframe_confirm_on_key "y"
assert_eq "2" "$?" "y returns 2 (done)"
assert_eq "0" "$SHELLFRAME_CONFIRM_RESULT" "RESULT=0 (Yes)"

ptyunit_test_begin "confirm_on_key: Y → RESULT=0, returns 2"
_reset_confirm
_shellframe_confirm_on_key "Y"
assert_eq "0" "$SHELLFRAME_CONFIRM_RESULT" "Y → Yes"

ptyunit_test_begin "confirm_on_key: n → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "n"
assert_eq "2" "$?" "n returns 2"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "RESULT=1 (No)"

ptyunit_test_begin "confirm_on_key: N → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "N"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "N → No"

# ── Enter confirms current selection ────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: Enter confirms Yes (selected=0)"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=0
_shellframe_confirm_on_key "$SHELLFRAME_KEY_ENTER"
assert_eq "2" "$?" "Enter returns 2"
assert_eq "0" "$SHELLFRAME_CONFIRM_RESULT" "RESULT=0 (Yes)"

ptyunit_test_begin "confirm_on_key: Enter confirms No (selected=1)"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=1
_shellframe_confirm_on_key "$SHELLFRAME_KEY_ENTER"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "RESULT=1 (No)"

ptyunit_test_begin "confirm_on_key: c confirms current selection"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=1
_shellframe_confirm_on_key "c"
assert_eq "2" "$?" "c returns 2"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "c → No"

# ── Cancel keys ─────────────────────────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: Esc → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "$SHELLFRAME_KEY_ESC"
assert_eq "2" "$?" "Esc returns 2"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "Esc → No"

ptyunit_test_begin "confirm_on_key: q → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "q"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "q → No"

ptyunit_test_begin "confirm_on_key: Q → RESULT=1, returns 2"
_reset_confirm
_shellframe_confirm_on_key "Q"
assert_eq "1" "$SHELLFRAME_CONFIRM_RESULT" "Q → No"

# ── Unhandled keys ───────────────────────────────────────────────────────────

ptyunit_test_begin "confirm_on_key: unhandled key returns 1"
_reset_confirm
_shellframe_confirm_on_key "x"
assert_eq "1" "$?" "x returns 1 (unhandled)"

ptyunit_test_begin "confirm_on_key: unhandled key does not change selection"
_reset_confirm
SHELLFRAME_CONFIRM_SELECTED=0
_shellframe_confirm_on_key "x"
assert_eq "0" "$SHELLFRAME_CONFIRM_SELECTED" "selection unchanged"

ptyunit_test_summary
