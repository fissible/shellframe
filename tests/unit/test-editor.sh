#!/usr/bin/env bash
# tests/unit/test-editor.sh — Unit tests for src/widgets/editor.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/widgets/editor.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── Setup ─────────────────────────────────────────────────────────────────────

SHELLFRAME_EDITOR_CTX="ed"

_reset() {
    SHELLFRAME_EDITOR_CTX="ed"
    SHELLFRAME_EDITOR_FOCUSED=0
    SHELLFRAME_EDITOR_LINES=()
    SHELLFRAME_EDITOR_RESULT=""
    shellframe_editor_init "ed" 10
}

_reset_with() {
    # _reset_with "line0" "line1" ...
    SHELLFRAME_EDITOR_CTX="ed"
    SHELLFRAME_EDITOR_FOCUSED=0
    SHELLFRAME_EDITOR_RESULT=""
    SHELLFRAME_EDITOR_LINES=("$@")
    shellframe_editor_init "ed" 10
}

# ── shellframe_editor_init ────────────────────────────────────────────────────

ptyunit_test_begin "editor_init: starts with 1 empty line"
_reset
assert_output "1" shellframe_editor_line_count "ed"

ptyunit_test_begin "editor_init: row and col start at 0"
_reset
assert_output "0" shellframe_editor_row "ed"
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "editor_init: line 0 is empty by default"
_reset
assert_output "" shellframe_editor_line "ed" 0

ptyunit_test_begin "editor_init: loads SHELLFRAME_EDITOR_LINES"
_reset_with "Hello" "World"
assert_output "2" shellframe_editor_line_count "ed"
assert_output "Hello" shellframe_editor_line "ed" 0
assert_output "World" shellframe_editor_line "ed" 1

# ── shellframe_editor_set_text / shellframe_editor_get_text ───────────────────

ptyunit_test_begin "set_text / get_text: round-trip single line"
_reset
shellframe_editor_set_text "ed" "hello"
assert_output "hello" shellframe_editor_get_text "ed"

ptyunit_test_begin "set_text: splits on newlines"
_reset
shellframe_editor_set_text "ed" $'foo\nbar\nbaz'
assert_output "3" shellframe_editor_line_count "ed"
assert_output "foo" shellframe_editor_line "ed" 0
assert_output "bar" shellframe_editor_line "ed" 1
assert_output "baz" shellframe_editor_line "ed" 2

ptyunit_test_begin "set_text: resets cursor to 0,0"
_reset
shellframe_editor_set_text "ed" $'foo\nbar'
assert_output "0" shellframe_editor_row "ed"
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "get_text: joins lines with newlines"
_reset
shellframe_editor_set_text "ed" $'line1\nline2'
assert_output $'line1\nline2' shellframe_editor_get_text "ed"

ptyunit_test_begin "get_text: empty editor returns empty string"
_reset
assert_output "" shellframe_editor_get_text "ed"

# ── Insert char ───────────────────────────────────────────────────────────────

ptyunit_test_begin "insert_char: inserts at cursor, advances col"
_reset
shellframe_editor_on_key "h"
shellframe_editor_on_key "i"
assert_output "hi" shellframe_editor_line "ed" 0
assert_output "2" shellframe_editor_col "ed"

ptyunit_test_begin "insert_char: inserts in middle of line"
_reset
shellframe_editor_set_text "ed" "ac"
# Move cursor to col 1 (between a and c)
shellframe_editor_on_key $'\033[C'   # right → col 1
shellframe_editor_on_key "b"
assert_output "abc" shellframe_editor_line "ed" 0
assert_output "2" shellframe_editor_col "ed"

# ── Enter (newline) ───────────────────────────────────────────────────────────

ptyunit_test_begin "enter: splits line at cursor, cursor moves to row+1 col 0"
_reset
shellframe_editor_set_text "ed" "hello world"
# Move to col 5
_i=0
while (( _i < 5 )); do shellframe_editor_on_key $'\033[C'; (( _i++ )) || true; done
shellframe_editor_on_key $'\r'
assert_output "2" shellframe_editor_line_count "ed"
assert_output "hello" shellframe_editor_line "ed" 0
assert_output " world" shellframe_editor_line "ed" 1
assert_output "1" shellframe_editor_row "ed"
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "enter: at start of line inserts empty line before"
_reset
shellframe_editor_set_text "ed" "hello"
# cursor is at 0,0 after set_text
shellframe_editor_on_key $'\r'
assert_output "2" shellframe_editor_line_count "ed"
assert_output "" shellframe_editor_line "ed" 0
assert_output "hello" shellframe_editor_line "ed" 1

