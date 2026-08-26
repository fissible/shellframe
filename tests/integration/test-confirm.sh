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

# ── #48 review round 3: consumer-owned fd 3 survives a v1 widget ─────────────

ptyunit_test_begin "confirm #48: consumer fd 3 payload intact around widget run"
_f48=$(mktemp)
_pty48_rc=0
out=$( SHELLFRAME_TTY_FD=7 SF48_OUT="$_f48" python3 "$PTY_RUN" "$SHELLFRAME_DIR/tests/fixtures/fd3-consumer.sh" $'y' 2>/dev/null ) || _pty48_rc=$?
assert_contains "$out" "Proceed"
assert_eq "before" "$(head -n1 "$_f48")"
assert_contains "$(cat "$_f48")" "after rc=0"
rm -f "$_f48"

ptyunit_test_begin "confirm #48b: consumer-owned fd 4 survives (save slot must dodge it)"
_f4=$(mktemp)
_pty48_rc=0
out=$( SHELLFRAME_TTY_FD=7 SF48_OUT="$_f4" SF48_FD_NUM=4 python3 "$PTY_RUN" "$SHELLFRAME_DIR/tests/fixtures/fd3-consumer.sh" $'y' 2>/dev/null ) || _pty48_rc=$?
assert_contains "$out" "Proceed"
assert_eq "before" "$(head -n1 "$_f4")"
assert_contains "$(cat "$_f4")" "after rc=0"
rm -f "$_f4"

ptyunit_test_summary
