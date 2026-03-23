#!/usr/bin/env bash
# tests/unit/test-table.sh — Unit tests for _shellframe_table_on_key and
# _shellframe_table_scroll_check

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

_reset_tbl() {
    SHELLFRAME_TBL_SELECTED=0
    SHELLFRAME_TBL_SCROLL=0
    SHELLFRAME_TBL_LABELS=("apple" "banana" "cherry")
    SHELLFRAME_TBL_ACTIONS=("eat skip" "eat peel skip" "eat skip")
    SHELLFRAME_TBL_IDX=(0 0 0)
    SHELLFRAME_TBL_META=("" "" "")
}

# ── Up / Down navigation ────────────────────────────────────────────────────

ptyunit_test_begin "tbl_on_key: Down moves cursor to next row"
_reset_tbl
_shellframe_table_on_key "$SHELLFRAME_KEY_DOWN" 3
assert_eq "0" "$?" "returns 0 (dirty)"
assert_eq "1" "$SHELLFRAME_TBL_SELECTED" "cursor moved to 1"

ptyunit_test_begin "tbl_on_key: Down clamps at last row"
_reset_tbl
SHELLFRAME_TBL_SELECTED=2
_shellframe_table_on_key "$SHELLFRAME_KEY_DOWN" 3
assert_eq "2" "$SHELLFRAME_TBL_SELECTED" "clamped at 2"

ptyunit_test_begin "tbl_on_key: Up moves cursor to previous row"
_reset_tbl
SHELLFRAME_TBL_SELECTED=2
_shellframe_table_on_key "$SHELLFRAME_KEY_UP" 3
assert_eq "1" "$SHELLFRAME_TBL_SELECTED" "moved up to 1"

ptyunit_test_begin "tbl_on_key: Up clamps at row 0"
_reset_tbl
_shellframe_table_on_key "$SHELLFRAME_KEY_UP" 3
assert_eq "0" "$?" "returns 0 (dirty)"
assert_eq "0" "$SHELLFRAME_TBL_SELECTED" "clamped at 0"

# ── Action cycling ──────────────────────────────────────────────────────────

ptyunit_test_begin "tbl_on_key: Right cycles action for selected row"
_reset_tbl
SHELLFRAME_TBL_SELECTED=1    # banana: eat peel skip
_shellframe_table_on_key "$SHELLFRAME_KEY_RIGHT" 3
assert_eq "0" "$?" "returns 0 (dirty)"
assert_eq "1" "${SHELLFRAME_TBL_IDX[1]}" "banana idx cycled to 1 (peel)"

ptyunit_test_begin "tbl_on_key: Space cycles action for selected row"
_reset_tbl
SHELLFRAME_TBL_SELECTED=0    # apple: eat skip
_shellframe_table_on_key "$SHELLFRAME_KEY_SPACE" 3
assert_eq "1" "${SHELLFRAME_TBL_IDX[0]}" "apple idx cycled to 1 (skip)"

ptyunit_test_begin "tbl_on_key: Right wraps action cycle"
_reset_tbl
SHELLFRAME_TBL_SELECTED=0    # apple: eat skip (2 actions)
SHELLFRAME_TBL_IDX[0]=1      # currently on 'skip'
_shellframe_table_on_key "$SHELLFRAME_KEY_RIGHT" 3
assert_eq "0" "${SHELLFRAME_TBL_IDX[0]}" "wrapped back to 0 (eat)"

# ── Confirm / Quit ──────────────────────────────────────────────────────────

ptyunit_test_begin "tbl_on_key: Enter returns 2 (confirm)"
_reset_tbl
_shellframe_table_on_key "$SHELLFRAME_KEY_ENTER" 3
assert_eq "2" "$?" "Enter returns 2"

ptyunit_test_begin "tbl_on_key: c returns 2 (confirm)"
_reset_tbl
_shellframe_table_on_key "c" 3
assert_eq "2" "$?" "c returns 2"

ptyunit_test_begin "tbl_on_key: C returns 2 (confirm)"
_reset_tbl
_shellframe_table_on_key "C" 3
assert_eq "2" "$?" "C returns 2"

ptyunit_test_begin "tbl_on_key: q returns 3 (quit)"
_reset_tbl
_shellframe_table_on_key "q" 3
assert_eq "3" "$?" "q returns 3"

ptyunit_test_begin "tbl_on_key: Q returns 3 (quit)"
_reset_tbl
_shellframe_table_on_key "Q" 3
assert_eq "3" "$?" "Q returns 3"

# ── Unhandled keys ───────────────────────────────────────────────────────────

ptyunit_test_begin "tbl_on_key: unhandled key returns 1"
_reset_tbl
_shellframe_table_on_key "x" 3
assert_eq "1" "$?" "x returns 1 (unhandled)"

ptyunit_test_begin "tbl_on_key: unhandled key does not change state"
_reset_tbl
SHELLFRAME_TBL_SELECTED=1
_shellframe_table_on_key "z" 3
assert_eq "1" "$SHELLFRAME_TBL_SELECTED" "cursor unchanged"

# ── Scroll check ─────────────────────────────────────────────────────────────

ptyunit_test_begin "tbl_scroll_check: selection in viewport — no change"
SHELLFRAME_TBL_SCROLL=0
SHELLFRAME_TBL_SELECTED=1
_shellframe_table_scroll_check 5
assert_eq "1" "$?" "returns 1 (no change)"
assert_eq "0" "$SHELLFRAME_TBL_SCROLL" "scroll unchanged"

ptyunit_test_begin "tbl_scroll_check: selection above viewport — scrolls up"
SHELLFRAME_TBL_SCROLL=3
SHELLFRAME_TBL_SELECTED=1
_shellframe_table_scroll_check 5
assert_eq "0" "$?" "returns 0 (changed)"
assert_eq "1" "$SHELLFRAME_TBL_SCROLL" "scroll set to selection"

ptyunit_test_begin "tbl_scroll_check: selection below viewport — scrolls down"
SHELLFRAME_TBL_SCROLL=0
SHELLFRAME_TBL_SELECTED=5
_shellframe_table_scroll_check 3
assert_eq "0" "$?" "returns 0 (changed)"
assert_eq "3" "$SHELLFRAME_TBL_SCROLL" "scroll adjusted to show selection"

ptyunit_test_begin "tbl_scroll_check: selection at last visible row — no change"
SHELLFRAME_TBL_SCROLL=2
SHELLFRAME_TBL_SELECTED=4   # exactly scroll + vr - 1 = 2 + 3 - 1 = 4
_shellframe_table_scroll_check 3
assert_eq "1" "$?" "returns 1 (no change)"
assert_eq "2" "$SHELLFRAME_TBL_SCROLL" "scroll unchanged"

ptyunit_test_begin "tbl_scroll_check: selection at first visible row — no change"
SHELLFRAME_TBL_SCROLL=2
SHELLFRAME_TBL_SELECTED=2
_shellframe_table_scroll_check 5
assert_eq "1" "$?" "returns 1 (no change)"
assert_eq "2" "$SHELLFRAME_TBL_SCROLL" "scroll unchanged"

ptyunit_test_summary
