#!/usr/bin/env bash
# tests/unit/test-grid.sh — Unit tests for src/widgets/grid.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/selection.sh"
source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/widgets/grid.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── Setup helpers ─────────────────────────────────────────────────────────────

# 3-column, 5-row grid
_reset_grid() {
    SHELLFRAME_GRID_CTX="g"
    SHELLFRAME_GRID_ROWS=5
    SHELLFRAME_GRID_COLS=3
    SHELLFRAME_GRID_PK_COLS=0
    SHELLFRAME_GRID_HEADERS=("Name" "Age" "City")
    SHELLFRAME_GRID_COL_WIDTHS=(20 5 15)
    # Row 0: Alice 30 NYC
    # Row 1: Bob   25 LA
    # Row 2: Carol 40 Chicago
    # Row 3: Dave  35 Boston
    # Row 4: Eve   28 Miami
    SHELLFRAME_GRID_DATA=(
        "Alice" "30" "NYC"
        "Bob"   "25" "LA"
        "Carol" "40" "Chicago"
        "Dave"  "35" "Boston"
        "Eve"   "28" "Miami"
    )
    SHELLFRAME_GRID_MULTISELECT=0
    SHELLFRAME_GRID_FOCUSED=0
    SHELLFRAME_GRID_COL_ALIGN=()
    shellframe_grid_init "g" 10
}

# ── shellframe_grid_init ──────────────────────────────────────────────────────

ptyunit_test_begin "grid_init: cursor starts at 0"
_reset_grid
assert_output "0" shellframe_sel_cursor "g"

ptyunit_test_begin "grid_init: v-scroll top starts at 0"
_reset_grid
assert_output "0" shellframe_scroll_top "g"

ptyunit_test_begin "grid_init: h-scroll left starts at 0"
_reset_grid
assert_output "0" shellframe_scroll_left "g"

ptyunit_test_begin "grid_init: reinit resets cursor to 0"
_reset_grid
shellframe_sel_move "g" down
shellframe_grid_init "g" 10
assert_output "0" shellframe_sel_cursor "g"

ptyunit_test_begin "grid_init: reinit resets v-scroll to 0"
_reset_grid
shellframe_scroll_move "g" down 3
shellframe_grid_init "g" 10
assert_output "0" shellframe_scroll_top "g"

ptyunit_test_begin "grid_init: reinit resets h-scroll to 0"
_reset_grid
shellframe_scroll_move "g" right 2
shellframe_grid_init "g" 10
assert_output "0" shellframe_scroll_left "g"

# ── shellframe_grid_on_key: row navigation ────────────────────────────────────

ptyunit_test_begin "grid_on_key: down moves cursor, returns 0"
_reset_grid
shellframe_grid_on_key $'\033[B'
assert_eq "0" "$?" "down returns 0"
assert_output "1" shellframe_sel_cursor "g"

ptyunit_test_begin "grid_on_key: up moves cursor, returns 0"
_reset_grid
shellframe_grid_on_key $'\033[B'   # cursor → 1
shellframe_grid_on_key $'\033[B'   # cursor → 2
shellframe_grid_on_key $'\033[A'   # cursor → 1
assert_eq "0" "$?" "up returns 0"
assert_output "1" shellframe_sel_cursor "g"

ptyunit_test_begin "grid_on_key: up at top clamps at 0"
_reset_grid
shellframe_grid_on_key $'\033[A'
assert_output "0" shellframe_sel_cursor "g"

ptyunit_test_begin "grid_on_key: down at bottom clamps at last row"
_reset_grid
for _i in 1 2 3 4 5 6; do shellframe_grid_on_key $'\033[B'; done
assert_output "4" shellframe_sel_cursor "g"   # 5-row grid → max idx = 4

ptyunit_test_begin "grid_on_key: home moves cursor to 0"
_reset_grid
shellframe_grid_on_key $'\033[B'
shellframe_grid_on_key $'\033[B'
shellframe_grid_on_key $'\033[H'
assert_eq "0" "$?" "home returns 0"
assert_output "0" shellframe_sel_cursor "g"

ptyunit_test_begin "grid_on_key: end moves cursor to last row"
_reset_grid
shellframe_grid_on_key $'\033[F'
assert_eq "0" "$?" "end returns 0"
assert_output "4" shellframe_sel_cursor "g"

# ── shellframe_grid_on_key: page up / down ────────────────────────────────────

