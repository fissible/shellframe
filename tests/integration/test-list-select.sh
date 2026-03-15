#!/usr/bin/env bash
# tests/integration/test-list-select.sh — PTY tests for examples/list-select.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUI_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$TESTS_DIR/pty_run.py"
SCRIPT="$CLUI_DIR/examples/list-select.sh"

source "$TESTS_DIR/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

clui_test_begin "list-select: select first item (apple) with Enter"
out=$(_pty ENTER)
assert_contains "$out" "You selected: apple"

clui_test_begin "list-select: move down once, select banana"
out=$(_pty DOWN ENTER)
assert_contains "$out" "You selected: banana"

clui_test_begin "list-select: move down twice, select cherry"
out=$(_pty DOWN DOWN ENTER)
assert_contains "$out" "You selected: cherry"

clui_test_begin "list-select: quit with q — no selection"
out=$(_pty q)
assert_contains "$out" "No selection."

clui_test_begin "list-select: select with Space key"
out=$(_pty SPACE)
assert_contains "$out" "You selected: apple"

clui_test_summary
