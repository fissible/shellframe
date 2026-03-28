#!/usr/bin/env bash
# tests/unit/test-context-menu.sh — Unit tests for src/widgets/context-menu.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/selection.sh"
source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/panel.sh"
source "$SHELLFRAME_DIR/src/widgets/context-menu.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# ── Stub shell.sh dependency ─────────────────────────────────────────────────
_SHELLFRAME_SHELL_DIRTY=0
shellframe_shell_mark_dirty() { _SHELLFRAME_SHELL_DIRTY=1; }

# ── Setup helpers ─────────────────────────────────────────────────────────────

SHELLFRAME_CMENU_ITEMS=("Open" "Copy" "Delete" "Export")
SHELLFRAME_CMENU_CTX="cm"
_rc=0
_mt=0; _ml=0; _mw=0; _mh=0
_c=0; _cell=""

_reset_cmenu() {
    SHELLFRAME_CMENU_CTX="cm"
    SHELLFRAME_CMENU_ANCHOR_ROW=5
    SHELLFRAME_CMENU_ANCHOR_COL=10
    SHELLFRAME_CMENU_FOCUSED=1
    SHELLFRAME_CMENU_STYLE="single"
    SHELLFRAME_CMENU_MAX_HEIGHT=10
    SHELLFRAME_CMENU_BG=""
    SHELLFRAME_CMENU_RESULT=-1
    SHELLFRAME_CMENU_ITEMS=("Open" "Copy" "Delete" "Export")
    shellframe_cmenu_init "cm"
    _SHELLFRAME_SHELL_DIRTY=0
}

# ── shellframe_cmenu_init ───────────────────────────────────────────────────

ptyunit_test_begin "cmenu_init: cursor starts at 0"
_reset_cmenu
assert_output "0" shellframe_sel_cursor "cm"

ptyunit_test_begin "cmenu_init: scroll top starts at 0"
_reset_cmenu
assert_output "0" shellframe_scroll_top "cm"

ptyunit_test_begin "cmenu_init: resets selection count"
_reset_cmenu
assert_output "4" shellframe_sel_count "cm"

# ── _shellframe_cmenu_dims ──────────────────────────────────────────────────

ptyunit_test_begin "cmenu_dims: menu positioned at anchor"
_reset_cmenu
_shellframe_cmenu_dims 1 1 80 24 _mt _ml _mw _mh
assert_eq "5" "$_mt"
assert_eq "10" "$_ml"

ptyunit_test_begin "cmenu_dims: width based on longest item + 4"
_reset_cmenu
_shellframe_cmenu_dims 1 1 80 24 _mt _ml _mw _mh
assert_eq "10" "$_mw"

ptyunit_test_begin "cmenu_dims: height = items + 2 borders"
_reset_cmenu
_shellframe_cmenu_dims 1 1 80 24 _mt _ml _mw _mh
assert_eq "6" "$_mh"

ptyunit_test_begin "cmenu_dims: shifts up when overflowing bottom"
_reset_cmenu
SHELLFRAME_CMENU_ANCHOR_ROW=22
_shellframe_cmenu_dims 1 1 80 24 _mt _ml _mw _mh
assert_eq "19" "$_mt"

ptyunit_test_begin "cmenu_dims: shifts left when overflowing right"
_reset_cmenu
SHELLFRAME_CMENU_ANCHOR_COL=75
_shellframe_cmenu_dims 1 1 80 24 _mt _ml _mw _mh
assert_eq "71" "$_ml"

ptyunit_test_begin "cmenu_dims: respects max_height"
_reset_cmenu
SHELLFRAME_CMENU_MAX_HEIGHT=2
SHELLFRAME_CMENU_ITEMS=("A" "B" "C" "D" "E")
shellframe_cmenu_init "cm"
_shellframe_cmenu_dims 1 1 80 24 _mt _ml _mw _mh
assert_eq "4" "$_mh"

# ── shellframe_cmenu_on_key ──────────────────────────────────────────────────

ptyunit_test_begin "cmenu_on_key: Enter confirms with cursor index"
_reset_cmenu
shellframe_cmenu_on_key $'\r'; _rc=$?
assert_eq "2" "$_rc"
assert_eq "0" "$SHELLFRAME_CMENU_RESULT"

ptyunit_test_begin "cmenu_on_key: Esc dismisses with -1"
_reset_cmenu
shellframe_cmenu_on_key $'\033'; _rc=$?
assert_eq "2" "$_rc"
assert_eq "-1" "$SHELLFRAME_CMENU_RESULT"

ptyunit_test_begin "cmenu_on_key: Down moves cursor to 1"
_reset_cmenu
shellframe_cmenu_on_key $'\033[B'; _rc=$?
assert_eq "0" "$_rc"
shellframe_sel_cursor "cm" _c
assert_eq "1" "$_c"