ptyunit_test_begin "grid_on_key: page_down moves by viewport rows"
SHELLFRAME_GRID_CTX="gpg"
SHELLFRAME_GRID_ROWS=12
SHELLFRAME_GRID_COLS=2
SHELLFRAME_GRID_COL_WIDTHS=(10 10)
SHELLFRAME_GRID_HEADERS=("A" "B")
SHELLFRAME_GRID_DATA=()
shellframe_grid_init "gpg" 4   # viewport = 4 rows
shellframe_grid_on_key $'\033[6~'
assert_eq "0" "$?" "page_down returns 0"
assert_output "4" shellframe_sel_cursor "gpg"

ptyunit_test_begin "grid_on_key: page_up moves by viewport rows"
shellframe_sel_init "gpg" 12
shellframe_sel_move "gpg" end   # cursor → 11
shellframe_grid_on_key $'\033[5~'
assert_eq "0" "$?" "page_up returns 0"
assert_output "7" shellframe_sel_cursor "gpg"   # 11 - 4 = 7

# Restore for subsequent tests
SHELLFRAME_GRID_CTX="g"

# ── shellframe_grid_on_key: h-scroll ─────────────────────────────────────────

ptyunit_test_begin "grid_on_key: right scrolls h-scroll, returns 0"
_reset_grid
shellframe_grid_on_key $'\033[C'
assert_eq "0" "$?" "right returns 0"
assert_output "1" shellframe_scroll_left "g"

ptyunit_test_begin "grid_on_key: left scrolls h-scroll back, returns 0"
_reset_grid
shellframe_scroll_move "g" right 2
shellframe_grid_on_key $'\033[D'
assert_eq "0" "$?" "left returns 0"
assert_output "1" shellframe_scroll_left "g"

ptyunit_test_begin "grid_on_key: left at h-scroll 0 clamps at 0"
_reset_grid
shellframe_grid_on_key $'\033[D'
assert_output "0" shellframe_scroll_left "g"

ptyunit_test_begin "grid_on_key: right clamps at max column (ncols-1 with vcols=1)"
_reset_grid
# 3-col grid, vcols=1 (conservative init) → max_left = 3-1 = 2
for _i in 1 2 3 4 5 6 7 8 9 10; do shellframe_grid_on_key $'\033[C'; done
assert_output "2" shellframe_scroll_left "g"

# ── shellframe_grid_on_key: Enter ─────────────────────────────────────────────

ptyunit_test_begin "grid_on_key: Enter (\\n) returns 2"
_reset_grid
shellframe_grid_on_key $'\n'
assert_eq "2" "$?" "Enter returns 2"

ptyunit_test_begin "grid_on_key: Enter (\\r) returns 2"
_reset_grid
shellframe_grid_on_key $'\r'
assert_eq "2" "$?" "Enter CR returns 2"

# ── shellframe_grid_on_key: multiselect ───────────────────────────────────────

ptyunit_test_begin "grid_on_key: space toggles when multiselect=1"
_reset_grid
SHELLFRAME_GRID_MULTISELECT=1
shellframe_grid_on_key " "
assert_eq "0" "$?" "space returns 0"
assert_output "1" shellframe_sel_selected_count "g"

ptyunit_test_begin "grid_on_key: space untoggles when multiselect=1"
_reset_grid
SHELLFRAME_GRID_MULTISELECT=1
shellframe_sel_toggle "g" 0   # pre-select item 0 so untoggle has something to clear
shellframe_grid_on_key " "
assert_output "0" shellframe_sel_selected_count "g"

ptyunit_test_begin "grid_on_key: space not handled when multiselect=0"
_reset_grid
SHELLFRAME_GRID_MULTISELECT=0
shellframe_grid_on_key " "
assert_eq "1" "$?" "space returns 1 without multiselect"

# ── shellframe_grid_on_key: unhandled ─────────────────────────────────────────

ptyunit_test_begin "grid_on_key: unhandled key returns 1"
_reset_grid
shellframe_grid_on_key "x"
assert_eq "1" "$?" "unhandled key returns 1"

ptyunit_test_begin "grid_on_key: Escape returns 1"
_reset_grid
shellframe_grid_on_key $'\033'
assert_eq "1" "$?" "escape returns 1"

# ── shellframe_grid_on_focus ──────────────────────────────────────────────────

