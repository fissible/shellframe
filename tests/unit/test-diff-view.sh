#!/usr/bin/env bash
# tests/unit/test-diff-view.sh — Unit tests for src/widgets/diff-view.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

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

# Full diff covering all row types for render tests
_setup_render_diff() {
    SHELLFRAME_DIFF_TYPES=("hdr" "file_sep" "ctx" "add" "del" "chg" "sep")
    SHELLFRAME_DIFF_LEFT=("src/old.sh" "" "context line" "" "deleted line" "old version" "")
    SHELLFRAME_DIFF_RIGHT=("src/new.sh" "" "context line" "added line" "" "new version" "")
    SHELLFRAME_DIFF_LNUMS=("" "" "10" "" "12" "14" "")
    SHELLFRAME_DIFF_RNUMS=("" "" "10" "11" "" "13" "")
    SHELLFRAME_DIFF_ROW_COUNT=7
    SHELLFRAME_DIFF_FILE_ROWS=(0)
    SHELLFRAME_DIFF_FILE_STATUS=("modified")
    SHELLFRAME_DIFF_VIEW_HIDE_FILE_HDR=0
    SHELLFRAME_DIFF_VIEW_HL_ENABLED=0
    SHELLFRAME_DIFF_VIEW_LEFT_FOOTER=""
    SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER=""
    SHELLFRAME_DIFF_VIEW_LEFT_DATE=""
    SHELLFRAME_DIFF_VIEW_RIGHT_DATE=""
}

# Helper: call a render fn with fd 3 → temp file; return ANSI-stripped output.
# Usage: _c=$(_dv_capture fn arg...)
_dv_capture() {
    local _fn="$1"; shift
    local _f
    _f=$(mktemp "${TMPDIR:-/tmp}/sf-test-dv.XXXXXX")
    exec 3>"$_f"
    "$_fn" "$@"
    exec 3>&- 2>/dev/null || true
    sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_f"
    rm -f "$_f"
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

# ── _shellframe_dv_clip_ansi ─────────────────────────────────────────────────

ptyunit_test_begin "dv_clip_ansi: clips plain text to max width"
_shellframe_dv_clip_ansi "hello world" 5 _r
assert_eq "hello" "$_r"

ptyunit_test_begin "dv_clip_ansi: returns full string when shorter than max"
_shellframe_dv_clip_ansi "hi" 10 _r
assert_eq "hi" "$_r"

ptyunit_test_begin "dv_clip_ansi: empty string yields empty result"
_shellframe_dv_clip_ansi "" 5 _r
assert_eq "" "$_r"

ptyunit_test_begin "dv_clip_ansi: ANSI escape is zero-width"
_shellframe_dv_clip_ansi $'\033[31mhello\033[0m' 3 _r
assert_contains "$_r" $'\033[31m'
assert_not_contains "$_r" "lo"

# ── _shellframe_dv_render_pane ───────────────────────────────────────────────

ptyunit_test_begin "dv_render_pane: ctx row text visible on left pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "context line"

ptyunit_test_begin "dv_render_pane: ctx row line number visible on left pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "10"

ptyunit_test_begin "dv_render_pane: add row is blank on left pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_not_contains "$_c" "added line"

ptyunit_test_begin "dv_render_pane: add row shows content on right pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "right")
assert_contains "$_c" "added line"

ptyunit_test_begin "dv_render_pane: del row shows content on left pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "deleted line"

ptyunit_test_begin "dv_render_pane: del row is blank on right pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "right")
assert_not_contains "$_c" "deleted line"

ptyunit_test_begin "dv_render_pane: chg row shows old content on left pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "old version"

ptyunit_test_begin "dv_render_pane: chg row shows new content on right pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "right")
assert_contains "$_c" "new version"

ptyunit_test_begin "dv_render_pane: hdr row shows filename on left pane"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "src/old.sh"

ptyunit_test_begin "dv_render_pane: file_sep row renders horizontal rule"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "─"

ptyunit_test_begin "dv_render_pane: sep row shows separator marker"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "···"

ptyunit_test_begin "dv_render_pane: HIDE_FILE_HDR suppresses filename in hdr row"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_HIDE_FILE_HDR=1
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_not_contains "$_c" "src/old.sh"
SHELLFRAME_DIFF_VIEW_HIDE_FILE_HDR=0

ptyunit_test_begin "dv_render_pane: HIDE_FILE_HDR suppresses file_sep rule"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_HIDE_FILE_HDR=1
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_not_contains "$_c" "─"
SHELLFRAME_DIFF_VIEW_HIDE_FILE_HDR=0

# ── shellframe_diff_view_render ──────────────────────────────────────────────

ptyunit_test_begin "diff_view_render: renders ctx content in output"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture shellframe_diff_view_render 1 1 80 10)
assert_contains "$_c" "context line"

