#!/usr/bin/env bash
# tests/unit/test-sanitize.sh — shellframe_sanitize: untrusted-content scrubbing (#45)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

# Exercise UTF-8 collation wherever available: the CSI final-byte class
# [@-~] silently failed to match letters under bash 3.2 + UTF-8 collation
# (review blocker, 2026-08-25) — CI's C-locale runners cannot see it.
if locale -a 2>/dev/null | grep -qi 'en_US.utf8\|en_US.UTF-8'; then
    export LANG=en_US.UTF-8 LC_COLLATE=en_US.UTF-8
fi

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

ptyunit_test_begin "sanitize: 50 KB clean paste completes within 10 s (perf guard)"
# Regression guard for the round-3 quadratic findings: ${var//x/} stripping
# and multibyte-locale substring extraction both made clean pastes take
# seconds-to-minutes on bash 3.2. The bound is generous enough for slow CI
# (a real regression costs >40 s).
_big=$(printf 'abc %064d\n%.0s' 1 800)   # ~50 KB, no ESC / no C0
_t0=$(date +%s)
shellframe_sanitize "$_big" _big_out
_t1=$(date +%s)
assert_eq "${#_big}" "${#_big_out}"
if (( _t1 - _t0 <= 10 )); then
    ptyunit_pass
else
    ptyunit_fail "sanitizer took $(( _t1 - _t0 )) s for a clean 50 KB paste"
fi

ptyunit_test_begin "sanitize: multi-byte text survives byte-collation pinning"
assert_eq "日本語テスト" "$(shellframe_sanitize "日本語テスト")"

ptyunit_test_summary
