#!/usr/bin/env bash
# tests/integration/test-confirm.sh — PTY tests for examples/confirm.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUI_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$TESTS_DIR/pty_run.py"
SCRIPT="$CLUI_DIR/examples/confirm.sh"

source "$TESTS_DIR/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

clui_test_begin "confirm: y key — confirmed"
out=$(_pty y)
assert_contains "$out" "Confirmed"

clui_test_begin "confirm: n key — cancelled"
out=$(_pty n)
assert_contains "$out" "Cancelled"

clui_test_begin "confirm: Enter selects default (Yes) — confirmed"
out=$(_pty ENTER)
assert_contains "$out" "Confirmed"

clui_test_begin "confirm: Right then Enter — moves to No — cancelled"
out=$(_pty RIGHT ENTER)
assert_contains "$out" "Cancelled"

clui_test_begin "confirm: Right then Left then Enter — back to Yes — confirmed"
out=$(_pty RIGHT LEFT ENTER)
assert_contains "$out" "Confirmed"

clui_test_begin "confirm: q key — cancelled"
out=$(_pty q)
assert_contains "$out" "Cancelled"

clui_test_begin "confirm: Q key — cancelled"
out=$(_pty Q)
assert_contains "$out" "Cancelled"

clui_test_begin "confirm: Esc key — cancelled"
out=$(_pty ESC)
assert_contains "$out" "Cancelled"

clui_test_summary
