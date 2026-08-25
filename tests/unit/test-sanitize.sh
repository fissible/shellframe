#!/usr/bin/env bash
# tests/unit/test-sanitize.sh — shellframe_sanitize: untrusted-content scrubbing (#45)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

ptyunit_test_begin "sanitize: plain text passes through untouched"
assert_eq "hello world" "$(shellframe_sanitize "hello world")"

ptyunit_test_begin "sanitize: CSI sequence stripped (real ESC bytes)"
assert_eq "ab" "$(shellframe_sanitize $'a\033[31mb')"

ptyunit_test_begin "sanitize: SGR with params + cursor moves stripped"
assert_eq "x" "$(shellframe_sanitize $'\033[1;32m\033[10;5Hx')"

ptyunit_test_begin "sanitize: OSC terminated by BEL stripped"
assert_eq "title" "$(shellframe_sanitize $'\033]0;window\07title')"

ptyunit_test_begin "sanitize: OSC terminated by ST stripped"
assert_eq "t" "$(shellframe_sanitize $'\033]8;;http://x\033\\t')"

ptyunit_test_begin "sanitize: newline and tab preserved"
assert_eq $'a\n\tb' "$(shellframe_sanitize $'a\n\tb')"

ptyunit_test_begin "sanitize: other C0 controls dropped"
assert_eq "abc" "$(shellframe_sanitize $'a\002\007bc')"

ptyunit_test_begin "sanitize: DEL dropped"
assert_eq "ac" "$(shellframe_sanitize $'a\177c')"

ptyunit_test_begin "sanitize: literal backslash-n is NOT interpreted (#42 class)"
# two characters: backslash + n — must survive as-is
_out=$(shellframe_sanitize 'a\nb')
assert_eq 'a\nb' "$_out"

ptyunit_test_begin "sanitize: trailing truncated escape dropped"
assert_eq "ok" "$(shellframe_sanitize $'ok\033[31')"

ptyunit_test_summary
