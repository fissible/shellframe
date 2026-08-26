#!/usr/bin/env bash
# tests/integration/test-spinner.sh — PTY validation for #52

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"

source "$PTYUNIT_HOME/assert.sh"

ptyunit_test_begin "spinner #52: propagates the command's exit code"
_rc=0
out=$(SPINNER_EXIT=3 python3 "$PTY_RUN" "$SHELLFRAME_DIR/examples/spinner-demo.sh" 2>/dev/null) || _rc=$?
assert_eq "3" "$_rc"

ptyunit_test_begin "spinner #52: animation frames observed on the tty (raw capture)"
raw=$(PTY_RAW=1 python3 "$PTY_RUN" "$SHELLFRAME_DIR/examples/spinner-demo.sh" 2>/dev/null)
_seen=0
for f in '|' '/' '-' '\'; do
    [[ "$raw" == *"$f"* ]] && _seen=$((_seen+1))
done
(( _seen >= 2 )) && ptyunit_pass || ptyunit_fail "expected >=2 distinct frames, saw $_seen"

ptyunit_test_begin "spinner #52: spinner line cleared after completion"
raw=$(PTY_RAW=1 python3 "$PTY_RUN" "$SHELLFRAME_DIR/examples/spinner-demo.sh" 2>/dev/null)
# pty_run normalizes \r to \n even in RAW captures, so assert on the TAIL:
# the last write must be the clear-line sequence.
_tail="${raw: -6}"
case "$_tail" in
    *$'\033[2K'*) ptyunit_pass ;;
    *) ptyunit_fail "stream does not end with a cleared spinner line" ;;
esac

ptyunit_test_summary
