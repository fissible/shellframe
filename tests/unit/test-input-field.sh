#!/usr/bin/env bash
# tests/unit/test-input-field.sh — Unit tests for src/widgets/input-field.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/cursor.sh"
source "$SHELLFRAME_DIR/src/widgets/input-field.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# Helper: reset field to empty state
_reset_field() {
    SHELLFRAME_FIELD_CTX="f"
    shellframe_field_init "f"
}

# ── shellframe_field_on_key: printable chars ──────────────────────────────────

ptyunit_test_begin "field_on_key: printable char inserts, returns 0"
_reset_field
shellframe_field_on_key "a"
assert_eq "0" "$?" "returns 0"
assert_output "a" shellframe_cur_text "f"

ptyunit_test_begin "field_on_key: multiple printable chars"
_reset_field
shellframe_field_on_key "h"
shellframe_field_on_key "i"
assert_output "hi" shellframe_cur_text "f"

ptyunit_test_begin "field_on_key: space is printable"
_reset_field
shellframe_field_on_key " "
assert_eq "0" "$?" "space returns 0"
assert_output " " shellframe_cur_text "f"

ptyunit_test_begin "field_on_key: symbols are printable"
_reset_field
shellframe_field_on_key "!"
shellframe_field_on_key "@"
assert_output "!@" shellframe_cur_text "f"

# ── shellframe_field_on_key: backspace ────────────────────────────────────────

ptyunit_test_begin "field_on_key: backspace removes last char, returns 0"
_reset_field
shellframe_cur_set "f" "hello"   # text="hello", cursor=5 (end)
shellframe_field_on_key $'\x7f'
assert_eq "0" "$?" "backspace returns 0"
assert_output "hell" shellframe_cur_text "f"

ptyunit_test_begin "field_on_key: backspace at pos 0 does nothing"
_reset_field
shellframe_cur_set "f" "hi" 0   # text="hi", cursor=0
shellframe_field_on_key $'\x7f'
assert_output "hi" shellframe_cur_text "f"

# ── shellframe_field_on_key: cursor movement ──────────────────────────────────

ptyunit_test_begin "field_on_key: left arrow moves cursor, returns 0"
_reset_field
shellframe_cur_set "f" "hello" 3   # text="hello", cursor=3
shellframe_field_on_key $'\033[D'
assert_eq "0" "$?" "left returns 0"
assert_output "2" shellframe_cur_pos "f"

ptyunit_test_begin "field_on_key: right arrow moves cursor, returns 0"
_reset_field
shellframe_cur_set "f" "hello" 2   # text="hello", cursor=2
shellframe_field_on_key $'\033[C'
assert_eq "0" "$?" "right returns 0"
assert_output "3" shellframe_cur_pos "f"

ptyunit_test_begin "field_on_key: home moves to start"
_reset_field
shellframe_cur_set "f" "hello" 4   # text="hello", cursor=4
shellframe_field_on_key $'\033[H'
assert_output "0" shellframe_cur_pos "f"

ptyunit_test_begin "field_on_key: end moves to end"
_reset_field
shellframe_cur_set "f" "hello" 0   # text="hello", cursor=0
shellframe_field_on_key $'\033[F'
assert_output "5" shellframe_cur_pos "f"

ptyunit_test_begin "field_on_key: Ctrl-A moves to start"
_reset_field
shellframe_cur_set "f" "hello" 3   # text="hello", cursor=3
shellframe_field_on_key $'\x01'
assert_output "0" shellframe_cur_pos "f"

ptyunit_test_begin "field_on_key: Ctrl-E moves to end"
_reset_field
shellframe_cur_set "f" "hello" 1   # text="hello", cursor=1
shellframe_field_on_key $'\x05'
assert_output "5" shellframe_cur_pos "f"

# ── shellframe_field_on_key: kill operations ──────────────────────────────────

ptyunit_test_begin "field_on_key: Ctrl-K kills to end"
_reset_field
shellframe_cur_set "f" "hello" 2   # text="hello", cursor=2
shellframe_field_on_key $'\x0b'
assert_eq "0" "$?" "Ctrl-K returns 0"
assert_output "he" shellframe_cur_text "f"

ptyunit_test_begin "field_on_key: Ctrl-U kills to start"
_reset_field
shellframe_cur_set "f" "hello" 3   # text="hello", cursor=3
shellframe_field_on_key $'\x15'
assert_eq "0" "$?" "Ctrl-U returns 0"
assert_output "lo" shellframe_cur_text "f"

ptyunit_test_begin "field_on_key: Ctrl-W kills word left"
_reset_field
shellframe_cur_init "f" "foo bar"   # text="foo bar", cursor=7 (end)
shellframe_field_on_key $'\x17'
assert_eq "0" "$?" "Ctrl-W returns 0"
assert_output "foo " shellframe_cur_text "f"

# ── shellframe_field_on_key: Enter ────────────────────────────────────────────

