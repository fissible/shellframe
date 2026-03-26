#!/usr/bin/env bash
# tests/unit/test-scroll.sh — Unit tests for src/scroll.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/scroll.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── shellframe_scroll_init ────────────────────────────────────────────────────

ptyunit_test_begin "scroll_init: top starts at 0"
shellframe_scroll_init "t" 100 80 20 40
assert_output "0" shellframe_scroll_top "t"

ptyunit_test_begin "scroll_init: left starts at 0"
assert_output "0" shellframe_scroll_left "t"

ptyunit_test_begin "scroll_init: reinit resets offsets"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 10
shellframe_scroll_init "t" 100 80 20 40
assert_output "0" shellframe_scroll_top "t"

# ── shellframe_scroll_move: vertical ─────────────────────────────────────────

ptyunit_test_begin "scroll_move: down increments top"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 5
assert_output "5" shellframe_scroll_top "t"

ptyunit_test_begin "scroll_move: up decrements top"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 10
shellframe_scroll_move "t" up 3
assert_output "7" shellframe_scroll_top "t"

ptyunit_test_begin "scroll_move: up clamps at 0"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" up 99
assert_output "0" shellframe_scroll_top "t"

ptyunit_test_begin "scroll_move: down clamps at max (rows - vrows)"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 999
assert_output "80" shellframe_scroll_top "t"   # max = 100 - 20

ptyunit_test_begin "scroll_move: home sets top to 0"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 50
shellframe_scroll_move "t" home
assert_output "0" shellframe_scroll_top "t"

ptyunit_test_begin "scroll_move: end sets top to max"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" end
assert_output "80" shellframe_scroll_top "t"

ptyunit_test_begin "scroll_move: page_down moves by vrows"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" page_down
assert_output "20" shellframe_scroll_top "t"

ptyunit_test_begin "scroll_move: page_up moves by vrows"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 40
shellframe_scroll_move "t" page_up
assert_output "20" shellframe_scroll_top "t"

ptyunit_test_begin "scroll_move: content smaller than viewport — max_top is 0"
shellframe_scroll_init "t" 10 80 20 40
shellframe_scroll_move "t" down 999
assert_output "0" shellframe_scroll_top "t"

# ── shellframe_scroll_move: horizontal ───────────────────────────────────────

ptyunit_test_begin "scroll_move: right increments left"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 5
assert_output "5" shellframe_scroll_left "t"

ptyunit_test_begin "scroll_move: left decrements"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 10
shellframe_scroll_move "t" left 3
assert_output "7" shellframe_scroll_left "t"

ptyunit_test_begin "scroll_move: left clamps at 0"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" left 99
assert_output "0" shellframe_scroll_left "t"

ptyunit_test_begin "scroll_move: right clamps at max (cols - vcols)"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 999
assert_output "60" shellframe_scroll_left "t"   # max = 80 - 20

ptyunit_test_begin "scroll_move: h_home sets left to 0"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 30
shellframe_scroll_move "t" h_home
assert_output "0" shellframe_scroll_left "t"

ptyunit_test_begin "scroll_move: h_end sets left to max"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" h_end
assert_output "60" shellframe_scroll_left "t"

# ── shellframe_scroll_ensure_row ─────────────────────────────────────────────

ptyunit_test_begin "ensure_row: row already visible — no change"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 10
shellframe_scroll_ensure_row "t" 15    # 15 is in viewport [10, 29]
assert_output "10" shellframe_scroll_top "t"

ptyunit_test_begin "ensure_row: row above viewport — scroll up"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 20
shellframe_scroll_ensure_row "t" 5    # 5 is above viewport [20, 39]
assert_output "5" shellframe_scroll_top "t"

ptyunit_test_begin "ensure_row: row below viewport — scroll down"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_ensure_row "t" 25   # 25 is below viewport [0, 19]
assert_output "6" shellframe_scroll_top "t"   # 25 - 20 + 1 = 6

ptyunit_test_begin "ensure_row: last row of content — clamps at max_top"
shellframe_scroll_init "t" 30 80 20 40
shellframe_scroll_ensure_row "t" 29   # last row; max_top = 10
assert_output "10" shellframe_scroll_top "t"

# ── shellframe_scroll_ensure_col ─────────────────────────────────────────────

ptyunit_test_begin "ensure_col: col already visible — no change"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 10
shellframe_scroll_ensure_col "t" 15   # 15 in viewport [10, 29]
assert_output "10" shellframe_scroll_left "t"

ptyunit_test_begin "ensure_col: col to the left — scroll left"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 20
shellframe_scroll_ensure_col "t" 5
assert_output "5" shellframe_scroll_left "t"

ptyunit_test_begin "ensure_col: col to the right — scroll right"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_ensure_col "t" 25   # below viewport [0, 19]
assert_output "6" shellframe_scroll_left "t"   # 25 - 20 + 1 = 6

# ── shellframe_scroll_row_visible ─────────────────────────────────────────────