ptyunit_test_begin "cmenu_on_key: Up at 0 stays at 0"
_reset_cmenu
shellframe_cmenu_on_key $'\033[A'; _rc=$?
assert_eq "0" "$_rc"
shellframe_sel_cursor "cm" _c
assert_eq "0" "$_c"

ptyunit_test_begin "cmenu_on_key: Down then Enter confirms index 1"
_reset_cmenu
shellframe_cmenu_on_key $'\033[B'
shellframe_cmenu_on_key $'\r'
assert_eq "1" "$SHELLFRAME_CMENU_RESULT"

ptyunit_test_begin "cmenu_on_key: Home goes to first item"
_reset_cmenu
shellframe_sel_set "cm" 3
shellframe_cmenu_on_key $'\033[H'
shellframe_sel_cursor "cm" _c
assert_eq "0" "$_c"

ptyunit_test_begin "cmenu_on_key: End goes to last item"
_reset_cmenu
shellframe_cmenu_on_key $'\033[F'
shellframe_sel_cursor "cm" _c
assert_eq "3" "$_c"

ptyunit_test_begin "cmenu_on_key: unhandled key returns 1"
_reset_cmenu
shellframe_cmenu_on_key "x"; _rc=$?
assert_eq "1" "$_rc"

ptyunit_test_begin "cmenu_on_key: marks dirty on navigation"
_reset_cmenu
_SHELLFRAME_SHELL_DIRTY=0
shellframe_cmenu_on_key $'\033[B'
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY"

# ── shellframe_cmenu_on_mouse ───────────────────────────────────────────────

ptyunit_test_begin "cmenu_on_mouse: click on first item confirms it"
_reset_cmenu
shellframe_cmenu_on_mouse 0 "press" 6 11 1 1 80 24; _rc=$?
assert_eq "2" "$_rc"
assert_eq "0" "$SHELLFRAME_CMENU_RESULT"

ptyunit_test_begin "cmenu_on_mouse: click on second item confirms index 1"
_reset_cmenu
shellframe_cmenu_on_mouse 0 "press" 7 11 1 1 80 24; _rc=$?
assert_eq "2" "$_rc"
assert_eq "1" "$SHELLFRAME_CMENU_RESULT"

ptyunit_test_begin "cmenu_on_mouse: click outside dismisses"
_reset_cmenu
shellframe_cmenu_on_mouse 0 "press" 1 1 1 1 80 24; _rc=$?
assert_eq "2" "$_rc"
assert_eq "-1" "$SHELLFRAME_CMENU_RESULT"

ptyunit_test_begin "cmenu_on_mouse: scroll up within menu"
_reset_cmenu
SHELLFRAME_CMENU_MAX_HEIGHT=2
SHELLFRAME_CMENU_ITEMS=("A" "B" "C" "D")
shellframe_cmenu_init "cm"
shellframe_cmenu_on_mouse 65 "press" 6 11 1 1 80 24
shellframe_cmenu_on_mouse 64 "press" 6 11 1 1 80 24; _rc=$?
assert_eq "0" "$_rc"

ptyunit_test_begin "cmenu_on_mouse: release events ignored"
_reset_cmenu
shellframe_cmenu_on_mouse 0 "release" 6 11 1 1 80 24; _rc=$?
assert_eq "0" "$_rc"

# ── shellframe_cmenu_on_focus ───────────────────────────────────────────────

ptyunit_test_begin "cmenu_on_focus: sets FOCUSED to 1"
SHELLFRAME_CMENU_FOCUSED=0
shellframe_cmenu_on_focus 1
assert_eq "1" "$SHELLFRAME_CMENU_FOCUSED"

ptyunit_test_begin "cmenu_on_focus: sets FOCUSED to 0"
shellframe_cmenu_on_focus 0
assert_eq "0" "$SHELLFRAME_CMENU_FOCUSED"

# ── shellframe_cmenu_size ───────────────────────────────────────────────────

ptyunit_test_begin "cmenu_size: reports correct dimensions"
_reset_cmenu
assert_output "10 3 10 6" shellframe_cmenu_size

ptyunit_test_begin "cmenu_size: adjusts to longer items"
SHELLFRAME_CMENU_ITEMS=("A very long menu item")
assert_output "25 3 25 3" shellframe_cmenu_size

# ── shellframe_cmenu_render (smoke test) ────────────────────────────────────

ptyunit_test_begin "cmenu_render: runs without error"
_reset_cmenu
shellframe_fb_frame_start 24 80
shellframe_cmenu_render 1 1 80 24; _rc=$?
assert_eq "0" "$_rc"

ptyunit_test_begin "cmenu_render: dirty array tracks rendered cells"
_reset_cmenu
shellframe_fb_frame_start 24 80
shellframe_cmenu_render 1 1 80 24
# Row 5 should have dirty cells from the panel border
assert_not_eq "0" "${_SF_FRAME_DIRTY[5]:-0}"

ptyunit_test_summary
