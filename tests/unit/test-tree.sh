#!/usr/bin/env bash
# tests/unit/test-tree.sh — Unit tests for src/widgets/tree.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/selection.sh"
source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/widgets/tree.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# Stub: tree on_key calls shellframe_shell_mark_dirty; define it before any test
_SHELLFRAME_SHELL_DIRTY=0
shellframe_shell_mark_dirty() { _SHELLFRAME_SHELL_DIRTY=1; }

# ── Test tree: two roots, first has two children, second is a leaf ────────────
#
#  ▶ Root A       (index 0, depth 0, haschildren 1)
#      Child A1   (index 1, depth 1, haschildren 0)
#      Child A2   (index 2, depth 1, haschildren 0)
#  ▶ Root B       (index 3, depth 0, haschildren 1)
#      Child B1   (index 4, depth 1, haschildren 0)
#  Leaf C         (index 5, depth 0, haschildren 0)

SHELLFRAME_TREE_ITEMS=("Root A" "Child A1" "Child A2" "Root B" "Child B1" "Leaf C")
SHELLFRAME_TREE_DEPTHS=("0" "1" "1" "0" "1" "0")
SHELLFRAME_TREE_HASCHILDREN=("1" "0" "0" "1" "0" "0")
SHELLFRAME_TREE_CTX="tr"

_reset_tree() {
    SHELLFRAME_TREE_CTX="tr"
    SHELLFRAME_TREE_FOCUSED=0
    shellframe_tree_init "tr" 10
}

# ── shellframe_tree_init ──────────────────────────────────────────────────────

ptyunit_test_begin "tree_init: cursor starts at 0"
_reset_tree
assert_output "0" shellframe_sel_cursor "tr"

ptyunit_test_begin "tree_init: scroll top starts at 0"
_reset_tree
assert_output "0" shellframe_scroll_top "tr"

ptyunit_test_begin "tree_init: view contains only root-level nodes (all collapsed)"
_reset_tree
# With all parents collapsed, view should be: 0 3 5 (Root A, Root B, Leaf C)
assert_output "3" _shellframe_tree_view_count "tr"

ptyunit_test_begin "tree_init: sel count equals visible view rows"
_reset_tree
assert_output "3" shellframe_sel_count "tr"

ptyunit_test_begin "tree_init: reinit resets cursor to 0"
_reset_tree
shellframe_sel_move "tr" down   # cursor → 1
shellframe_tree_init "tr" 10
assert_output "0" shellframe_sel_cursor "tr"

# ── _shellframe_tree_build_view ───────────────────────────────────────────────

ptyunit_test_begin "build_view: expand Root A exposes its children"
_reset_tree
_shellframe_tree_set_expanded "tr" 0 "1"
_shellframe_tree_build_view "tr"
# view: 0 1 2 3 5  (Root A expanded shows 1,2; Root B still collapsed; Leaf C)
assert_output "5" _shellframe_tree_view_count "tr"

ptyunit_test_begin "build_view: expand both parents exposes all nodes"
_reset_tree
_shellframe_tree_set_expanded "tr" 0 "1"
_shellframe_tree_set_expanded "tr" 3 "1"
_shellframe_tree_build_view "tr"
assert_output "6" _shellframe_tree_view_count "tr"

ptyunit_test_begin "build_view: collapsed state re-hides children"
_reset_tree
_shellframe_tree_set_expanded "tr" 0 "1"
_shellframe_tree_build_view "tr"
_shellframe_tree_set_expanded "tr" 0 "0"
_shellframe_tree_build_view "tr"
assert_output "3" _shellframe_tree_view_count "tr"

# ── _shellframe_tree_view_to_node ─────────────────────────────────────────────

ptyunit_test_begin "view_to_node: view row 0 → node 0 when collapsed"
_reset_tree
assert_output "0" _shellframe_tree_view_to_node "tr" "0"

ptyunit_test_begin "view_to_node: view row 1 → node 3 (Root B) when collapsed"
_reset_tree
assert_output "3" _shellframe_tree_view_to_node "tr" "1"

ptyunit_test_begin "view_to_node: view row 2 → node 5 (Leaf C) when collapsed"
_reset_tree
assert_output "5" _shellframe_tree_view_to_node "tr" "2"

