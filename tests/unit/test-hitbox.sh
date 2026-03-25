#!/usr/bin/env bash
# tests/unit/test-hitbox.sh — Unit tests for src/hitbox.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/hitbox.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── shellframe_widget_at ──────────────────────────────────────────────────────

ptyunit_test_begin "widget_at: returns name for point inside registered widget"
shellframe_widget_clear
shellframe_widget_register "my_list" 2 5 20 10
assert_output "my_list" shellframe_widget_at 5 10

ptyunit_test_begin "widget_at: returns empty for point above registered widget"
shellframe_widget_clear
shellframe_widget_register "my_list" 2 5 20 10
assert_output "" shellframe_widget_at 1 5

ptyunit_test_begin "widget_at: returns empty for point below registered widget"
shellframe_widget_clear
shellframe_widget_register "my_list" 2 5 20 10   # rows 2..11
assert_output "" shellframe_widget_at 12 5

ptyunit_test_begin "widget_at: point on top-left corner is inside"
shellframe_widget_clear
shellframe_widget_register "box" 3 7 5 4   # rows 3..6, cols 7..11
assert_output "box" shellframe_widget_at 3 7

ptyunit_test_begin "widget_at: point on bottom-right corner is inside"
shellframe_widget_clear
shellframe_widget_register "box" 3 7 5 4   # rows 3..6, cols 7..11
assert_output "box" shellframe_widget_at 6 11

ptyunit_test_begin "widget_at: one row past bottom is outside"
shellframe_widget_clear
shellframe_widget_register "box" 3 7 5 4   # rows 3..6
assert_output "" shellframe_widget_at 7 7

ptyunit_test_begin "widget_at: one col past right is outside"
shellframe_widget_clear
shellframe_widget_register "box" 3 7 5 4   # cols 7..11
assert_output "" shellframe_widget_at 3 12

ptyunit_test_begin "widget_at: overlap — last-registered wins"
shellframe_widget_clear
shellframe_widget_register "first"  0 0 10 10
shellframe_widget_register "second" 0 0 10 10
assert_output "second" shellframe_widget_at 5 5

ptyunit_test_begin "widget_at: non-overlapping — returns correct widget"
shellframe_widget_clear
shellframe_widget_register "left"  0  0 10 5   # rows 0..4, cols 0..9
shellframe_widget_register "right" 0 10 10 5   # rows 0..4, cols 10..19
assert_output "left"  shellframe_widget_at 2 5
assert_output "right" shellframe_widget_at 2 15

ptyunit_test_begin "widget_at: out_var form sets variable without printing"
shellframe_widget_clear
shellframe_widget_register "panel" 0 0 20 20
_result=""
shellframe_widget_at 5 5 _result
assert_eq "panel" "$_result" "out_var set correctly"

# ── shellframe_widget_clear ───────────────────────────────────────────────────

ptyunit_test_begin "widget_clear: no-arg clears all registrations"
shellframe_widget_clear
shellframe_widget_register "foo" 0 0 10 10
shellframe_widget_clear
assert_output "" shellframe_widget_at 5 5

ptyunit_test_begin "widget_clear: clear by name removes only that widget"
shellframe_widget_clear
shellframe_widget_register "a" 0  0 10 10
shellframe_widget_register "b" 0 10 10 10
shellframe_widget_clear "a"
assert_output "" shellframe_widget_at 5 5
assert_output "b" shellframe_widget_at 5 15

ptyunit_test_begin "widget_clear: clear by name is idempotent on unknown name"
shellframe_widget_clear
shellframe_widget_register "x" 0 0 5 5
shellframe_widget_clear "nonexistent"
assert_output "x" shellframe_widget_at 2 2

ptyunit_test_summary
