#!/usr/bin/env bash
# tests/unit/test-selection.sh — Unit tests for shellframe/src/selection.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/selection.sh"
source "$TESTS_DIR/assert.sh"

# ── shellframe_sel_init ────────────────────────────────────────────────────────

shellframe_test_begin "sel_init: cursor starts at 0"
shellframe_sel_init "t" 5
assert_output "0" shellframe_sel_cursor "t"

shellframe_test_begin "sel_init: count is recorded"
shellframe_sel_init "t" 5
assert_output "5" shellframe_sel_count "t"

shellframe_test_begin "sel_init: no items selected initially"
shellframe_sel_init "t" 5
assert_output "0" shellframe_sel_selected_count "t"

shellframe_test_begin "sel_init: zero-item list"
shellframe_sel_init "t" 0
assert_output "0" shellframe_sel_cursor "t"
assert_output "0" shellframe_sel_count "t"

shellframe_test_begin "sel_init: reinit resets cursor and flags"
shellframe_sel_init "t" 5
shellframe_sel_move "t" down
shellframe_sel_toggle "t"
shellframe_sel_init "t" 5   # reinitialise
assert_output "0" shellframe_sel_cursor "t"
assert_output "0" shellframe_sel_selected_count "t"

# ── shellframe_sel_move ────────────────────────────────────────────────────────

shellframe_test_begin "sel_move: down increments cursor"
shellframe_sel_init "t" 5
shellframe_sel_move "t" down
assert_output "1" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: down clamps at last item"
shellframe_sel_init "t" 3
shellframe_sel_move "t" down
shellframe_sel_move "t" down
shellframe_sel_move "t" down   # would be index 3, out of range
assert_output "2" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: up from 0 stays at 0"
shellframe_sel_init "t" 5
shellframe_sel_move "t" up
assert_output "0" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: up decrements cursor"
shellframe_sel_init "t" 5
shellframe_sel_move "t" down
shellframe_sel_move "t" down
shellframe_sel_move "t" up
assert_output "1" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: home goes to 0"
shellframe_sel_init "t" 5
shellframe_sel_move "t" down
shellframe_sel_move "t" down
shellframe_sel_move "t" home
assert_output "0" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: end goes to last item"
shellframe_sel_init "t" 5
shellframe_sel_move "t" end
assert_output "4" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: page_down jumps by page_size"
shellframe_sel_init "t" 20
shellframe_sel_move "t" page_down 5
assert_output "5" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: page_down clamps at last item"
shellframe_sel_init "t" 10
shellframe_sel_move "t" page_down 20
assert_output "9" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: page_up from middle"
shellframe_sel_init "t" 20
shellframe_sel_move "t" page_down 10
shellframe_sel_move "t" page_up 4
assert_output "6" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: page_up clamps at 0"
shellframe_sel_init "t" 10
shellframe_sel_move "t" down
shellframe_sel_move "t" page_up 20
assert_output "0" shellframe_sel_cursor "t"

shellframe_test_begin "sel_move: empty list — no crash"
shellframe_sel_init "t" 0
shellframe_sel_move "t" down
shellframe_sel_move "t" up
assert_output "0" shellframe_sel_cursor "t"

# ── shellframe_sel_toggle ──────────────────────────────────────────────────────

shellframe_test_begin "sel_toggle: toggles cursor item on"
shellframe_sel_init "t" 5
shellframe_sel_toggle "t"
shellframe_sel_is_selected "t" 0 && result="yes" || result="no"
assert_eq "yes" "$result" "item 0 should be selected after toggle"

shellframe_test_begin "sel_toggle: double toggle returns to off"
shellframe_sel_init "t" 5
shellframe_sel_toggle "t"
shellframe_sel_toggle "t"
shellframe_sel_is_selected "t" 0 && result="yes" || result="no"
assert_eq "no" "$result" "item 0 deselected after double toggle"

