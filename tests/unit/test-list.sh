#!/usr/bin/env bash
# tests/unit/test-list.sh — Unit tests for src/widgets/list.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/selection.sh"
source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/widgets/list.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# ── Setup helpers ─────────────────────────────────────────────────────────────

SHELLFRAME_LIST_ITEMS=("Alpha" "Beta" "Gamma" "Delta")
SHELLFRAME_LIST_CTX="lst"

_reset_list() {
    SHELLFRAME_LIST_CTX="lst"
    SHELLFRAME_LIST_MULTISELECT=0
    shellframe_list_init "lst" 10
}

# ── shellframe_list_init ──────────────────────────────────────────────────────

ptyunit_test_begin "list_init: cursor starts at 0"
_reset_list
assert_output "0" shellframe_sel_cursor "lst"

ptyunit_test_begin "list_init: scroll top starts at 0"
_reset_list
assert_output "0" shellframe_scroll_top "lst"

ptyunit_test_begin "list_init: reinit resets cursor to 0"
_reset_list
shellframe_sel_move "lst" down
shellframe_list_init "lst" 10
assert_output "0" shellframe_sel_cursor "lst"

# ── shellframe_list_on_key: navigation ───────────────────────────────────────

ptyunit_test_begin "list_on_key: down moves cursor, returns 0"
_reset_list
shellframe_list_on_key $'\033[B'
assert_eq "0" "$?" "down returns 0"
assert_output "1" shellframe_sel_cursor "lst"

ptyunit_test_begin "list_on_key: up moves cursor, returns 0"
_reset_list
shellframe_list_on_key $'\033[B'   # cursor → 1
shellframe_list_on_key $'\033[B'   # cursor → 2
shellframe_list_on_key $'\033[A'   # cursor → 1
assert_eq "0" "$?" "up returns 0"
assert_output "1" shellframe_sel_cursor "lst"

ptyunit_test_begin "list_on_key: up at top clamps at 0"
_reset_list
shellframe_list_on_key $'\033[A'
assert_output "0" shellframe_sel_cursor "lst"

ptyunit_test_begin "list_on_key: down at bottom clamps at last item"
_reset_list
shellframe_list_on_key $'\033[B'
shellframe_list_on_key $'\033[B'
shellframe_list_on_key $'\033[B'
shellframe_list_on_key $'\033[B'   # 4 downs on a 4-item list → clamps at 3
assert_output "3" shellframe_sel_cursor "lst"

ptyunit_test_begin "list_on_key: home moves cursor to 0"
_reset_list
shellframe_list_on_key $'\033[B'   # cursor → 1
shellframe_list_on_key $'\033[B'   # cursor → 2
shellframe_list_on_key $'\033[H'
assert_eq "0" "$?" "home returns 0"
assert_output "0" shellframe_sel_cursor "lst"

ptyunit_test_begin "list_on_key: end moves cursor to last"
_reset_list
shellframe_list_on_key $'\033[F'
assert_eq "0" "$?" "end returns 0"
assert_output "3" shellframe_sel_cursor "lst"

# ── shellframe_list_on_key: page up / down ────────────────────────────────────

ptyunit_test_begin "list_on_key: page_down moves by viewport rows"
SHELLFRAME_LIST_ITEMS=("A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L")
SHELLFRAME_LIST_CTX="pg"
shellframe_list_init "pg" 4   # viewport = 4 rows
shellframe_list_on_key $'\033[6~'
assert_eq "0" "$?" "page_down returns 0"
assert_output "4" shellframe_sel_cursor "pg"

ptyunit_test_begin "list_on_key: page_up moves by viewport rows"
shellframe_sel_init "pg" 12   # reset cursor to 0
shellframe_sel_move "pg" end   # cursor → 11
shellframe_list_on_key $'\033[5~'
assert_eq "0" "$?" "page_up returns 0"
assert_output "7" shellframe_sel_cursor "pg"   # 11 - 4 = 7

# Restore for subsequent tests
SHELLFRAME_LIST_ITEMS=("Alpha" "Beta" "Gamma" "Delta")
SHELLFRAME_LIST_CTX="lst"

# ── shellframe_list_on_key: Enter ─────────────────────────────────────────────

ptyunit_test_begin "list_on_key: Enter (\\r) returns 2"
_reset_list
shellframe_list_on_key $'\r'
assert_eq "2" "$?" "Enter returns 2"

ptyunit_test_begin "list_on_key: Enter (\\n) returns 2"
_reset_list
shellframe_list_on_key $'\n'
assert_eq "2" "$?" "Enter (newline) returns 2"

# ── shellframe_list_on_key: multiselect ───────────────────────────────────────

ptyunit_test_begin "list_on_key: space toggles when multiselect=1"
_reset_list
SHELLFRAME_LIST_MULTISELECT=1
shellframe_list_on_key " "
assert_eq "0" "$?" "space returns 0"
assert_output "1" shellframe_sel_selected_count "lst"

ptyunit_test_begin "list_on_key: space untoggles when multiselect=1"
# state from previous test: item 0 is selected, multiselect=1
shellframe_list_on_key " "
assert_output "0" shellframe_sel_selected_count "lst"

