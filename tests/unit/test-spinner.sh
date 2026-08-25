#!/usr/bin/env bash
# tests/unit/test-spinner.sh — progress bar math + non-tty degradation (#52)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

ptyunit_test_begin "progress #52: 0% renders empty track"
out=$(shellframe_progress 0 10 "work")
assert_contains "$out" "work [░░░░░░░░░░░░░░░░░░░░] 0%"

ptyunit_test_begin "progress #52: 50% renders half fill"
out=$(shellframe_progress 5 10)
assert_contains "$out" "[██████████░░░░░░░░░░] 50%"

ptyunit_test_begin "progress #52: 100% renders full bar"
out=$(shellframe_progress 10 10 "done")
assert_contains "$out" "done [████████████████████] 100%"

ptyunit_test_begin "progress #52: over-range clamps to 100%"
out=$(shellframe_progress 15 10)
assert_contains "$out" "] 100%"

ptyunit_test_begin "progress #52: non-numeric input rejected (rc 2)"
shellframe_progress x 10; assert_eq "2" "$?"

ptyunit_test_begin "progress #52: zero total guarded"
out=$(shellframe_progress 0 0)
assert_contains "$out" "] 0%"

ptyunit_test_begin "spinner #52: passes through exit code (success)"
shellframe_spinner working -- true; assert_eq "0" "$?"

ptyunit_test_begin "spinner #52: passes through exit code (failure rc 3)"
shellframe_spinner failing -- bash -c 'exit 3'; assert_eq "3" "$?"

ptyunit_test_begin "spinner #52: stdout of the command passes through"
out=$(shellframe_spinner computing -- printf 'result42')
assert_contains "$out" "result42"

ptyunit_test_begin "status #52: non-tty prints plain line"
out=$(shellframe_status "step one complete")
assert_eq "step one complete" "$out"

ptyunit_test_summary