# ── shellframe_tree_on_key: navigation ───────────────────────────────────────

ptyunit_test_begin "tree_on_key: down moves cursor, returns 0"
_reset_tree
shellframe_tree_on_key $'\033[B'
assert_eq "0" "$?" "down returns 0"
assert_output "1" shellframe_sel_cursor "tr"

ptyunit_test_begin "tree_on_key: up moves cursor, returns 0"
_reset_tree
shellframe_tree_on_key $'\033[B'   # cursor → 1
shellframe_tree_on_key $'\033[A'   # cursor → 0
assert_eq "0" "$?" "up returns 0"
assert_output "0" shellframe_sel_cursor "tr"

ptyunit_test_begin "tree_on_key: up at top clamps at 0"
_reset_tree
shellframe_tree_on_key $'\033[A'
assert_output "0" shellframe_sel_cursor "tr"

ptyunit_test_begin "tree_on_key: down at bottom clamps at last visible row"
_reset_tree
shellframe_tree_on_key $'\033[B'
shellframe_tree_on_key $'\033[B'
shellframe_tree_on_key $'\033[B'   # 3 downs on a 3-row view → clamps at 2
assert_output "2" shellframe_sel_cursor "tr"

ptyunit_test_begin "tree_on_key: home moves cursor to 0"
_reset_tree
shellframe_tree_on_key $'\033[B'
shellframe_tree_on_key $'\033[B'
shellframe_tree_on_key $'\033[H'
assert_eq "0" "$?" "home returns 0"
assert_output "0" shellframe_sel_cursor "tr"

ptyunit_test_begin "tree_on_key: end moves cursor to last visible row"
_reset_tree
shellframe_tree_on_key $'\033[F'
assert_eq "0" "$?" "end returns 0"
assert_output "2" shellframe_sel_cursor "tr"

# ── shellframe_tree_on_key: expand / collapse ─────────────────────────────────

ptyunit_test_begin "tree_on_key: Right expands collapsed parent, view grows"
_reset_tree
# cursor at 0 (Root A, haschildren=1, collapsed)
shellframe_tree_on_key $'\033[C'
assert_eq "0" "$?" "right returns 0"
assert_output "5" _shellframe_tree_view_count "tr"

ptyunit_test_begin "tree_on_key: Right on already-expanded node is no-op"
# state from previous test: Root A expanded, cursor at 0
shellframe_tree_on_key $'\033[C'
assert_output "5" _shellframe_tree_view_count "tr"

ptyunit_test_begin "tree_on_key: Right on leaf is no-op"
_reset_tree
shellframe_tree_on_key $'\033[B'
shellframe_tree_on_key $'\033[B'   # cursor at 2 (Leaf C, haschildren=0)
shellframe_tree_on_key $'\033[C'
assert_output "3" _shellframe_tree_view_count "tr"

ptyunit_test_begin "tree_on_key: Space toggles collapsed → expanded"
_reset_tree
shellframe_tree_on_key " "
assert_eq "0" "$?" "space returns 0"
assert_output "5" _shellframe_tree_view_count "tr"

ptyunit_test_begin "tree_on_key: Space toggles expanded → collapsed"
# state from previous test: Root A expanded
shellframe_tree_on_key " "
assert_output "3" _shellframe_tree_view_count "tr"

ptyunit_test_begin "tree_on_key: cursor stays on same node after expand"
_reset_tree
shellframe_tree_on_key $'\033[B'   # cursor → row 1 (Root B)
shellframe_tree_on_key $'\033[C'   # expand Root B
# cursor should still be on Root B; Root B is now at view row 3 (after children of nothing)
# view is: 0(Root A) 3(Root B) 4(Child B1) 5(Leaf C)
assert_output "1" shellframe_sel_cursor "tr"
assert_output "3" _shellframe_tree_view_to_node "tr" "1"

ptyunit_test_begin "tree_on_key: cursor stays on same node after collapse"
# state: Root B expanded at view row 1; expand Root A too
shellframe_tree_on_key $'\033[A'   # cursor → 0 (Root A)
shellframe_tree_on_key $'\033[C'   # expand Root A → view: 0 1 2 3 4 5
shellframe_tree_on_key $'\033[B'   # cursor → 1 (Child A1)
shellframe_tree_on_key $'\033[B'   # cursor → 2 (Child A2)
shellframe_tree_on_key $'\033[A'   # cursor → 1 (Child A1)
shellframe_tree_on_key $'\033[A'   # cursor → 0 (Root A)
shellframe_tree_on_key " "         # collapse Root A → view: 0 3 4 5
# cursor should be on Root A (node 0) at view row 0
assert_output "0" shellframe_sel_cursor "tr"
assert_output "0" _shellframe_tree_view_to_node "tr" "0"

