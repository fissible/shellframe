#!/usr/bin/env bash
# tests/unit/test-save-fd.sh — _shellframe_pick_save_fd correctness (#48/#61)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

ptyunit_test_begin "save-fd #61: skips an open candidate, picks the first closed one"
exec 5>/dev/null                       # hold 5 open (as a consumer would)
_SF_TTY_FD=3
_picked=$(_shellframe_pick_save_fd)
assert_eq "6" "$_picked"

ptyunit_test_begin "save-fd #61: skips the tty fd itself"
exec 5>/dev/null; exec 6>/dev/null     # 5 and 6 both consumer-held
_SF_TTY_FD=7                           # tty on 7; candidates 5 6 8 9
_picked=$(_shellframe_pick_save_fd)
assert_eq "8" "$_picked"

exec 5>&- 2>/dev/null; exec 6>&- 2>/dev/null   # release test-held fds
ptyunit_test_begin "save-fd #61: closed fds are picked in order"
_SF_TTY_FD=3
_picked=$(_shellframe_pick_save_fd)
assert_eq "5" "$_picked"

ptyunit_test_summary