ptyunit_test_begin "list_on_key: space not handled when multiselect=0"
_reset_list
SHELLFRAME_LIST_MULTISELECT=0
shellframe_list_on_key " "
assert_eq "1" "$?" "space returns 1 without multiselect"

# ── shellframe_list_on_key: unhandled ─────────────────────────────────────────

ptyunit_test_begin "list_on_key: unhandled key returns 1"
_reset_list
shellframe_list_on_key "x"
assert_eq "1" "$?" "unhandled key returns 1"

ptyunit_test_begin "list_on_key: Escape returns 1"
_reset_list
shellframe_list_on_key $'\033'
assert_eq "1" "$?" "escape returns 1"

# ── shellframe_list_on_focus ──────────────────────────────────────────────────

ptyunit_test_begin "list_on_focus: sets FOCUSED=1"
SHELLFRAME_LIST_FOCUSED=0
shellframe_list_on_focus 1
assert_eq "1" "$SHELLFRAME_LIST_FOCUSED" "focused set to 1"

ptyunit_test_begin "list_on_focus: sets FOCUSED=0"
SHELLFRAME_LIST_FOCUSED=1
shellframe_list_on_focus 0
assert_eq "0" "$SHELLFRAME_LIST_FOCUSED" "focused set to 0"

# ── shellframe_list_size ───────────────────────────────────────────────────────

ptyunit_test_begin "list_size: returns 1 1 0 0"
assert_output "1 1 0 0" shellframe_list_size

# ── shellframe_list_render ─────────────────────────────────────────────────────

# Render list to a temp file, strip ANSI, return plain text
_render_list() {
    local _top="${1:-1}" _left="${2:-1}" _width="${3:-20}" _height="${4:-5}"
    local _out
    _out=$(mktemp "${TMPDIR:-/tmp}/sf-test-list.XXXXXX")
    trap '{ exec 3>&- 2>/dev/null || true; rm -f "$_out"; }' RETURN
    exec 3>"$_out"
    shellframe_list_render "$_top" "$_left" "$_width" "$_height"
    exec 3>&-
    sed 's/\033\[[0-9;]*m//g; s/\033\[[0-9;]*[A-Za-z]//g' "$_out"
}

ptyunit_test_begin "list_render: items appear in output"
SHELLFRAME_LIST_ITEMS=("Alpha" "Beta" "Gamma" "Delta")
SHELLFRAME_LIST_CTX="lst"
_reset_list
_out=$(_render_list 1 1 20 4)
assert_contains "$_out" "Alpha" "first item present"
assert_contains "$_out" "Beta" "second item present"

ptyunit_test_begin "list_render: items beyond height not shown"
SHELLFRAME_LIST_ITEMS=("Alpha" "Beta" "Gamma" "Delta")
SHELLFRAME_LIST_CTX="lst"
_reset_list
_out=$(_render_list 1 1 20 2)
assert_contains "$_out" "Alpha" "item 0 visible"
assert_not_contains "$_out" "Gamma" "item 2 beyond height"

ptyunit_test_begin "list_render: multiselect shows checked prefix"
SHELLFRAME_LIST_ITEMS=("Alpha" "Beta" "Gamma" "Delta")
SHELLFRAME_LIST_CTX="lst"
_reset_list
SHELLFRAME_LIST_MULTISELECT=1
shellframe_list_on_key " "   # toggle item 0 selected
_out=$(_render_list 1 1 20 4)
assert_contains "$_out" "[x]" "selected item has [x]"
assert_contains "$_out" "[ ]" "unselected item has [ ]"

ptyunit_test_begin "list_render: no checkboxes in single-select mode"
SHELLFRAME_LIST_ITEMS=("Alpha" "Beta" "Gamma" "Delta")
SHELLFRAME_LIST_CTX="lst"
_reset_list
SHELLFRAME_LIST_MULTISELECT=0
_out=$(_render_list 1 1 20 4)
assert_not_contains "$_out" "[x]" "no [x] in single-select"
assert_not_contains "$_out" "[ ]" "no [ ] in single-select"

# ── Dirty-region integration ──────────────────────────────────────────────────
# shellframe_shell_mark_dirty is defined in shell.sh; stub it here so list.sh
# can be tested in isolation without sourcing the full shell module.

_SHELLFRAME_SHELL_DIRTY=0
shellframe_shell_mark_dirty() { _SHELLFRAME_SHELL_DIRTY=1; }

ptyunit_test_begin "list_on_key: marks dirty on recognized navigation key"
_reset_list
_SHELLFRAME_SHELL_DIRTY=0
shellframe_list_on_key $'\033[B' || true   # Down
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "dirty set on Down key"

ptyunit_test_begin "list_on_key: marks dirty on Enter (rc=2)"
_reset_list
_SHELLFRAME_SHELL_DIRTY=0
shellframe_list_on_key $'\r' || true   # Enter → rc 2
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "dirty set on Enter"

ptyunit_test_begin "list_on_key: does not mark dirty on unrecognized key"
_reset_list
_SHELLFRAME_SHELL_DIRTY=0
shellframe_list_on_key "X" || true   # unrecognized → rc 1
assert_eq "0" "$_SHELLFRAME_SHELL_DIRTY" "dirty not set on unrecognized key"

ptyunit_test_summary