ptyunit_test_begin "enter: at end of line appends empty line"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'   # col → 2 (end)
shellframe_editor_on_key $'\r'
assert_output "2" shellframe_editor_line_count "ed"
assert_output "hi" shellframe_editor_line "ed" 0
assert_output "" shellframe_editor_line "ed" 1

# ── Backspace ─────────────────────────────────────────────────────────────────

ptyunit_test_begin "backspace: deletes char before cursor"
_reset
shellframe_editor_set_text "ed" "abc"
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'   # col → 2
shellframe_editor_on_key $'\x7f'
assert_output "ac" shellframe_editor_line "ed" 0
assert_output "1" shellframe_editor_col "ed"

ptyunit_test_begin "backspace: at col 0, row 0 is no-op"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\x7f'
assert_output "hi" shellframe_editor_line "ed" 0
assert_output "0" shellframe_editor_row "ed"

ptyunit_test_begin "backspace: at col 0, row > 0 joins with previous line"
_reset
shellframe_editor_set_text "ed" $'abc\ndef'
# cursor at 0,0 after set_text; move to row 1 col 0
shellframe_editor_on_key $'\033[B'   # down → row 1
shellframe_editor_on_key $'\x7f'
assert_output "1" shellframe_editor_line_count "ed"
assert_output "abcdef" shellframe_editor_line "ed" 0
assert_output "0" shellframe_editor_row "ed"
assert_output "3" shellframe_editor_col "ed"

# ── Delete ────────────────────────────────────────────────────────────────────

ptyunit_test_begin "delete: removes char at cursor"
_reset
shellframe_editor_set_text "ed" "abc"
shellframe_editor_on_key $'\033[3~'
assert_output "bc" shellframe_editor_line "ed" 0
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "delete: at EOL joins with next line"
_reset
shellframe_editor_set_text "ed" $'abc\ndef'
# cursor at row 0, col 0; move to EOL
shellframe_editor_on_key $'\033[F'   # End → col 3
shellframe_editor_on_key $'\033[3~'
assert_output "1" shellframe_editor_line_count "ed"
assert_output "abcdef" shellframe_editor_line "ed" 0
assert_output "3" shellframe_editor_col "ed"