ptyunit_test_begin "grid_on_focus: sets FOCUSED=1"
SHELLFRAME_GRID_FOCUSED=0
shellframe_grid_on_focus 1
assert_eq "1" "$SHELLFRAME_GRID_FOCUSED" "focused set to 1"

ptyunit_test_begin "grid_on_focus: sets FOCUSED=0"
SHELLFRAME_GRID_FOCUSED=1
shellframe_grid_on_focus 0
assert_eq "0" "$SHELLFRAME_GRID_FOCUSED" "focused set to 0"

# ── shellframe_grid_size ───────────────────────────────────────────────────────

ptyunit_test_begin "grid_size: returns 3 3 0 0"
assert_output "3 3 0 0" shellframe_grid_size

# ── empty grid edge cases ─────────────────────────────────────────────────────

ptyunit_test_begin "grid_init: zero rows is valid"
SHELLFRAME_GRID_CTX="gempty"
SHELLFRAME_GRID_ROWS=0
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_COL_WIDTHS=(10 10 10)
SHELLFRAME_GRID_HEADERS=("A" "B" "C")
SHELLFRAME_GRID_DATA=()
shellframe_grid_init "gempty" 5
assert_output "0" shellframe_sel_cursor "gempty"
assert_output "0" shellframe_sel_count "gempty"

ptyunit_test_begin "grid_on_key: down on empty grid returns 0 without error"
SHELLFRAME_GRID_CTX="gempty"
shellframe_grid_on_key $'\033[B'
assert_eq "0" "$?" "down on empty returns 0"

ptyunit_test_begin "grid_on_key: up on empty grid returns 0 without error"
shellframe_grid_on_key $'\033[A'
assert_eq "0" "$?" "up on empty returns 0"

# ── h-scroll stays at 0 when only 1 column ────────────────────────────────────

ptyunit_test_begin "grid h-scroll: single column, right clamps at 0"
SHELLFRAME_GRID_CTX="g1col"
SHELLFRAME_GRID_ROWS=3
SHELLFRAME_GRID_COLS=1
SHELLFRAME_GRID_COL_WIDTHS=(30)
SHELLFRAME_GRID_HEADERS=("Name")
SHELLFRAME_GRID_DATA=("Alice" "Bob" "Carol")
shellframe_grid_init "g1col" 10
shellframe_grid_on_key $'\033[C'
assert_output "0" shellframe_scroll_left "g1col"

# ── SHELLFRAME_GRID_PK_COLS ────────────────────────────────────────────────────
# PK_COLS is a render-only hint; it does not affect key handling or scroll state.
# These tests verify the global's default, that init preserves it, and that
# navigation still works correctly regardless of its value.

ptyunit_test_begin "grid globals: PK_COLS defaults to 0"
assert_eq "0" "$SHELLFRAME_GRID_PK_COLS" "default PK_COLS is 0"

ptyunit_test_begin "grid_init: PK_COLS=1 does not affect cursor or scroll init"
SHELLFRAME_GRID_CTX="gpk"
SHELLFRAME_GRID_ROWS=4
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_PK_COLS=1
SHELLFRAME_GRID_COL_WIDTHS=(5 10 10)
SHELLFRAME_GRID_HEADERS=("id" "name" "val")
SHELLFRAME_GRID_DATA=("1" "alpha" "x"  "2" "beta" "y"  "3" "gamma" "z"  "4" "delta" "w")
shellframe_grid_init "gpk" 10
assert_output "0" shellframe_sel_cursor "gpk"
assert_output "0" shellframe_scroll_top "gpk"
assert_output "0" shellframe_scroll_left "gpk"

ptyunit_test_begin "grid_on_key: navigation unaffected by PK_COLS=1"
SHELLFRAME_GRID_CTX="gpk"
shellframe_grid_on_key $'\033[B'   # down → 1
shellframe_grid_on_key $'\033[B'   # down → 2
assert_output "2" shellframe_sel_cursor "gpk"
shellframe_grid_on_key $'\033[A'   # up → 1
assert_output "1" shellframe_sel_cursor "gpk"

ptyunit_test_begin "grid_on_key: h-scroll unaffected by PK_COLS=1"
SHELLFRAME_GRID_CTX="gpk"
shellframe_grid_on_key $'\033[C'   # right → h_left = 1
assert_output "1" shellframe_scroll_left "gpk"
shellframe_grid_on_key $'\033[D'   # left  → h_left = 0
assert_output "0" shellframe_scroll_left "gpk"