shellframe_test_begin "sel_toggle: toggle at explicit index"
shellframe_sel_init "t" 5
shellframe_sel_toggle "t" 3
shellframe_sel_is_selected "t" 3 && result="yes" || result="no"
assert_eq "yes" "$result" "item 3 toggled explicitly"

shellframe_test_begin "sel_toggle: toggle multiple items independently"
shellframe_sel_init "t" 5
shellframe_sel_toggle "t" 1
shellframe_sel_toggle "t" 3
shellframe_sel_is_selected "t" 0 && result0="yes" || result0="no"
shellframe_sel_is_selected "t" 1 && result1="yes" || result1="no"
shellframe_sel_is_selected "t" 2 && result2="yes" || result2="no"
shellframe_sel_is_selected "t" 3 && result3="yes" || result3="no"
assert_eq "no"  "$result0" "item 0 not selected"
assert_eq "yes" "$result1" "item 1 selected"
assert_eq "no"  "$result2" "item 2 not selected"
assert_eq "yes" "$result3" "item 3 selected"

# ── shellframe_sel_select_all / shellframe_sel_clear_all ──────────────────────

shellframe_test_begin "sel_select_all: all items selected"
shellframe_sel_init "t" 4
shellframe_sel_select_all "t"
assert_output "4" shellframe_sel_selected_count "t"

shellframe_test_begin "sel_clear_all: all items deselected"
shellframe_sel_init "t" 4
shellframe_sel_select_all "t"
shellframe_sel_clear_all "t"
assert_output "0" shellframe_sel_selected_count "t"

shellframe_test_begin "sel_select_all then partial toggle"
shellframe_sel_init "t" 4
shellframe_sel_select_all "t"
shellframe_sel_toggle "t" 1   # deselect item 1
assert_output "3" shellframe_sel_selected_count "t"

# ── shellframe_sel_selected ────────────────────────────────────────────────────

shellframe_test_begin "sel_selected: empty selection prints blank line"
shellframe_sel_init "t" 5
result=$(shellframe_sel_selected "t")
assert_eq "" "${result%$'\n'}" "empty selection is blank"

shellframe_test_begin "sel_selected: single item"
shellframe_sel_init "t" 5
shellframe_sel_toggle "t" 2
result=$(shellframe_sel_selected "t")
assert_eq "2" "${result%$'\n'}" "single selected item"

shellframe_test_begin "sel_selected: multiple items in index order"
shellframe_sel_init "t" 5
shellframe_sel_toggle "t" 0
shellframe_sel_toggle "t" 2
shellframe_sel_toggle "t" 4
result=$(shellframe_sel_selected "t")
assert_eq "0 2 4" "${result%$'\n'}" "multiple selected items in order"

# ── shellframe_sel_count ───────────────────────────────────────────────────────

shellframe_test_begin "sel_count: reports init count"
shellframe_sel_init "t" 7
assert_output "7" shellframe_sel_count "t"

# ── context isolation ──────────────────────────────────────────────────────────

shellframe_test_begin "context isolation: two contexts are independent"
shellframe_sel_init "ctx_a" 5
shellframe_sel_init "ctx_b" 3
shellframe_sel_move "ctx_a" down
shellframe_sel_move "ctx_a" down
shellframe_sel_toggle "ctx_a" 1
assert_output "2" shellframe_sel_cursor "ctx_a"
assert_output "0" shellframe_sel_cursor "ctx_b"
shellframe_sel_is_selected "ctx_a" 1 && res="yes" || res="no"
assert_eq "yes" "$res" "ctx_a item 1 selected"
shellframe_sel_is_selected "ctx_b" 1 && res="yes" || res="no"
assert_eq "no" "$res" "ctx_b item 1 not selected (independent)"

# ── invalid ctx rejected ───────────────────────────────────────────────────────

shellframe_test_begin "invalid ctx: rejected with error"
result=0
shellframe_sel_init "bad ctx" 5 2>/dev/null && result=0 || result=1
assert_eq "1" "$result" "invalid ctx name returns error"

shellframe_test_summary
