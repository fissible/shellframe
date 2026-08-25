#!/usr/bin/env bash
# tests/unit/test-read-eof.sh — EOF discrimination for both key readers (#44)
#
# The return-code discriminator is bash-version-dependent (verified:
# bash 3.2 returns 1 for BOTH timeout and EOF; bash >= 4 returns >128 on
# timeout). These tests run on every matrix leg, so the 3.2 two-strike
# confirmation path is exercised where it matters.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

ptyunit_test_begin "read_key: stdin EOF sets SHELLFRAME_KEY_EOF instantly"
_out=$( </dev/null shellframe_read_key _rk; printf 'eof=%d key=%q' "$SHELLFRAME_KEY_EOF" "$_rk" )
assert_contains "$_out" "eof=1"

ptyunit_test_begin "shell_read_key: open-and-idle input is a timeout tick, not EOF"
# A held-open fifo never delivers data and never EOFs: the timed read must
# report a timeout tick. On bash 3.2 this exercises both strikes of the
# confirmation probe (each returns rc=1+empty like EOF would).
_fifo="${TMPDIR:-/tmp}/sf-eof-fifo.$$"
mkfifo "$_fifo"
( sleep 4 > "$_fifo" >/dev/null 2>&1 ) &
_hold=$!
_out=$( exec 9<> "$_fifo"; _shellframe_shell_read_key _sk <&9; printf 'eof=%d' "${_SHELLFRAME_KEY_EOF:-}" )
exec 9<&-
kill "$_hold" 2>/dev/null
rm -f "$_fifo"
assert_contains "$_out" "eof=0"

ptyunit_test_begin "shell_read_key: stdin EOF sets _SHELLFRAME_KEY_EOF"
_out=$( </dev/null _shellframe_shell_read_key _sk; printf 'eof=%d' "${_SHELLFRAME_KEY_EOF:-}" )
assert_contains "$_out" "eof=1"

ptyunit_test_begin "shell_read_key: idle pipe does not false-flag EOF (two-strike on 3.2)"
# Held-open pipe: on bash >=4 the single timed read reports timeout;
# on 3.2 the confirmation probe also times out. Neither may set EOF.
_out=$( { sleep 3; } | { _shellframe_shell_read_key _sk; printf 'eof=%d' "${_SHELLFRAME_KEY_EOF:-}"; } )
assert_contains "$_out" "eof=0"

ptyunit_test_summary
