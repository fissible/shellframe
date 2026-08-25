#!/usr/bin/env bash
# tests/unit/test-table.sh — Unit tests for _shellframe_table_on_key and
# _shellframe_table_scroll_check

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
# ptyunit coverage uses BASH_XTRACEFD=3; widgets write to >&3. Dup the trace fd
# to 4 first, then redirect fd 3 to /dev/null so render output is discarded
# without killing the trace. In normal (non-coverage) runs fd 3 is not open, so
# exec 4>&3 is a silent no-op.
exec 4>&3 2>/dev/null || true   # dup trace fd; no-op outside coverage mode
exec 3>/dev/null                 # discard widget render output
BASH_XTRACEFD=4                  # keep trace on fd 4, safe from >&3 redirects

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

# ── _shellframe_tbl_default_draw_row ─────────────────────────────────────────

ptyunit_test_begin "tbl_default_draw_row: non-selected row has no cursor"
SHELLFRAME_TBL_SELECTED=1
_out=$(_shellframe_tbl_default_draw_row 0 "apple" "eat skip" 0 "")
assert_not_contains "$_out" "> " "non-selected row has no cursor"

ptyunit_test_begin "tbl_default_draw_row: selected row has cursor indicator"
SHELLFRAME_TBL_SELECTED=0
_out=$(_shellframe_tbl_default_draw_row 0 "apple" "eat skip" 0 "")
assert_contains "$_out" "> " "selected row has cursor"

ptyunit_test_begin "tbl_default_draw_row: shows label in output"
SHELLFRAME_TBL_SELECTED=0
_out=$(_shellframe_tbl_default_draw_row 0 "banana" "eat skip" 0 "")
assert_contains "$_out" "banana" "label appears in output"

ptyunit_test_begin "tbl_default_draw_row: shows current action in brackets"
SHELLFRAME_TBL_SELECTED=0
_out=$(_shellframe_tbl_default_draw_row 0 "apple" "eat skip" 1 "")
assert_contains "$_out" "[skip]" "action index 1 shows skip"

ptyunit_test_begin "tbl_default_draw_row: first action shown at index 0"
SHELLFRAME_TBL_SELECTED=0
_out=$(_shellframe_tbl_default_draw_row 0 "apple" "eat skip" 0 "")
assert_contains "$_out" "[eat]" "action index 0 shows eat"

# ── #42: %b escape-injection regression ─────────────────────────────────────
# See test-action-list.sh for rationale: color constants defined with literal
# backslash notation must survive row rendering unexpanded (%s, never %b).

_sf_tbl_saved_bold="$SHELLFRAME_BOLD"
_sf_tbl_saved_reset="$SHELLFRAME_RESET"
SHELLFRAME_BOLD='\033[1m'
SHELLFRAME_RESET='\033[0m'

ptyunit_test_begin "tbl draw_row #42: literal-backslash colors render literally"
_out=$(_shellframe_tbl_default_draw_row 0 "apple" "eat skip" 0 "")
assert_contains "$_out" '\033[1m' "literal backslash sequence preserved"
if [[ "$_out" != *$'\x1b'* ]]; then
    ptyunit_pass
else
    ptyunit_fail "real ESC byte injected into output (escape expansion)"
fi

SHELLFRAME_BOLD="$_sf_tbl_saved_bold"
SHELLFRAME_RESET="$_sf_tbl_saved_reset"

ptyunit_test_summary
