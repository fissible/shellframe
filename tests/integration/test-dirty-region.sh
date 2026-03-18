#!/usr/bin/env bash
# tests/integration/test-dirty-region.sh
# Verify that navigation events skip shellframe_screen_clear (dirty=1 partial draw).
#
# Strategy: capture raw ANSI output (PTY_RAW=1), count occurrences of the
# screen-clear sequence \033[H\033[3J\033[2J.
#
# Expected counts:
#   Initial render only (no navigation): 2 (screen_enter + first _draw call)
#   After navigation keys:               still 2 (no additional screen_clear)
#
# These tests FAIL before the dirty-rendering implementation and PASS after.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"

source "$TESTS_DIR/ptyunit/assert.sh"

_SCREEN_CLEAR=$'\033[H\033[3J\033[2J'

# ── action-list ───────────────────────────────────────────────────────────────

SCRIPT_AL="$SHELLFRAME_DIR/examples/action-list.sh"
_al_raw() { PTY_RAW=1 python3 "$PTY_RUN" "$SCRIPT_AL" "$@" 2>/dev/null; }
_al()     {            python3 "$PTY_RUN" "$SCRIPT_AL" "$@" 2>/dev/null; }

ptyunit_test_begin "action-list dirty: baseline — 2 screen_clears on initial render"
out=$(_al_raw ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "action-list dirty: no extra screen_clear after DOWN"
out=$(_al_raw DOWN ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "action-list dirty: no extra screen_clear after multiple DOWN/UP"
out=$(_al_raw DOWN DOWN UP ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "action-list dirty: no extra screen_clear after action cycle (Space)"
out=$(_al_raw SPACE ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "action-list dirty: partial update targets old cursor row (row 1;1)"
out=$(_al_raw DOWN q)
# After DOWN, item 0 (row 1) must be redrawn (deselected) and item 1 (row 2) selected.
# Partial draw uses printf '\033[%d;1H\033[2K' — check for \033[2K which does NOT appear
# in the sequential full draw (action-list draws rows with \n, not absolute positioning).
assert_contains "$out" $'\033[1;1H\033[2K'
assert_contains "$out" $'\033[2;1H\033[2K'

ptyunit_test_begin "action-list dirty: behavior unchanged — DOWN then ENTER selects banana"
out=$(_al DOWN ENTER)
assert_contains "$out" "banana"

# ── table ─────────────────────────────────────────────────────────────────────

SCRIPT_TBL="$SHELLFRAME_DIR/examples/table.sh"
_tbl_raw() { PTY_RAW=1 python3 "$PTY_RUN" "$SCRIPT_TBL" "$@" 2>/dev/null; }
_tbl()     {            python3 "$PTY_RUN" "$SCRIPT_TBL" "$@" 2>/dev/null; }

ptyunit_test_begin "table dirty: baseline — 2 screen_clears on initial render"
out=$(_tbl_raw ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "table dirty: no extra screen_clear after DOWN"
out=$(_tbl_raw DOWN ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "table dirty: no extra screen_clear after multiple DOWN/UP"
out=$(_tbl_raw DOWN DOWN UP ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "table dirty: partial update targets correct rows after DOWN"
out=$(_tbl_raw DOWN q)
# In examples/table.sh there is no page chrome and no column headers, so:
#   _content_top=1, _first_data_row=1
# After DOWN: old cursor = row 0 (terminal row 1), new cursor = row 1 (terminal row 2).
# Full draw  : all rows written once → row1=1, row2=1, row3=1 occurrence(s)
# Partial draw: only old+new cursor rows redrawn → row1+2 each get +1
# Total expected: row1=2, row2=2, row3=1 (untouched by partial draw)
assert_count "$out" $'\033[1;1H\033[2K' 2   # old cursor row: full draw + partial
assert_count "$out" $'\033[2;1H\033[2K' 2   # new cursor row: full draw + partial
assert_count "$out" $'\033[3;1H\033[2K' 1   # untouched row: full draw only

ptyunit_test_begin "table dirty: behavior unchanged — DOWN then ENTER selects banana"
out=$(_tbl DOWN ENTER)
assert_contains "$out" "banana"

# ── confirm ───────────────────────────────────────────────────────────────────

SCRIPT_CF="$SHELLFRAME_DIR/examples/confirm.sh"
_cf_raw() { PTY_RAW=1 python3 "$PTY_RUN" "$SCRIPT_CF" "$@" 2>/dev/null; }
_cf()     {            python3 "$PTY_RUN" "$SCRIPT_CF" "$@" 2>/dev/null; }

ptyunit_test_begin "confirm dirty: baseline — 2 screen_clears on initial render"
out=$(_cf_raw ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "confirm dirty: no extra screen_clear after RIGHT button toggle"
out=$(_cf_raw RIGHT ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "confirm dirty: no extra screen_clear after RIGHT then LEFT"
out=$(_cf_raw RIGHT LEFT ENTER)
assert_count "$out" "$_SCREEN_CLEAR" 2

ptyunit_test_begin "confirm dirty: behavior unchanged — RIGHT then ENTER cancels"
out=$(_cf RIGHT ENTER)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm dirty: behavior unchanged — ENTER confirms"
out=$(_cf ENTER)
assert_contains "$out" "Confirmed"

ptyunit_test_summary