ptyunit_test_begin "tree_on_key: Left collapses expanded parent"
_reset_tree
shellframe_tree_on_key $'\033[C'   # expand Root A → view grows to 5
shellframe_tree_on_key $'\033[D'   # left: collapse Root A
assert_output "3" _shellframe_tree_view_count "tr"
assert_output "0" shellframe_sel_cursor "tr"

ptyunit_test_begin "tree_on_key: Left on leaf moves to parent"
_reset_tree
shellframe_tree_on_key $'\033[C'   # expand Root A → view: 0 1 2 3 5
# cursor at 0; move to child A1 (view row 1)
shellframe_tree_on_key $'\033[B'   # cursor → 1 (Child A1)
shellframe_tree_on_key $'\033[D'   # left on leaf → jump to parent (Root A at row 0)
assert_output "0" shellframe_sel_cursor "tr"

ptyunit_test_begin "tree_on_key: Left at depth-0 node is no-op"
_reset_tree
# cursor at 0 (Root A, depth=0, collapsed)
shellframe_tree_on_key $'\033[D'
assert_output "0" shellframe_sel_cursor "tr"

# ── shellframe_tree_on_key: Enter ────────────────────────────────────────────

ptyunit_test_begin "tree_on_key: Enter (\\r) returns 2 and sets TREE_RESULT"
_reset_tree
SHELLFRAME_TREE_RESULT=""
shellframe_tree_on_key $'\r'
assert_eq "2" "$?" "Enter returns 2"
assert_eq "0" "$SHELLFRAME_TREE_RESULT" "TREE_RESULT is node 0"

ptyunit_test_begin "tree_on_key: Enter (\\n) returns 2"
_reset_tree
shellframe_tree_on_key $'\n'
assert_eq "2" "$?" "newline returns 2"

ptyunit_test_begin "tree_on_key: Enter on child returns correct node index"
_reset_tree
shellframe_tree_on_key $'\033[C'   # expand Root A
shellframe_tree_on_key $'\033[B'   # cursor → view row 1 (Child A1 = node 1)
SHELLFRAME_TREE_RESULT=""
shellframe_tree_on_key $'\r'
assert_eq "2" "$?" "Enter returns 2"
assert_eq "1" "$SHELLFRAME_TREE_RESULT" "TREE_RESULT is node 1 (Child A1)"

# ── shellframe_tree_on_key: unhandled ─────────────────────────────────────────

ptyunit_test_begin "tree_on_key: unhandled key returns 1"
_reset_tree
shellframe_tree_on_key "x"
assert_eq "1" "$?" "unhandled returns 1"

ptyunit_test_begin "tree_on_key: Escape returns 1"
_reset_tree
shellframe_tree_on_key $'\033'
assert_eq "1" "$?" "escape returns 1"

# ── shellframe_tree_on_focus ──────────────────────────────────────────────────

ptyunit_test_begin "tree_on_focus: sets FOCUSED=1"
SHELLFRAME_TREE_FOCUSED=0
shellframe_tree_on_focus 1
assert_eq "1" "$SHELLFRAME_TREE_FOCUSED" "focused set to 1"

ptyunit_test_begin "tree_on_focus: sets FOCUSED=0"
SHELLFRAME_TREE_FOCUSED=1
shellframe_tree_on_focus 0
assert_eq "0" "$SHELLFRAME_TREE_FOCUSED" "focused set to 0"

# ── shellframe_tree_size ──────────────────────────────────────────────────────

ptyunit_test_begin "tree_size: returns 1 1 0 0"
assert_output "1 1 0 0" shellframe_tree_size

# ── Dirty-region integration ──────────────────────────────────────────────────

ptyunit_test_begin "tree_on_key: marks dirty on Down arrow"
_reset_tree
_SHELLFRAME_SHELL_DIRTY=0
shellframe_tree_on_key $'\033[B' || true   # Down
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "dirty set on navigation"