ptyunit_test_begin "delete: at EOL of last line is no-op"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\033[F'   # End
shellframe_editor_on_key $'\033[3~'
assert_output "1" shellframe_editor_line_count "ed"
assert_output "hi" shellframe_editor_line "ed" 0

# ── Arrow navigation ──────────────────────────────────────────────────────────

ptyunit_test_begin "left: moves col left"
_reset
shellframe_editor_set_text "ed" "abc"
shellframe_editor_on_key $'\033[C'   # right → col 1
shellframe_editor_on_key $'\033[D'   # left  → col 0
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "left: at col 0 row > 0 wraps to end of previous line"
_reset
shellframe_editor_set_text "ed" $'abc\ndef'
shellframe_editor_on_key $'\033[B'   # down → row 1
shellframe_editor_on_key $'\033[D'   # left → wraps to row 0 col 3
assert_output "0" shellframe_editor_row "ed"
assert_output "3" shellframe_editor_col "ed"

ptyunit_test_begin "left: at col 0 row 0 is no-op"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\033[D'
assert_output "0" shellframe_editor_row "ed"
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "right: moves col right"
_reset
shellframe_editor_set_text "ed" "abc"
shellframe_editor_on_key $'\033[C'
assert_output "1" shellframe_editor_col "ed"

ptyunit_test_begin "right: at EOL row < last wraps to next line col 0"
_reset
shellframe_editor_set_text "ed" $'abc\ndef'
shellframe_editor_on_key $'\033[F'   # End → col 3
shellframe_editor_on_key $'\033[C'   # right → wraps to row 1 col 0
assert_output "1" shellframe_editor_row "ed"
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "up: moves row up, clamps col to line length"
_reset
shellframe_editor_set_text "ed" $'hi\nworld'
shellframe_editor_on_key $'\033[B'   # down → row 1
shellframe_editor_on_key $'\033[F'   # End  → col 5
shellframe_editor_on_key $'\033[A'   # up   → row 0, col clamped to 2
assert_output "0" shellframe_editor_row "ed"
assert_output "2" shellframe_editor_col "ed"

ptyunit_test_begin "down: moves row down, clamps col to line length"
_reset
shellframe_editor_set_text "ed" $'world\nhi'
shellframe_editor_on_key $'\033[F'   # End → col 5
shellframe_editor_on_key $'\033[B'   # down → row 1, col clamped to 2
assert_output "1" shellframe_editor_row "ed"
assert_output "2" shellframe_editor_col "ed"

ptyunit_test_begin "up: at row 0 is no-op"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\033[A'
assert_output "0" shellframe_editor_row "ed"

ptyunit_test_begin "down: at last row is no-op"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\033[B'
assert_output "0" shellframe_editor_row "ed"

# ── Home / End ────────────────────────────────────────────────────────────────

ptyunit_test_begin "home: moves col to 0"
_reset
shellframe_editor_set_text "ed" "hello"
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'   # col → 2
shellframe_editor_on_key $'\033[H'   # Home
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "ctrl-a: moves col to 0"
_reset
shellframe_editor_set_text "ed" "hello"
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\x01'   # Ctrl-A
assert_output "0" shellframe_editor_col "ed"

ptyunit_test_begin "end: moves col to line length"
_reset
shellframe_editor_set_text "ed" "hello"
shellframe_editor_on_key $'\033[F'   # End
assert_output "5" shellframe_editor_col "ed"

ptyunit_test_begin "ctrl-e: moves col to line length"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\x05'   # Ctrl-E
assert_output "2" shellframe_editor_col "ed"

# ── Ctrl-K (kill to EOL) ──────────────────────────────────────────────────────

ptyunit_test_begin "ctrl-k: kills from cursor to end of line"
_reset
shellframe_editor_set_text "ed" "hello world"
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'   # col → 5
shellframe_editor_on_key $'\x0b'     # Ctrl-K
assert_output "hello" shellframe_editor_line "ed" 0
assert_output "5" shellframe_editor_col "ed"

ptyunit_test_begin "ctrl-k: at EOL joins with next line"
_reset
shellframe_editor_set_text "ed" $'hello\nworld'
shellframe_editor_on_key $'\033[F'   # End → col 5
shellframe_editor_on_key $'\x0b'
assert_output "1" shellframe_editor_line_count "ed"
assert_output "helloworld" shellframe_editor_line "ed" 0

# ── Ctrl-U (kill to SOL) ──────────────────────────────────────────────────────

ptyunit_test_begin "ctrl-u: kills from start of line to cursor"
_reset
shellframe_editor_set_text "ed" "hello world"
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'   # col → 5
shellframe_editor_on_key $'\x15'     # Ctrl-U
assert_output " world" shellframe_editor_line "ed" 0
assert_output "0" shellframe_editor_col "ed"

# ── Ctrl-W (kill word left) ───────────────────────────────────────────────────

ptyunit_test_begin "ctrl-w: kills word left of cursor"
_reset
shellframe_editor_set_text "ed" "hello world"
shellframe_editor_on_key $'\033[F'   # End → col 11
shellframe_editor_on_key $'\x17'     # Ctrl-W
assert_output "hello " shellframe_editor_line "ed" 0
assert_output "6" shellframe_editor_col "ed"

ptyunit_test_begin "ctrl-w: at col 0 is no-op"
_reset
shellframe_editor_set_text "ed" "hello"
shellframe_editor_on_key $'\x17'
assert_output "hello" shellframe_editor_line "ed" 0
assert_output "0" shellframe_editor_col "ed"

# ── Page Up / Down ────────────────────────────────────────────────────────────

ptyunit_test_begin "page_down: moves cursor down by viewport rows"
SHELLFRAME_EDITOR_LINES=()
_pi=0
while (( _pi < 20 )); do
    SHELLFRAME_EDITOR_LINES+=("line${_pi}")
    (( _pi++ )) || true
done
SHELLFRAME_EDITOR_CTX="ed"
shellframe_editor_init "ed" 5   # viewport = 5 rows
shellframe_editor_on_key $'\033[6~'   # Page Down
assert_output "5" shellframe_editor_row "ed"

ptyunit_test_begin "page_up: moves cursor up by viewport rows"
shellframe_editor_on_key $'\033[5~'   # Page Up → back to row 0
assert_output "0" shellframe_editor_row "ed"

# ── Vertical scroll ───────────────────────────────────────────────────────────

ptyunit_test_begin "scroll: vtop advances when cursor moves past viewport"
SHELLFRAME_EDITOR_LINES=()
_si=0
while (( _si < 15 )); do
    SHELLFRAME_EDITOR_LINES+=("row${_si}")
    (( _si++ )) || true
done
SHELLFRAME_EDITOR_CTX="ed"
shellframe_editor_init "ed" 5   # viewport = 5 rows
# Move cursor 10 rows down
_di=0
while (( _di < 10 )); do
    shellframe_editor_on_key $'\033[B'
    (( _di++ )) || true
done
assert_output "10" shellframe_editor_row "ed"
# vtop should be at 6 (row 10 = vtop+4 → vtop=6)
assert_output "6" shellframe_editor_vtop "ed"

ptyunit_test_begin "scroll: vtop decreases when cursor moves above viewport"
# cursor at row 10, vtop at 6; move up 8 rows → cursor at 2
_ui=0
while (( _ui < 8 )); do
    shellframe_editor_on_key $'\033[A'
    (( _ui++ )) || true
done
assert_output "2" shellframe_editor_row "ed"
assert_output "2" shellframe_editor_vtop "ed"

# Restore context for subsequent tests
SHELLFRAME_EDITOR_CTX="ed"
SHELLFRAME_EDITOR_LINES=()
shellframe_editor_init "ed" 10

# ── Ctrl-D (submit) ───────────────────────────────────────────────────────────

ptyunit_test_begin "ctrl-d: returns 2 and sets SHELLFRAME_EDITOR_RESULT"
_reset
shellframe_editor_set_text "ed" $'foo\nbar'
SHELLFRAME_EDITOR_RESULT=""
shellframe_editor_on_key $'\x04'
assert_eq "2" "$?" "ctrl-d returns 2"
assert_eq $'foo\nbar' "$SHELLFRAME_EDITOR_RESULT" "RESULT is full text"

ptyunit_test_begin "ctrl-d: empty editor result is empty string"
_reset
SHELLFRAME_EDITOR_RESULT=""
shellframe_editor_on_key $'\x04'
assert_eq "2" "$?" "ctrl-d returns 2 on empty editor"
assert_eq "" "$SHELLFRAME_EDITOR_RESULT" "RESULT is empty"

# ── Unhandled keys ────────────────────────────────────────────────────────────

ptyunit_test_begin "on_key: unhandled key returns 1"
_reset
shellframe_editor_on_key $'\033'
assert_eq "1" "$?" "escape returns 1"

ptyunit_test_begin "on_key: tab returns 1 (not handled)"
_reset
shellframe_editor_on_key $'\t'
assert_eq "1" "$?" "tab returns 1"

# ── on_focus ──────────────────────────────────────────────────────────────────

ptyunit_test_begin "on_focus: sets FOCUSED=1"
SHELLFRAME_EDITOR_FOCUSED=0
shellframe_editor_on_focus 1
assert_eq "1" "$SHELLFRAME_EDITOR_FOCUSED" "focused set to 1"

ptyunit_test_begin "on_focus: sets FOCUSED=0"
SHELLFRAME_EDITOR_FOCUSED=1
shellframe_editor_on_focus 0
assert_eq "0" "$SHELLFRAME_EDITOR_FOCUSED" "focused set to 0"

# ── size ──────────────────────────────────────────────────────────────────────

ptyunit_test_begin "editor_size: returns 1 1 0 0"
assert_output "1 1 0 0" shellframe_editor_size

ptyunit_test_summary
