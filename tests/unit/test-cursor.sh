#!/usr/bin/env bash
# tests/unit/test-cursor.sh — Unit tests for src/cursor.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/cursor.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── shellframe_cur_init ────────────────────────────────────────────────────────

ptyunit_test_begin "cur_init: empty text — cursor at 0"
shellframe_cur_init "t"
assert_output "0" shellframe_cur_pos "t"

ptyunit_test_begin "cur_init: empty text — text is empty"
shellframe_cur_init "t"
assert_output "" shellframe_cur_text "t"

ptyunit_test_begin "cur_init: initial text — cursor at end"
shellframe_cur_init "t" "hello"
assert_output "5" shellframe_cur_pos "t"

ptyunit_test_begin "cur_init: initial text — text stored"
shellframe_cur_init "t" "hello"
assert_output "hello" shellframe_cur_text "t"

ptyunit_test_begin "cur_init: reinit resets state"
shellframe_cur_init "t" "foo"
shellframe_cur_insert "t" "x"
shellframe_cur_init "t"
assert_output "0"  shellframe_cur_pos  "t"
assert_output ""   shellframe_cur_text "t"

# ── shellframe_cur_set ─────────────────────────────────────────────────────────

ptyunit_test_begin "cur_set: replaces text and moves cursor to end"
shellframe_cur_init "t"
shellframe_cur_set "t" "world"
assert_output "world" shellframe_cur_text "t"
assert_output "5"     shellframe_cur_pos  "t"

ptyunit_test_begin "cur_set: explicit pos"
shellframe_cur_set "t" "hello" 2
assert_output "2" shellframe_cur_pos "t"

ptyunit_test_begin "cur_set: pos clamped to 0"
shellframe_cur_set "t" "hello" -5
assert_output "0" shellframe_cur_pos "t"

ptyunit_test_begin "cur_set: pos clamped to len"
shellframe_cur_set "t" "hello" 99
assert_output "5" shellframe_cur_pos "t"

# ── shellframe_cur_move ────────────────────────────────────────────────────────

ptyunit_test_begin "cur_move: right increments pos"
shellframe_cur_init "t" "abc"
shellframe_cur_set "t" "abc" 0
shellframe_cur_move "t" right
assert_output "1" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: right clamps at end"
shellframe_cur_init "t" "abc"
shellframe_cur_move "t" right   # pos was 3 (end)
assert_output "3" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: left decrements pos"
shellframe_cur_init "t" "abc"
shellframe_cur_move "t" left
assert_output "2" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: left clamps at 0"
shellframe_cur_init "t"
shellframe_cur_move "t" left
assert_output "0" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: home sets pos to 0"
shellframe_cur_init "t" "hello"
shellframe_cur_move "t" home
assert_output "0" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: end sets pos to len"
shellframe_cur_init "t" "hello"
shellframe_cur_set "t" "hello" 0
shellframe_cur_move "t" end
assert_output "5" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: word_left skips to start of word"
shellframe_cur_init "t" "hello world"   # len=11, cursor at 11
shellframe_cur_move "t" word_left       # skip "world" (5 chars) → 6
assert_output "6" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: word_left skips trailing space then word"
shellframe_cur_init "t" "hello world"
shellframe_cur_set "t" "hello world" 6  # just after space, before 'w'
shellframe_cur_move "t" word_left       # pos 6: check pos-1=5 which is ' '
                                        # skip space → 5; check pos-1=4 'o'
                                        # skip "hello" → 0
assert_output "0" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: word_left at 0 is no-op"
shellframe_cur_init "t" "hello"
shellframe_cur_set "t" "hello" 0
shellframe_cur_move "t" word_left
assert_output "0" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: word_right skips to start of next word"
shellframe_cur_init "t" "hello world"
shellframe_cur_set "t" "hello world" 0  # before 'h'
shellframe_cur_move "t" word_right      # skip "hello" → 5, skip " " → 6
assert_output "6" shellframe_cur_pos "t"

ptyunit_test_begin "cur_move: word_right at end is no-op"
shellframe_cur_init "t" "hello"         # cursor at 5 (end)
shellframe_cur_move "t" word_right
assert_output "5" shellframe_cur_pos "t"

# ── shellframe_cur_insert ──────────────────────────────────────────────────────

ptyunit_test_begin "cur_insert: insert at beginning"
shellframe_cur_init "t" "bc"
shellframe_cur_set "t" "bc" 0
shellframe_cur_insert "t" "a"
assert_output "abc" shellframe_cur_text "t"
assert_output "1"   shellframe_cur_pos  "t"

ptyunit_test_begin "cur_insert: insert in middle"
shellframe_cur_init "t" "ac"
shellframe_cur_set "t" "ac" 1
shellframe_cur_insert "t" "b"
assert_output "abc" shellframe_cur_text "t"
assert_output "2"   shellframe_cur_pos  "t"

ptyunit_test_begin "cur_insert: insert at end"
shellframe_cur_init "t" "ab"
shellframe_cur_insert "t" "c"
assert_output "abc" shellframe_cur_text "t"
assert_output "3"   shellframe_cur_pos  "t"

# ── shellframe_cur_backspace ───────────────────────────────────────────────────

ptyunit_test_begin "cur_backspace: deletes char before cursor"
shellframe_cur_init "t" "abc"
shellframe_cur_move "t" left  # pos = 2
shellframe_cur_backspace "t"
assert_output "ac" shellframe_cur_text "t"
assert_output "1"  shellframe_cur_pos  "t"

