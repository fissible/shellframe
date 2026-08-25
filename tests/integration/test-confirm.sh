#!/usr/bin/env bash
# tests/integration/test-confirm.sh — PTY tests for examples/confirm.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/confirm.sh"

source "$PTYUNIT_HOME/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

ptyunit_test_begin "confirm: y key — confirmed"
out=$(_pty y)
assert_contains "$out" "Confirmed"

ptyunit_test_begin "confirm: n key — cancelled"
out=$(_pty n)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm: Enter selects default (Yes) — confirmed"
out=$(_pty ENTER)
assert_contains "$out" "Confirmed"

ptyunit_test_begin "confirm: Right then Enter — moves to No — cancelled"
out=$(_pty RIGHT ENTER)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm: Right then Left then Enter — back to Yes — confirmed"
out=$(_pty RIGHT LEFT ENTER)
assert_contains "$out" "Confirmed"

ptyunit_test_begin "confirm: q key — cancelled"
out=$(_pty q)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm: Q key — cancelled"
out=$(_pty Q)
assert_contains "$out" "Cancelled"

ptyunit_test_begin "confirm: Esc key — cancelled"
out=$(_pty ESC)
assert_contains "$out" "Cancelled"


# ── #44 review follow-up: confirm exits cancelled on stdin EOF ───────────────

ptyunit_test_begin "confirm #44: detached stdin exits promptly with rc=1"
_ce_rc=0
out=$( python3 "$PTY_RUN" "$SHELLFRAME_DIR/tests/fixtures/confirm-eof.sh" ) || _ce_rc=$?
assert_contains "$out" "confirm-rc:1"
assert_eq "0" "$_ce_rc"
ptyunit_test_summary
