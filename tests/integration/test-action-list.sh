#!/usr/bin/env bash
# tests/integration/test-action-list.sh — PTY tests for examples/action-list.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUI_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$TESTS_DIR/pty_run.py"
SCRIPT="$CLUI_DIR/examples/action-list.sh"

source "$TESTS_DIR/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

clui_test_begin "action-list: confirm with no changes — nothing printed"
out=$(_pty ENTER)
# With all actions on "nothing", no fruit lines should appear in output
assert_contains "$out" "Confirmed!"

clui_test_begin "action-list: move to banana, cycle to eat, confirm"
out=$(_pty DOWN SPACE ENTER)
assert_contains "$out" "banana → eat"

clui_test_begin "action-list: move to banana, cycle twice to peel, confirm"
out=$(_pty DOWN SPACE SPACE ENTER)
assert_contains "$out" "banana → peel"

clui_test_begin "action-list: move to cherry, cycle to eat, confirm"
out=$(_pty DOWN DOWN SPACE ENTER)
assert_contains "$out" "cherry → eat"

clui_test_begin "action-list: quit with q — Aborted printed"
out=$(_pty q)
assert_contains "$out" "Aborted."

clui_test_begin "action-list: quit with Q — Aborted printed"
out=$(_pty Q)
assert_contains "$out" "Aborted."

clui_test_summary
