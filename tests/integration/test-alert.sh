#!/usr/bin/env bash
# tests/integration/test-alert.sh — PTY tests for examples/alert.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
CLUI_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$TESTS_DIR/pty_run.py"
SCRIPT="$CLUI_DIR/examples/alert.sh"

source "$TESTS_DIR/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

clui_test_begin "alert: any key (Space) dismisses"
out=$(_pty SPACE)
assert_contains "$out" "Alert dismissed"

clui_test_begin "alert: Enter dismisses"
out=$(_pty ENTER)
assert_contains "$out" "Alert dismissed"

clui_test_begin "alert: letter key dismisses"
out=$(_pty q)
assert_contains "$out" "Alert dismissed"

clui_test_summary