ptyunit_test_begin "row_visible: first row of viewport — visible"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 10
shellframe_scroll_row_visible "t" 10
assert_eq "0" "$?" "first row visible"

ptyunit_test_begin "row_visible: last row of viewport — visible"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 10
shellframe_scroll_row_visible "t" 29
assert_eq "0" "$?" "last row visible"

ptyunit_test_begin "row_visible: row above viewport — not visible"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 10
shellframe_scroll_row_visible "t" 9
assert_eq "1" "$?" "row above not visible"

ptyunit_test_begin "row_visible: row below viewport — not visible"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 10
shellframe_scroll_row_visible "t" 30
assert_eq "1" "$?" "row below not visible"

# ── Two independent contexts ──────────────────────────────────────────────────

ptyunit_test_begin "two contexts are independent"
shellframe_scroll_init "a" 100 80 20 40
shellframe_scroll_init "b" 100 80 20 40
shellframe_scroll_move "a" down 15
assert_output "15" shellframe_scroll_top "a"
assert_output "0"  shellframe_scroll_top "b"

# ── shellframe_scroll_resize ──────────────────────────────────────────────────

ptyunit_test_begin "scroll_resize: recamps offset when viewport grows"
shellframe_scroll_init "t" 30 80 10 40
shellframe_scroll_move "t" down 25   # top = 20 (max = 30-10 = 20)
shellframe_scroll_resize "t" 20 40   # larger viewport: max now = 30-20 = 10
assert_output "10" shellframe_scroll_top "t"

ptyunit_test_begin "out_var form: top via variable"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 7
_t=""
shellframe_scroll_top "t" _t
assert_eq "7" "$_t"

ptyunit_test_begin "out_var form: left via variable"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 5
_l=""
shellframe_scroll_left "t" _l
assert_eq "5" "$_l"

# ── shellframe_scroll_col_visible ─────────────────────────────────────────────

ptyunit_test_begin "col_visible: first col of viewport — visible"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 10
shellframe_scroll_col_visible "t" 10
assert_eq "0" "$?" "first col visible"

ptyunit_test_begin "col_visible: last col of viewport — visible"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 10
shellframe_scroll_col_visible "t" 29
assert_eq "0" "$?" "last col visible"

ptyunit_test_begin "col_visible: col to the left of viewport — not visible"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 10
shellframe_scroll_col_visible "t" 9
assert_eq "1" "$?" "col left of viewport not visible"

ptyunit_test_begin "col_visible: col to the right of viewport — not visible"
shellframe_scroll_init "t" 100 80 20 20
shellframe_scroll_move "t" right 10
shellframe_scroll_col_visible "t" 30
assert_eq "1" "$?" "col right of viewport not visible"

# ── shellframe_scroll_on_mouse ────────────────────────────────────────────────

# Stub shellframe_shell_mark_dirty (defined in shell.sh)
_SHELLFRAME_SCROLL_DIRTY=0
shellframe_shell_mark_dirty() { _SHELLFRAME_SCROLL_DIRTY=1; }

ptyunit_test_begin "scroll_on_mouse: scroll-up (button 64) scrolls up and marks dirty"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" down 10
_SHELLFRAME_SCROLL_DIRTY=0
shellframe_scroll_on_mouse "t" 64 "press"
assert_eq "0" "$?" "scroll-up returns 0"
assert_output "9" shellframe_scroll_top "t"
assert_eq "1" "$_SHELLFRAME_SCROLL_DIRTY" "dirty set on scroll-up"

ptyunit_test_begin "scroll_on_mouse: scroll-down (button 65) scrolls down and marks dirty"
shellframe_scroll_init "t" 100 80 20 40
_SHELLFRAME_SCROLL_DIRTY=0
shellframe_scroll_on_mouse "t" 65 "press"
assert_eq "0" "$?" "scroll-down returns 0"
assert_output "1" shellframe_scroll_top "t"
assert_eq "1" "$_SHELLFRAME_SCROLL_DIRTY" "dirty set on scroll-down"

ptyunit_test_begin "scroll_on_mouse: non-press action returns 1"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_on_mouse "t" 64 "release"; _rc=$?
assert_eq "1" "$_rc" "release event returns 1"

ptyunit_test_begin "scroll_on_mouse: unhandled button returns 1"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_on_mouse "t" 0 "press"; _rc=$?
assert_eq "1" "$_rc" "unhandled button returns 1"

# ── Error paths ───────────────────────────────────────────────────────────────

ptyunit_test_begin "scroll_init: invalid ctx name returns 1"
shellframe_scroll_init "" 10 10 5 5; _rc=$?
assert_eq "1" "$_rc" "empty ctx returns 1"

ptyunit_test_begin "scroll_move: unknown direction returns 1"
shellframe_scroll_init "t" 100 80 20 40
shellframe_scroll_move "t" "bogus_dir"; _rc=$?
assert_eq "1" "$_rc" "unknown direction returns 1"

ptyunit_test_summary