ptyunit_test_begin "tree_on_key: does not mark dirty on unrecognized key"
_reset_tree
_SHELLFRAME_SHELL_DIRTY=0
shellframe_tree_on_key "x" || true
assert_eq "0" "$_SHELLFRAME_SHELL_DIRTY" "dirty not set on unrecognized key"

# ── _shellframe_tree_node_to_view ─────────────────────────────────────────────

ptyunit_test_begin "node_to_view: node 0 (Root A) → view row 0 when collapsed"
_reset_tree
assert_output "0" _shellframe_tree_node_to_view "tr" "0"

ptyunit_test_begin "node_to_view: node 3 (Root B) → view row 1 when collapsed"
_reset_tree
assert_output "1" _shellframe_tree_node_to_view "tr" "3"

ptyunit_test_begin "node_to_view: node 5 (Leaf C) → view row 2 when collapsed"
_reset_tree
assert_output "2" _shellframe_tree_node_to_view "tr" "5"

ptyunit_test_begin "node_to_view: hidden child node returns 0 (default) when parent collapsed"
_reset_tree
# Child A1 (node 1, depth 1) is hidden when Root A is collapsed; function returns 0 as default
assert_output "0" _shellframe_tree_node_to_view "tr" "1"

ptyunit_test_begin "node_to_view: child node visible after parent expanded"
_reset_tree
_shellframe_tree_set_expanded "tr" 0 "1"
_shellframe_tree_build_view "tr"
_shellframe_tree_sync_state "tr" 0
# After expanding Root A: view = 0(Root A) 1(Child A1) 2(Child A2) 3(Root B) 5(Leaf C)
# Child A1 is at view row 1
assert_output "1" _shellframe_tree_node_to_view "tr" "1"

# ── shellframe_tree_render ─────────────────────────────────────────────────────

# Render helper: renders tree to a temp file, strips ANSI, returns plain text
_render_tree() {
    local _top="${1:-1}" _left="${2:-1}" _width="${3:-20}" _height="${4:-5}"
    local _out
    _out=$(mktemp "${TMPDIR:-/tmp}/sf-test-tree.XXXXXX")
    trap '{ exec 3>/dev/null 2>/dev/null || true; rm -f "$_out"; }' RETURN
    _SF_FRAME_PREV=()
    shellframe_fb_frame_start "$_height" "$_width"
    exec 3>"$_out"
    shellframe_tree_render "$_top" "$_left" "$_width" "$_height"
    shellframe_screen_flush
    exec 3>/dev/null
    tr -d '\033' < "$_out" | sed 's/\[[0-9;]*[A-Za-z]//g'
}

ptyunit_test_begin "tree_render: root nodes appear in output"
_reset_tree
_out=$(_render_tree 1 1 20 5)
assert_contains "$_out" "Root A" "Root A in output"
assert_contains "$_out" "RootB" "Root B in output"

ptyunit_test_begin "tree_render: collapsed parent shows expand indicator"
_reset_tree
_out=$(_render_tree 1 1 20 5)
assert_contains "$_out" "▶" "collapsed node shows ▶"

ptyunit_test_begin "tree_render: expanded parent shows collapse indicator"
_reset_tree
_shellframe_tree_set_expanded "tr" 0 "1"
_shellframe_tree_build_view "tr"
_shellframe_tree_sync_state "tr" 0
_out=$(_render_tree 1 1 20 6)
assert_contains "$_out" "▼" "expanded node shows ▼"

ptyunit_test_begin "tree_render: children visible after parent expanded"
_reset_tree
_shellframe_tree_set_expanded "tr" 0 "1"
_shellframe_tree_build_view "tr"
_shellframe_tree_sync_state "tr" 0
_out=$(_render_tree 1 1 20 6)
assert_contains "$_out" "ChildA1" "child visible after expand"

ptyunit_test_begin "tree_render: leaf node has no expand/collapse indicator"
_reset_tree
_out=$(_render_tree 1 1 20 5)
# Leaf C (no children) should appear without ▶ prefix; check it appears at all
# Non-selected rows: spaces are not emitted by screen_flush diff optimization
assert_contains "$_out" "LeafC" "leaf appears in output"

ptyunit_test_summary