ptyunit_test_begin "cur_backspace: at end deletes last char"
shellframe_cur_init "t" "abc"   # cursor at 3
shellframe_cur_backspace "t"
assert_output "ab" shellframe_cur_text "t"
assert_output "2"  shellframe_cur_pos  "t"

ptyunit_test_begin "cur_backspace: at pos 0 is no-op"
shellframe_cur_init "t" "abc"
shellframe_cur_set "t" "abc" 0
shellframe_cur_backspace "t"
assert_output "abc" shellframe_cur_text "t"
assert_output "0"   shellframe_cur_pos  "t"

# ── shellframe_cur_delete ──────────────────────────────────────────────────────

ptyunit_test_begin "cur_delete: deletes char at cursor"
shellframe_cur_init "t" "abc"
shellframe_cur_set "t" "abc" 1  # cursor before 'b'
shellframe_cur_delete "t"
assert_output "ac" shellframe_cur_text "t"
assert_output "1"  shellframe_cur_pos  "t"

ptyunit_test_begin "cur_delete: at end is no-op"
shellframe_cur_init "t" "abc"   # cursor at 3
shellframe_cur_delete "t"
assert_output "abc" shellframe_cur_text "t"
assert_output "3"   shellframe_cur_pos  "t"

ptyunit_test_begin "cur_delete: at beginning deletes first char"
shellframe_cur_init "t" "abc"
shellframe_cur_set "t" "abc" 0
shellframe_cur_delete "t"
assert_output "bc" shellframe_cur_text "t"
assert_output "0"  shellframe_cur_pos  "t"

# ── shellframe_cur_kill_to_end ─────────────────────────────────────────────────

ptyunit_test_begin "cur_kill_to_end: from middle"
shellframe_cur_init "t" "hello world"
shellframe_cur_set "t" "hello world" 5
shellframe_cur_kill_to_end "t"
assert_output "hello" shellframe_cur_text "t"
assert_output "5"     shellframe_cur_pos  "t"

ptyunit_test_begin "cur_kill_to_end: from beginning"
shellframe_cur_init "t" "hello"
shellframe_cur_set "t" "hello" 0
shellframe_cur_kill_to_end "t"
assert_output "" shellframe_cur_text "t"
assert_output "0" shellframe_cur_pos "t"

ptyunit_test_begin "cur_kill_to_end: at end is no-op"
shellframe_cur_init "t" "hello"   # cursor at 5
shellframe_cur_kill_to_end "t"
assert_output "hello" shellframe_cur_text "t"
assert_output "5"     shellframe_cur_pos  "t"

# ── shellframe_cur_kill_to_start ───────────────────────────────────────────────

ptyunit_test_begin "cur_kill_to_start: from middle"
shellframe_cur_init "t" "hello world"
shellframe_cur_set "t" "hello world" 6
shellframe_cur_kill_to_start "t"
assert_output "world" shellframe_cur_text "t"
assert_output "0"     shellframe_cur_pos  "t"

ptyunit_test_begin "cur_kill_to_start: from end"
shellframe_cur_init "t" "hello"   # cursor at 5
shellframe_cur_kill_to_start "t"
assert_output "" shellframe_cur_text "t"
assert_output "0" shellframe_cur_pos "t"

ptyunit_test_begin "cur_kill_to_start: at start is no-op"
shellframe_cur_init "t" "hello"
shellframe_cur_set "t" "hello" 0
shellframe_cur_kill_to_start "t"
assert_output "hello" shellframe_cur_text "t"
assert_output "0"     shellframe_cur_pos  "t"

# ── shellframe_cur_kill_word_left ──────────────────────────────────────────────

ptyunit_test_begin "cur_kill_word_left: deletes last word"
shellframe_cur_init "t" "hello world"   # cursor at 11
shellframe_cur_kill_word_left "t"
assert_output "hello " shellframe_cur_text "t"
assert_output "6"      shellframe_cur_pos  "t"

ptyunit_test_begin "cur_kill_word_left: skips trailing space then word"
shellframe_cur_init "t" "hello world   "  # cursor at 14 (trailing spaces)
shellframe_cur_kill_word_left "t"
# skip 3 spaces → pos 11; skip "world" (5 chars) → pos 6
assert_output "hello " shellframe_cur_text "t"
assert_output "6"      shellframe_cur_pos  "t"

ptyunit_test_begin "cur_kill_word_left: at pos 0 is no-op"
shellframe_cur_init "t" "hello"
shellframe_cur_set "t" "hello" 0
shellframe_cur_kill_word_left "t"
assert_output "hello" shellframe_cur_text "t"
assert_output "0"     shellframe_cur_pos  "t"

ptyunit_test_begin "cur_kill_word_left: single word from end"
shellframe_cur_init "t" "hello"   # cursor at 5
shellframe_cur_kill_word_left "t"
assert_output "" shellframe_cur_text "t"
assert_output "0" shellframe_cur_pos "t"

# ── Two independent contexts ──────────────────────────────────────────────────

ptyunit_test_begin "two contexts do not interfere"
shellframe_cur_init "ctx1" "foo"
shellframe_cur_init "ctx2" "bar"
shellframe_cur_insert "ctx1" "x"
assert_output "foox" shellframe_cur_text "ctx1"
assert_output "bar"  shellframe_cur_text "ctx2"

ptyunit_test_summary
