#!/usr/bin/env bash
# tests/unit/test-text.sh — Unit tests for src/text.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/text.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── _shellframe_text_align: left (default) ────────────────────────────────────

ptyunit_test_begin "text_align: left — exact fit, unchanged"
assert_output "hello" _shellframe_text_align "hello" "hello" 5

ptyunit_test_begin "text_align: left — shorter, pads right"
assert_output "hi   " _shellframe_text_align "hi" "hi" 5

ptyunit_test_begin "text_align: left — empty string, all spaces"
assert_output "     " _shellframe_text_align "" "" 5

ptyunit_test_begin "text_align: left — overflow, clips with ellipsis"
assert_output "hell…" _shellframe_text_align "hello world" "hello world" 5

ptyunit_test_begin "text_align: left — width 1, replaced by ellipsis"
assert_output "…" _shellframe_text_align "hi" "hi" 1

ptyunit_test_begin "text_align: left — width 0, empty"
assert_output "" _shellframe_text_align "hi" "hi" 0

# ── _shellframe_text_align: right ─────────────────────────────────────────────

ptyunit_test_begin "text_align: right — shorter, pads left"
assert_output "   hi" _shellframe_text_align "hi" "hi" 5 right

ptyunit_test_begin "text_align: right — exact fit"
assert_output "hello" _shellframe_text_align "hello" "hello" 5 right

ptyunit_test_begin "text_align: right — overflow, clips"
assert_output "hell…" _shellframe_text_align "hello world" "hello world" 5 right

# ── _shellframe_text_align: center ────────────────────────────────────────────

ptyunit_test_begin "text_align: center — even padding"
assert_output "  hi  " _shellframe_text_align "hi" "hi" 6 center

ptyunit_test_begin "text_align: center — odd padding (extra space on right)"
assert_output " hi  " _shellframe_text_align "hi" "hi" 5 center

ptyunit_test_begin "text_align: center — exact fit"
assert_output "hello" _shellframe_text_align "hello" "hello" 5 center

ptyunit_test_begin "text_align: center — overflow, clips"
assert_output "hell…" _shellframe_text_align "hello world" "hello world" 5 center

# ── _shellframe_text_align: ANSI rendered ─────────────────────────────────────

ptyunit_test_begin "text_align: ANSI rendered — fits, returned unchanged"
_BOLD=$'\033[1m'; _RST=$'\033[0m'
result=$(_shellframe_text_align "hi" "${_BOLD}hi${_RST}" 5)
# Visible: "hi   " (BOLD+hi+RST+3spaces); check visible chars after stripping ANSI
result_vis="${result//$_BOLD/}"; result_vis="${result_vis//$_RST/}"
assert_eq "hi   " "$result_vis" "ANSI rendered left-aligned and padded"

# ── _shellframe_text_wrap_words ───────────────────────────────────────────────

ptyunit_test_begin "text_wrap: single word fits"
assert_output "hello" _shellframe_text_wrap_words "hello" 10

ptyunit_test_begin "text_wrap: two words fit on one line"
assert_output "hello world" _shellframe_text_wrap_words "hello world" 12

ptyunit_test_begin "text_wrap: two words split to two lines"
result=$(_shellframe_text_wrap_words "hello world" 6)
assert_eq "$(printf 'hello\nworld')" "$result" "two words split"

ptyunit_test_begin "text_wrap: three words, middle wrap"
result=$(_shellframe_text_wrap_words "foo bar baz" 7)
assert_eq "$(printf 'foo bar\nbaz')" "$result" "third word wraps"

ptyunit_test_begin "text_wrap: long word hard-breaks"
result=$(_shellframe_text_wrap_words "abcdefgh" 4)
assert_eq "$(printf 'abcd\nefgh')" "$result" "hard-break at width"

ptyunit_test_begin "text_wrap: empty string produces empty output"
assert_output "" _shellframe_text_wrap_words "" 10

ptyunit_test_begin "text_wrap: word longer than width splits across lines"
result=$(_shellframe_text_wrap_words "abcdefghij" 3)
assert_eq "$(printf 'abc\ndef\nghi\nj')" "$result" "long word splits multiple times"

# ── shellframe_text_size ──────────────────────────────────────────────────────

ptyunit_test_begin "text_size: single line"
SHELLFRAME_TEXT_CONTENT="hello"
assert_output "0 1 5 1" shellframe_text_size

ptyunit_test_begin "text_size: empty content"
SHELLFRAME_TEXT_CONTENT=""
assert_output "0 1 0 1" shellframe_text_size

ptyunit_test_begin "text_size: two lines"
SHELLFRAME_TEXT_CONTENT=$'hello\nworld!'
assert_output "0 1 6 2" shellframe_text_size

ptyunit_test_begin "text_size: three lines, first is longest"
SHELLFRAME_TEXT_CONTENT=$'hello world\nfoo\nbar'
assert_output "0 1 11 3" shellframe_text_size

ptyunit_test_summary
