#!/usr/bin/env bash
# tests/integration/test-autocomplete.sh — PTY tests for examples/autocomplete.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"

_example="$SHELLFRAME_DIR/examples/autocomplete.sh"

source "$PTYUNIT_HOME/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$_example" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

ptyunit_test_begin "autocomplete: Tab completes single match 'prod' -> 'products'"
out=$(_pty p r o d TAB ENTER)
assert_contains "$out" "products"

ptyunit_test_begin "autocomplete: Tab shows popup, navigate and accept"
out=$(_pty u s TAB DOWN ENTER ENTER)
assert_contains "$out" "user_roles"

ptyunit_test_begin "autocomplete: Esc dismisses popup"
out=$(_pty u s TAB ESC ESC)
assert_not_contains "$out" "Selected:"

ptyunit_test_summary