ptyunit_test_begin "field_on_key: Enter (\\r) returns 2"
_reset_field
shellframe_field_on_key $'\r'
assert_eq "2" "$?" "Enter returns 2"

ptyunit_test_begin "field_on_key: Enter (\\n) returns 2"
_reset_field
shellframe_field_on_key $'\n'
assert_eq "2" "$?" "Enter (newline) returns 2"

# ── shellframe_field_on_key: unhandled keys ───────────────────────────────────

ptyunit_test_begin "field_on_key: Page Up returns 1 (not handled)"
_reset_field
shellframe_field_on_key $'\033[5~'
assert_eq "1" "$?" "Page Up returns 1"

ptyunit_test_begin "field_on_key: Escape returns 1"
_reset_field
shellframe_field_on_key $'\033'
assert_eq "1" "$?" "Escape returns 1"

ptyunit_test_begin "field_on_key: F1 returns 1"
_reset_field
shellframe_field_on_key $'\033OP'
assert_eq "1" "$?" "F1 returns 1"

# ── shellframe_field_on_focus ──────────────────────────────────────────────────

ptyunit_test_begin "field_on_focus: sets FOCUSED=1"
SHELLFRAME_FIELD_FOCUSED=0
shellframe_field_on_focus 1
assert_eq "1" "$SHELLFRAME_FIELD_FOCUSED" "focused set to 1"

ptyunit_test_begin "field_on_focus: sets FOCUSED=0"
SHELLFRAME_FIELD_FOCUSED=1
shellframe_field_on_focus 0
assert_eq "0" "$SHELLFRAME_FIELD_FOCUSED" "focused set to 0"

# ── shellframe_field_size ──────────────────────────────────────────────────────

ptyunit_test_begin "field_size: returns 1 1 0 1"
assert_output "1 1 0 1" shellframe_field_size

# ── shellframe_field_render ───────────────────────────────────────────────────

# Render field to a temp file, strip ANSI, return plain text
_render_field() {
    local _top="${1:-1}" _left="${2:-1}" _width="${3:-20}"
    local _out
    _out=$(mktemp "${TMPDIR:-/tmp}/sf-test-field.XXXXXX")
    trap '{ exec 3>&- 2>/dev/null || true; rm -f "$_out"; }' RETURN
    exec 3>"$_out"
    shellframe_field_render "$_top" "$_left" "$_width"
    exec 3>&-
    sed 's/\033\[[0-9;]*m//g; s/\033\[[0-9;]*[A-Za-z]//g' "$_out"
}

ptyunit_test_begin "field_render: placeholder shown when empty and unfocused"
_reset_field
SHELLFRAME_FIELD_FOCUSED=0
SHELLFRAME_FIELD_PLACEHOLDER="Enter name"
_out=$(_render_field 1 1 20)
assert_contains "$_out" "Enter name" "placeholder present"

ptyunit_test_begin "field_render: text appears when field has content"
_reset_field
shellframe_cur_set "f" "hello"
SHELLFRAME_FIELD_FOCUSED=0
SHELLFRAME_FIELD_PLACEHOLDER=""
_out=$(_render_field 1 1 20)
assert_contains "$_out" "hello" "text present"

ptyunit_test_begin "field_render: mask mode shows bullets instead of text"
_reset_field
shellframe_cur_set "f" "abc"
SHELLFRAME_FIELD_FOCUSED=0
SHELLFRAME_FIELD_MASK=1
SHELLFRAME_FIELD_PLACEHOLDER=""
_out=$(_render_field 1 1 20)
assert_contains "$_out" "●●●" "masked text shows bullets"
assert_not_contains "$_out" "abc" "original text hidden"
SHELLFRAME_FIELD_MASK=0

# ── _shellframe_field_is_printable ────────────────────────────────────────────

ptyunit_test_begin "is_printable: letter returns 0"
_shellframe_field_is_printable "a"
assert_eq "0" "$?" "a is printable"

ptyunit_test_begin "is_printable: space returns 0"
_shellframe_field_is_printable " "
assert_eq "0" "$?" "space is printable"

ptyunit_test_begin "is_printable: digit returns 0"
_shellframe_field_is_printable "5"
assert_eq "0" "$?" "digit is printable"

ptyunit_test_begin "is_printable: symbol returns 0"
_shellframe_field_is_printable "!"
assert_eq "0" "$?" "symbol is printable"

ptyunit_test_begin "is_printable: multi-char string returns 1"
_shellframe_field_is_printable "ab"
assert_eq "1" "$?" "multi-char not printable"

ptyunit_test_begin "is_printable: escape sequence returns 1"
_shellframe_field_is_printable $'\033[A'
assert_eq "1" "$?" "escape sequence not printable"

ptyunit_test_begin "is_printable: empty string returns 1"
_shellframe_field_is_printable ""
assert_eq "1" "$?" "empty string not printable"

ptyunit_test_summary