ptyunit_test_begin "grid_on_key: PK_COLS=2 (multi-col PK) navigation correct"
SHELLFRAME_GRID_CTX="gpk2"
SHELLFRAME_GRID_ROWS=3
SHELLFRAME_GRID_COLS=4
SHELLFRAME_GRID_PK_COLS=2
SHELLFRAME_GRID_COL_WIDTHS=(5 5 10 10)
SHELLFRAME_GRID_HEADERS=("a" "b" "c" "d")
SHELLFRAME_GRID_DATA=("1" "x" "foo" "bar"  "2" "y" "baz" "qux"  "3" "z" "abc" "def")
shellframe_grid_init "gpk2" 10
shellframe_grid_on_key $'\033[F'   # end → cursor = 2
assert_output "2" shellframe_sel_cursor "gpk2"
shellframe_grid_on_key $'\033[H'   # home → cursor = 0
assert_output "0" shellframe_sel_cursor "gpk2"

# ── shellframe_grid_render: fd 3 output ──────────────────────────────────────

ptyunit_test_begin "grid_render: renders header labels to fd 3"
_reset_grid
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 50 10
exec 3>&-
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$_content" "Name"
assert_contains "$_content" "Age"
rm -f "$_out"

ptyunit_test_begin "grid_render: renders data cell values to fd 3"
_reset_grid
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 50 10
exec 3>&-
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$_content" "Alice"
assert_contains "$_content" "Bob"
rm -f "$_out"

ptyunit_test_begin "grid_render: no headers renders data only (no separator row)"
SHELLFRAME_GRID_CTX="gnh"
SHELLFRAME_GRID_ROWS=3
SHELLFRAME_GRID_COLS=2
SHELLFRAME_GRID_HEADERS=()
SHELLFRAME_GRID_COL_WIDTHS=(10 10)
SHELLFRAME_GRID_DATA=("foo" "bar" "baz" "qux" "one" "two")
SHELLFRAME_GRID_MULTISELECT=0
SHELLFRAME_GRID_FOCUSED=0
shellframe_grid_init "gnh" 5
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 30 5 "gnh"
exec 3>&-
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$_content" "foo"
rm -f "$_out"

ptyunit_test_begin "grid_render: PK_COLS renders thick separator"
SHELLFRAME_GRID_CTX="gpkr"
SHELLFRAME_GRID_ROWS=2
SHELLFRAME_GRID_COLS=3
SHELLFRAME_GRID_PK_COLS=1
SHELLFRAME_GRID_HEADERS=("id" "name" "val")
SHELLFRAME_GRID_COL_WIDTHS=(5 10 10)
SHELLFRAME_GRID_DATA=("1" "alpha" "x" "2" "beta" "y")
SHELLFRAME_GRID_MULTISELECT=0
SHELLFRAME_GRID_FOCUSED=0
shellframe_grid_init "gpkr" 5
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 40 6
exec 3>&-
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$_content" "┃"
rm -f "$_out"

ptyunit_test_begin "grid_render: multiselect shows checkbox prefix"
_reset_grid
SHELLFRAME_GRID_MULTISELECT=1
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 60 10
exec 3>&-
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$_content" "[ ]"
rm -f "$_out"

ptyunit_test_begin "grid_render: h-scroll > 0 skips first column"
_reset_grid
shellframe_scroll_move "g" right 1
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 50 10
exec 3>&-
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$_content" "Age"
rm -f "$_out"

# ── SHELLFRAME_GRID_COL_ALIGN ─────────────────────────────────────────────────

ptyunit_test_begin "grid_render: right-align pads numeric cells on left"
_reset_grid
SHELLFRAME_GRID_COL_ALIGN=(left right left)   # Age column → right
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 50 10
exec 3>&-
# Strip ANSI, find the 'Age' column area — value '30' should appear with leading spaces
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$_content" "30"   # value still rendered
rm -f "$_out"

ptyunit_test_begin "grid_render: COL_ALIGN defaults to left when unset"
_reset_grid
SHELLFRAME_GRID_COL_ALIGN=()
_out=$(mktemp)
exec 3>"$_out"
shellframe_grid_render 1 1 50 10
exec 3>&-
_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_out")
assert_contains "$_content" "Alice"   # left-aligned text still rendered
rm -f "$_out"

ptyunit_test_summary
