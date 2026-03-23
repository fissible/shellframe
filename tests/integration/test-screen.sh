#!/usr/bin/env bash
# tests/integration/test-screen.sh — Integration tests for src/screen.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$TESTS_DIR/ptyunit/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/screen-test.sh"

source "$TESTS_DIR/ptyunit/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

ptyunit_test_begin "screen: full enter/cursor/raw/exit sequence completes without error"
out=$(_pty)
assert_contains "$out" "screen-test-done"

ptyunit_test_summary
