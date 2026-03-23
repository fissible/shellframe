#!/usr/bin/env bash
# tests/integration/test-table.sh — PTY tests for examples/table.sh (legacy table widget)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/table.sh"

source "$TESTS_DIR/ptyunit/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

ptyunit_test_begin "table: renders without crash — confirm on Enter"
out=$(_pty ENTER)
assert_contains "$out" "Selected: "

ptyunit_test_begin "table: q quits"
out=$(_pty q)
assert_contains "$out" "Aborted."

ptyunit_test_summary