ptyunit_test_begin "diff_view_render: renders footer text when LEFT_FOOTER is set"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER="main (abc123)"
shellframe_diff_view_init
_c=$(_dv_capture shellframe_diff_view_render 1 1 80 10)
assert_contains "$_c" "main (abc123)"
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER=""

# ── shellframe_diff_view_render_side ─────────────────────────────────────────

ptyunit_test_begin "diff_view_render_side: left side renders content"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture shellframe_diff_view_render_side 1 1 40 10 "left")
assert_contains "$_c" "context line"

ptyunit_test_begin "diff_view_render_side: left side with footer shows footer text"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER="feature/test"
shellframe_diff_view_init
_c=$(_dv_capture shellframe_diff_view_render_side 1 1 40 10 "left")
assert_contains "$_c" "feature/test"
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER=""

ptyunit_test_begin "diff_view_render_side: right side renders content"
_setup_render_diff
shellframe_diff_view_init
_c=$(_dv_capture shellframe_diff_view_render_side 1 1 40 10 "right")
assert_contains "$_c" "context line"

ptyunit_test_begin "diff_view_render_side: right side with footer shows footer text"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER="feature/right-branch"
shellframe_diff_view_init
_c=$(_dv_capture shellframe_diff_view_render_side 1 1 40 10 "right")
assert_contains "$_c" "feature/right-branch"
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER=""

# ── Syntax highlighting ───────────────────────────────────────────────────────

ptyunit_test_begin "dv_render_pane: HL_ENABLED uses hl text instead of plain on left pane"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_HL_ENABLED=1
SHELLFRAME_DIFF_VIEW_HL_LEFT=("" "" "hl-context-left" "" "" "" "")
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "hl-context-left"
assert_not_contains "$_c" "context line"
SHELLFRAME_DIFF_VIEW_HL_ENABLED=0
SHELLFRAME_DIFF_VIEW_HL_LEFT=()

ptyunit_test_begin "dv_render_pane: HL_ENABLED uses hl text on right pane"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_HL_ENABLED=1
SHELLFRAME_DIFF_VIEW_HL_RIGHT=("" "" "hl-context-right" "" "" "" "")
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "right")
assert_contains "$_c" "hl-context-right"
SHELLFRAME_DIFF_VIEW_HL_ENABLED=0
SHELLFRAME_DIFF_VIEW_HL_RIGHT=()

# ── hdr row file status variants ─────────────────────────────────────────────

ptyunit_test_begin "dv_render_pane: hdr status=deleted shows label on left pane"
_setup_render_diff
SHELLFRAME_DIFF_FILE_STATUS=("deleted")
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_contains "$_c" "deleted"

ptyunit_test_begin "dv_render_pane: hdr status=added shows label on right pane"
_setup_render_diff
SHELLFRAME_DIFF_FILE_STATUS=("added")
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "right")
assert_contains "$_c" "added"

ptyunit_test_begin "dv_render_pane: hdr status=added shows no label on left pane"
_setup_render_diff
SHELLFRAME_DIFF_FILE_STATUS=("added")
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "left")
assert_not_contains "$_c" "added"

ptyunit_test_begin "dv_render_pane: hdr status=deleted shows no label on right pane"
_setup_render_diff
SHELLFRAME_DIFF_FILE_STATUS=("deleted")
shellframe_diff_view_init
_c=$(_dv_capture _shellframe_dv_render_pane 1 1 40 10 "right")
assert_not_contains "$_c" "deleted"

# ── render footer variants ────────────────────────────────────────────────────

ptyunit_test_begin "diff_view_render: RIGHT_FOOTER renders in footer"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER="feature/right"
shellframe_diff_view_init
_c=$(_dv_capture shellframe_diff_view_render 1 1 80 10)
assert_contains "$_c" "feature/right"
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER=""

ptyunit_test_begin "diff_view_render: LEFT_DATE renders in footer"
_setup_render_diff
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER="main"
SHELLFRAME_DIFF_VIEW_LEFT_DATE="2026-01-01"
shellframe_diff_view_init
_c=$(_dv_capture shellframe_diff_view_render 1 1 80 10)
assert_contains "$_c" "2026-01-01"
SHELLFRAME_DIFF_VIEW_LEFT_FOOTER=""
SHELLFRAME_DIFF_VIEW_LEFT_DATE=""

ptyunit_test_summary
