#!/usr/bin/env bash
# tests/integration/test-diff-view.sh — PTY test for diff-view render

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/diff-view.sh"

source "$TESTS_DIR/ptyunit/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

ptyunit_test_begin "diff-view: renders without error — exit sentinel present"
out=$(_pty ENTER)
assert_contains "$out" "diff-view rendered"

ptyunit_test_begin "diff-view: left footer visible"
out=$(_pty ENTER)
assert_contains "$out" "a/foo.sh"

ptyunit_test_begin "diff-view: right footer visible"
out=$(_pty ENTER)
assert_contains "$out" "b/foo.sh"

ptyunit_test_begin "diff-view: diff content line rendered"
out=$(_pty ENTER)
assert_contains "$out" "context line"

ptyunit_test_summary
