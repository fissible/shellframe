#!/usr/bin/env bash
# tests/unit/test-tab-bar.sh — Unit tests for src/widgets/tab-bar.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/widgets/tab-bar.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

SHELLFRAME_TABBAR_LABELS=("Files" "Edit" "View")

# ── shellframe_tabbar_on_key: left arrow ──────────────────────────────────────

ptyunit_test_begin "tabbar_on_key: left decrements active"
SHELLFRAME_TABBAR_ACTIVE=1
shellframe_tabbar_on_key $'\033[D'
assert_eq "0" "$SHELLFRAME_TABBAR_ACTIVE" "active decremented to 0"

ptyunit_test_begin "tabbar_on_key: left clamps at 0"
SHELLFRAME_TABBAR_ACTIVE=0
shellframe_tabbar_on_key $'\033[D'
assert_eq "0" "$SHELLFRAME_TABBAR_ACTIVE" "active stays at 0"

ptyunit_test_begin "tabbar_on_key: left returns 0 (handled)"
SHELLFRAME_TABBAR_ACTIVE=1
shellframe_tabbar_on_key $'\033[D'
assert_eq "0" "$?" "left arrow returns 0"

# ── shellframe_tabbar_on_key: right arrow ─────────────────────────────────────

ptyunit_test_begin "tabbar_on_key: right increments active"
SHELLFRAME_TABBAR_ACTIVE=0
shellframe_tabbar_on_key $'\033[C'
assert_eq "1" "$SHELLFRAME_TABBAR_ACTIVE" "active incremented to 1"

ptyunit_test_begin "tabbar_on_key: right clamps at last tab"
SHELLFRAME_TABBAR_ACTIVE=2
shellframe_tabbar_on_key $'\033[C'
assert_eq "2" "$SHELLFRAME_TABBAR_ACTIVE" "active stays at 2"

ptyunit_test_begin "tabbar_on_key: right returns 0 (handled)"
SHELLFRAME_TABBAR_ACTIVE=0
shellframe_tabbar_on_key $'\033[C'
assert_eq "0" "$?" "right arrow returns 0"

# ── shellframe_tabbar_on_key: unhandled ───────────────────────────────────────

ptyunit_test_begin "tabbar_on_key: unhandled key returns 1"
shellframe_tabbar_on_key "x"
assert_eq "1" "$?" "unhandled key returns 1"

ptyunit_test_begin "tabbar_on_key: Enter returns 1 (not handled by tabbar)"
shellframe_tabbar_on_key $'\r'
assert_eq "1" "$?" "Enter returns 1"

# ── shellframe_tabbar_on_key: empty labels ────────────────────────────────────

ptyunit_test_begin "tabbar_on_key: empty labels array returns 1"
SHELLFRAME_TABBAR_LABELS=()
shellframe_tabbar_on_key $'\033[C'
assert_eq "1" "$?" "no labels: right returns 1"
SHELLFRAME_TABBAR_LABELS=("Files" "Edit" "View")

# ── shellframe_tabbar_on_focus ─────────────────────────────────────────────────

ptyunit_test_begin "tabbar_on_focus: sets FOCUSED=1"
SHELLFRAME_TABBAR_FOCUSED=0
shellframe_tabbar_on_focus 1
assert_eq "1" "$SHELLFRAME_TABBAR_FOCUSED" "focused set to 1"

ptyunit_test_begin "tabbar_on_focus: sets FOCUSED=0"
SHELLFRAME_TABBAR_FOCUSED=1
shellframe_tabbar_on_focus 0
assert_eq "0" "$SHELLFRAME_TABBAR_FOCUSED" "focused set to 0"

# ── shellframe_tabbar_size ─────────────────────────────────────────────────────

ptyunit_test_begin "tabbar_size: returns 3 1 0 1"
assert_output "3 1 0 1" shellframe_tabbar_size

# ── shellframe_tabbar_render: fd 3 output ────────────────────────────────────

ptyunit_test_begin "tabbar_render: renders tab labels to fd 3"
SHELLFRAME_TABBAR_LABELS=("Home" "Schema" "Query")
SHELLFRAME_TABBAR_ACTIVE=0
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 1 60
exec 3>"$_out"
shellframe_tabbar_render 1 1 60 1
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "Home"
assert_contains "$_content" "Schema"
rm -f "$_out"

ptyunit_test_begin "tabbar_render: active tab is present in output"
SHELLFRAME_TABBAR_LABELS=("Files" "Edit" "View")
SHELLFRAME_TABBAR_ACTIVE=1
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 1 60
exec 3>"$_out"
shellframe_tabbar_render 1 1 60 1
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "Edit"
rm -f "$_out"

ptyunit_test_begin "tabbar_render: empty labels array produces no label output"
SHELLFRAME_TABBAR_LABELS=()
SHELLFRAME_TABBAR_ACTIVE=0
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 1 40
exec 3>"$_out"
shellframe_tabbar_render 1 1 40 1
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_not_contains "$_content" "Home"
assert_not_contains "$_content" "Edit"
rm -f "$_out"
SHELLFRAME_TABBAR_LABELS=("Files" "Edit" "View")

ptyunit_test_begin "tabbar_render: narrow width clips tab label with ellipsis"
SHELLFRAME_TABBAR_LABELS=("LongTabLabel" "B")
SHELLFRAME_TABBAR_ACTIVE=0
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 1 6
exec 3>"$_out"
shellframe_tabbar_render 1 1 6 1
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "…"
rm -f "$_out"

ptyunit_test_begin "tabbar_render: renders separator between tabs"
SHELLFRAME_TABBAR_LABELS=("A" "B" "C")
SHELLFRAME_TABBAR_ACTIVE=0
_out=$(mktemp)
_SF_ROW_PREV=(); shellframe_fb_frame_start 1 40
exec 3>"$_out"
shellframe_tabbar_render 1 1 40 1
shellframe_screen_flush
exec 3>&-
_content=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_content" "│"
rm -f "$_out"

# ── Dirty-region integration ──────────────────────────────────────────────────
_SHELLFRAME_SHELL_DIRTY=0
shellframe_shell_mark_dirty() { _SHELLFRAME_SHELL_DIRTY=1; }

ptyunit_test_begin "tabbar_on_key: marks dirty on Right arrow"
SHELLFRAME_TABBAR_LABELS=("Files" "Edit" "View")
SHELLFRAME_TABBAR_ACTIVE=0
_SHELLFRAME_SHELL_DIRTY=0
shellframe_tabbar_on_key $'\033[C' || true   # Right arrow
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "dirty set on tab change"

ptyunit_test_begin "tabbar_on_key: does not mark dirty on unrecognized key"
SHELLFRAME_TABBAR_LABELS=("Files" "Edit" "View")
SHELLFRAME_TABBAR_ACTIVE=0
_SHELLFRAME_SHELL_DIRTY=0
shellframe_tabbar_on_key "x" || true
assert_eq "0" "$_SHELLFRAME_SHELL_DIRTY" "dirty not set on unrecognized key"

ptyunit_test_summary
