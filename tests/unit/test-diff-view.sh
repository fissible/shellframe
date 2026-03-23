#!/usr/bin/env bash
# tests/unit/test-diff-view.sh — Unit tests for src/widgets/diff-view.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

_setup_diff() {
    # Minimal parsed diff: one context line, one add, one del
    SHELLFRAME_DIFF_TYPES=("ctx" "add" "del")
    SHELLFRAME_DIFF_LEFT=("unchanged" "" "removed line")
    SHELLFRAME_DIFF_RIGHT=("unchanged" "added line" "")
    SHELLFRAME_DIFF_LNUMS=("1" "" "3")
    SHELLFRAME_DIFF_RNUMS=("1" "2" "")
    SHELLFRAME_DIFF_ROW_COUNT=3
    SHELLFRAME_DIFF_FILE_ROWS=()
    SHELLFRAME_DIFF_FILE_STATUS=()
}

# ── shellframe_diff_view_init ────────────────────────────────────────────────

ptyunit_test_begin "diff_view_init: initialises scroll context dv_left"
_setup_diff
shellframe_diff_view_init
_top=""
shellframe_scroll_top "dv_left" _top
assert_eq "0" "$_top" "dv_left scroll top = 0"

ptyunit_test_begin "diff_view_init: initialises scroll context dv_right"
_setup_diff
shellframe_diff_view_init
_top=""
shellframe_scroll_top "dv_right" _top
assert_eq "0" "$_top" "dv_right scroll top = 0"

ptyunit_test_begin "diff_view_init: sync scroll context dv_sync locks dv_left/right"
_setup_diff
shellframe_diff_view_init
shellframe_sync_scroll_locked "dv_sync"
assert_eq "0" "$?" "dv_sync is locked (returns 0)"

# ── shellframe_diff_view_on_key ──────────────────────────────────────────────

ptyunit_test_begin "diff_view_on_key: Down scrolls dv_left down"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "$SHELLFRAME_KEY_DOWN"
assert_eq "0" "$?" "Down returns 0 (handled)"
_top=""
shellframe_scroll_top "dv_left" _top
assert_eq "3" "$_top" "scrolled down by 3"

ptyunit_test_begin "diff_view_on_key: Up scrolls dv_left up"
_setup_diff
shellframe_diff_view_init
shellframe_sync_scroll_move "dv_sync" "dv_left" "down" 3
shellframe_diff_view_on_key "$SHELLFRAME_KEY_UP"
assert_eq "0" "$?" "Up returns 0 (handled)"
_top=""
shellframe_scroll_top "dv_left" _top
assert_eq "0" "$_top" "scrolled back to top"

ptyunit_test_begin "diff_view_on_key: Home scrolls to top"
_setup_diff
shellframe_diff_view_init
shellframe_sync_scroll_move "dv_sync" "dv_left" "down" 3
shellframe_diff_view_on_key "$SHELLFRAME_KEY_HOME"
assert_eq "0" "$?" "Home returns 0"
_top=""
shellframe_scroll_top "dv_left" _top
assert_eq "0" "$_top" "back at top"

ptyunit_test_begin "diff_view_on_key: Page Up handled"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "$SHELLFRAME_KEY_PAGE_UP"
assert_eq "0" "$?" "Page Up returns 0"

ptyunit_test_begin "diff_view_on_key: Page Down handled"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "$SHELLFRAME_KEY_PAGE_DOWN"
assert_eq "0" "$?" "Page Down returns 0"

ptyunit_test_begin "diff_view_on_key: End handled"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "$SHELLFRAME_KEY_END"
assert_eq "0" "$?" "End returns 0"

ptyunit_test_begin "diff_view_on_key: unhandled key returns 1"
_setup_diff
shellframe_diff_view_init
shellframe_diff_view_on_key "x"
assert_eq "1" "$?" "x returns 1 (not handled)"

# ── shellframe_diff_view_on_focus ────────────────────────────────────────────

ptyunit_test_begin "diff_view_on_focus: sets FOCUSED=1"
SHELLFRAME_DIFF_VIEW_FOCUSED=0
shellframe_diff_view_on_focus 1
assert_eq "1" "$SHELLFRAME_DIFF_VIEW_FOCUSED" "FOCUSED=1"

ptyunit_test_begin "diff_view_on_focus: sets FOCUSED=0"
SHELLFRAME_DIFF_VIEW_FOCUSED=1
shellframe_diff_view_on_focus 0
assert_eq "0" "$SHELLFRAME_DIFF_VIEW_FOCUSED" "FOCUSED=0"

ptyunit_test_summary
