#!/usr/bin/env bash
# tests/unit/test-editor.sh — Unit tests for src/widgets/editor.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/widgets/editor.sh"
source "$PTYUNIT_HOME/assert.sh"

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

# ── _shellframe_ed_line_segments ─────────────────────────────────────────────

ptyunit_test_begin "line_segments: empty line → 0:0"
assert_output "0:0" _shellframe_ed_line_segments "" 80

ptyunit_test_begin "line_segments: short line → single segment 0:N"
assert_output "0:5" _shellframe_ed_line_segments "hello" 80

ptyunit_test_begin "line_segments: line exactly at width → single segment"
assert_output "0:5" _shellframe_ed_line_segments "hello" 5

ptyunit_test_begin "line_segments: soft wrap at last space before width"
# "hello world" width=7: space at index 5 → seg0="hello "(0:6), seg1="world"(6:5)
assert_output "0:6 6:5" _shellframe_ed_line_segments "hello world" 7

ptyunit_test_begin "line_segments: hard wrap at width when no space found"
# "helloworld" width=6: no space → hard wrap → 0:6, 6:4
assert_output "0:6 6:4" _shellframe_ed_line_segments "helloworld" 6

ptyunit_test_begin "line_segments: multi-segment with repeated spaces"
# "ab cde fg" width=4: space at index 2 → 0:3("ab "); then "cde fg" space at 3 → 3:4("cde "); then "fg"=7:2
assert_output "0:3 3:4 7:2" _shellframe_ed_line_segments "ab cde fg" 4

# ── _shellframe_ed_build_vmap / _shellframe_ed_vrow_count ─────────────────────

_setup_vmap() {
    # _setup_vmap width line0 line1 ...
    local _w="$1"; shift
    SHELLFRAME_EDITOR_LINES=("$@")
    SHELLFRAME_EDITOR_CTX="ed"
    shellframe_editor_init "ed" 10
    printf -v "_SHELLFRAME_ED_ed_VWIDTH" '%d' "$_w"
    _shellframe_ed_build_vmap "ed"
}

ptyunit_test_begin "vrow_count: 2 short lines → 2 visual rows (no wrap)"
_setup_vmap 80 "hello" "world"
assert_output "2" _shellframe_ed_vrow_count "ed"

ptyunit_test_begin "vrow_count: 1 wrapping line → 2 visual rows"
_setup_vmap 7 "hello world"
assert_output "2" _shellframe_ed_vrow_count "ed"

ptyunit_test_begin "vrow_count: 2 lines one wrapping → 3 visual rows"
_setup_vmap 7 "hello world" "hi"
assert_output "3" _shellframe_ed_vrow_count "ed"

# ── _shellframe_ed_cursor_to_vrow ─────────────────────────────────────────────

ptyunit_test_begin "cursor_to_vrow: col 0 on first line → vrow 0"
_setup_vmap 7 "hello world" "hi"
_cv=99
_shellframe_ed_cursor_to_vrow "ed" 0 0 _cv
assert_eq "0" "$_cv" "vrow should be 0"

ptyunit_test_begin "cursor_to_vrow: col 3 on first line (before wrap) → vrow 0"
_setup_vmap 7 "hello world" "hi"
_cv=99
_shellframe_ed_cursor_to_vrow "ed" 0 3 _cv
assert_eq "0" "$_cv" "vrow should be 0"

ptyunit_test_begin "cursor_to_vrow: col at seg boundary → resolves to next vrow"
# "hello world" width=7: seg0=0:6, seg1=6:5
# col=6 matches both seg_start=0 (≤6) and seg_start=6 (≤6); last wins → vrow 1
_setup_vmap 7 "hello world" "hi"
_cv=99
_shellframe_ed_cursor_to_vrow "ed" 0 6 _cv
assert_eq "1" "$_cv" "vrow should be 1 (boundary belongs to next segment)"

ptyunit_test_begin "cursor_to_vrow: col on second content line → vrow 2"
_setup_vmap 7 "hello world" "hi"
_cv=99
_shellframe_ed_cursor_to_vrow "ed" 1 1 _cv
assert_eq "2" "$_cv" "vrow should be 2"

# ── wrap=1 up/down: visual row movement, vis_col preservation ─────────────────

_reset_wrap1_narrow() {
    SHELLFRAME_EDITOR_WRAP=1
    SHELLFRAME_EDITOR_CTX="ed"
    SHELLFRAME_EDITOR_FOCUSED=0
    SHELLFRAME_EDITOR_RESULT=""
    SHELLFRAME_EDITOR_LINES=("$@")
    shellframe_editor_init "ed" 10
    printf -v "_SHELLFRAME_ED_ed_VWIDTH" '%d' 7
}

ptyunit_test_begin "wrap1 up: moves from vrow 1 to vrow 0, preserves vis_col"
# "hello world" wraps at width=7: vrow0="hello "(0:6), vrow1="world"(6:5)
# Start at col=8 on row 0 (vrow 1, vis_col=8-6=2); move up → vrow 0, new_col=0+2=2
_reset_wrap1_narrow "hello world"
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 8
SHELLFRAME_EDITOR_WRAP=1
_shellframe_ed_build_vmap "ed"
_shellframe_ed_move_up "ed"
assert_output "0" shellframe_editor_row "ed"
assert_output "2" shellframe_editor_col "ed"

ptyunit_test_begin "wrap1 down: moves from vrow 0 to vrow 1, preserves vis_col"
# Start at col=2 on row 0 (vrow 0, vis_col=2); move down → vrow 1, new_col=6+2=8
_reset_wrap1_narrow "hello world"
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 2
SHELLFRAME_EDITOR_WRAP=1
_shellframe_ed_build_vmap "ed"
_shellframe_ed_move_down "ed"
assert_output "0" shellframe_editor_row "ed"
assert_output "8" shellframe_editor_col "ed"

ptyunit_test_begin "wrap1 up: clamps vis_col to target segment length"
# vrow0="hello "(0:6, len=6); vrow1="world"(6:5)
# Start at col=11 (end of "world", vis_col=11-6=5); move up → vrow0, new_col=0+5=5
# clamped to tgt_s+tgt_l=0+6=6? No: clamped only if new_col > tgt_s+tgt_l
# 5 > 6? No → new_col=5 (not clamped)
_reset_wrap1_narrow "hello world"
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 11
SHELLFRAME_EDITOR_WRAP=1
_shellframe_ed_build_vmap "ed"
_shellframe_ed_move_up "ed"
assert_output "0" shellframe_editor_row "ed"
assert_output "5" shellframe_editor_col "ed"

ptyunit_test_begin "wrap1 up: does not land at segment boundary (core flicker bug)"
# "hello world" width=7: vrow0=s:0,l:6 ("hello ") [intermediate], vrow1=s:6,l:5 ("world") [last]
# From vrow1 col=11 (EOL), vis_col=11-6=5. Move up: new_col=0+5=5.
# 5 >= 0+6=6? No — no clamp. cursor_to_vrow(0,5): s=0≤5→vrow0; s=6≤5?No → vrow0. ✓
_reset_wrap1_narrow "hello world"
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 11
SHELLFRAME_EDITOR_WRAP=1
_shellframe_ed_build_vmap "ed"
_shellframe_ed_move_up "ed"
# Must land on content row 0, col within vrow 0 (0..5), NOT 6 (which = vrow 1 start)
assert_output "0"  shellframe_editor_row "ed"
_bc=$(shellframe_editor_col "ed")
assert_eq "1" "$(( _bc < 6 ))" "col must be < 6 (not at next-seg boundary)"

ptyunit_test_begin "wrap1 up: wide vis_col clamped to last char of intermediate segment"
# "abc def" width=3: "0:3 3:1 4:3". vrow2=s:4,l:3 ("def") last; vrow1=s:3,l:1 (" ") intermed.
# From vrow2 col=7 (EOL), vis_col=3. Move up to vrow1: new_col=3+3=6, 6>=3+1=4 → clamp to 3.
# cursor_to_vrow(0,3): s=0≤3→vrow0, s=3≤3→vrow1, s=4≤3?No → vrow1. ✓ (col=3 is on vrow1)
_reset_wrap1_narrow "abc def"
printf -v _SHELLFRAME_ED_ed_VWIDTH '%d' 3
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 7
SHELLFRAME_EDITOR_WRAP=1
_shellframe_ed_build_vmap "ed"
_shellframe_ed_move_up "ed"
assert_output "0"  shellframe_editor_row "ed"
assert_output "3"  shellframe_editor_col "ed"

ptyunit_test_begin "wrap1 up: at vrow 0 is no-op"
_reset_wrap1_narrow "hello world"
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 0
SHELLFRAME_EDITOR_WRAP=1
_shellframe_ed_build_vmap "ed"
_shellframe_ed_move_up "ed"
assert_output "0" shellframe_editor_row "ed"
assert_output "0" shellframe_editor_col "ed"

# ── wrap=0 HSCROLL (lazy / cursor-anchored) ───────────────────────────────────

_reset_nowrap() {
    SHELLFRAME_EDITOR_WRAP=0
    SHELLFRAME_EDITOR_CTX="ed"
    SHELLFRAME_EDITOR_FOCUSED=0
    SHELLFRAME_EDITOR_RESULT=""
    SHELLFRAME_EDITOR_LINES=("01234567890123456789")  # 20-char line
    shellframe_editor_init "ed" 10
    printf -v "_SHELLFRAME_ED_ed_VWIDTH" '%d' 10  # 10-char viewport
}

_hscroll_ed() {
    local _v="_SHELLFRAME_ED_ed_HSCROLL"
    printf '%d' "${!_v:-0}"
}

ptyunit_test_begin "hscroll: starts at 0"
_reset_nowrap
assert_output "0" _hscroll_ed

ptyunit_test_begin "hscroll: stays 0 while cursor within viewport"
_reset_nowrap
# Move right 9 times → col=9, still within [0..9], hscroll stays 0
_hi=0
while (( _hi < 9 )); do
    shellframe_editor_on_key $'\033[C'
    (( _hi++ )) || true
done
assert_output "9" shellframe_editor_col "ed"
assert_output "0" _hscroll_ed

ptyunit_test_begin "hscroll: advances lazily when cursor goes off right edge"
_reset_nowrap
# Move right 10 times → col=10, col >= hscroll+width=0+10 → hscroll=1
_hi=0
while (( _hi < 10 )); do
    shellframe_editor_on_key $'\033[C'
    (( _hi++ )) || true
done
assert_output "10" shellframe_editor_col "ed"
assert_output "1" _hscroll_ed

ptyunit_test_begin "hscroll: stays put while cursor moves left within viewport"
# col=10, hscroll=1; move left 5 times → col=5, still >= hscroll=1, hscroll stays 1
_hi=0
while (( _hi < 5 )); do
    shellframe_editor_on_key $'\033[D'
    (( _hi++ )) || true
done
assert_output "5" shellframe_editor_col "ed"
assert_output "1" _hscroll_ed

ptyunit_test_begin "hscroll: decreases when cursor goes below left edge"
# col=5, hscroll=1; move left 5 more → col=0, col < hscroll=1 → hscroll=0
_hi=0
while (( _hi < 5 )); do
    shellframe_editor_on_key $'\033[D'
    (( _hi++ )) || true
done
assert_output "0" shellframe_editor_col "ed"
assert_output "0" _hscroll_ed

# Restore wrap=1 for subsequent tests
SHELLFRAME_EDITOR_WRAP=1

# ── _shellframe_ed_insert_text (bulk insert) ──────────────────────────────────

ptyunit_test_begin "insert_text: inserts single-line string at cursor"
_reset
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 0
_shellframe_ed_insert_text "ed" "hello"
assert_output "hello" shellframe_editor_line "ed" 0
assert_output "5"     shellframe_editor_col  "ed"

ptyunit_test_begin "insert_text: splits on newlines and inserts multiple lines"
_reset
_shellframe_ed_insert_text "ed" $'foo\nbar\nbaz'
assert_output "3"   shellframe_editor_line_count "ed"
assert_output "foo" shellframe_editor_line "ed" 0
assert_output "bar" shellframe_editor_line "ed" 1
assert_output "baz" shellframe_editor_line "ed" 2
assert_output "2"   shellframe_editor_row "ed"
assert_output "3"   shellframe_editor_col "ed"

ptyunit_test_begin "insert_text: inserts mid-line and mid-document"
_reset
shellframe_editor_set_text "ed" $'start\nend'
# cursor is at 0,0; move to row 0 col 5 (end of "start")
shellframe_editor_on_key $'\033[F'
_shellframe_ed_insert_text "ed" $'\nmiddle'
assert_output "3"      shellframe_editor_line_count "ed"
assert_output "start"  shellframe_editor_line "ed" 0
assert_output "middle" shellframe_editor_line "ed" 1
assert_output "end"    shellframe_editor_line "ed" 2

# ── goal column ───────────────────────────────────────────────────────────────

_reset_goal_col() {
    SHELLFRAME_EDITOR_WRAP=1
    SHELLFRAME_EDITOR_CTX="ed"
    SHELLFRAME_EDITOR_FOCUSED=0
    SHELLFRAME_EDITOR_LINES=("hello world" "" "hello world")
    shellframe_editor_init "ed" 10
    printf -v "_SHELLFRAME_ED_ed_VWIDTH" '%d' 80
    _shellframe_ed_build_vmap "ed"
}

ptyunit_test_begin "goal_col: initialized to -1"
_reset_goal_col
_gc_var="_SHELLFRAME_ED_ed_GOAL_COL"
assert_eq "-1" "${!_gc_var:-0}" "GOAL_COL starts at -1"

ptyunit_test_begin "goal_col: preserved through blank line (wrap=1)"
_reset_goal_col
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 5
# Down → blank line row=1, col forced to 0; GOAL_COL stores 5
_shellframe_ed_move_down "ed"
assert_output "1" shellframe_editor_row "ed"
assert_output "0" shellframe_editor_col "ed"
# Down again → row=2, GOAL_COL=5 restores col=5
_shellframe_ed_move_down "ed"
assert_output "2" shellframe_editor_row "ed"
assert_output "5" shellframe_editor_col "ed"

ptyunit_test_begin "goal_col: clamps to short line, restores on longer line (wrap=1)"
_reset_goal_col
_shellframe_ed_set_line "ed" 1 "hi"
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 9
printf -v _SHELLFRAME_ED_ed_GOAL_COL '%d' -1
# Down → row=1 "hi" (len=2), col clamps to 2; GOAL_COL stores 9
_shellframe_ed_move_down "ed"
assert_output "1" shellframe_editor_row "ed"
assert_output "2" shellframe_editor_col "ed"
# Down again → row=2 "hello world" (len=11), GOAL_COL=9 → col=9
_shellframe_ed_move_down "ed"
assert_output "2" shellframe_editor_row "ed"
assert_output "9" shellframe_editor_col "ed"

ptyunit_test_begin "goal_col: resets on left key"
_reset_goal_col
printf -v _SHELLFRAME_ED_ed_ROW '%d' 0
printf -v _SHELLFRAME_ED_ed_COL '%d' 5
printf -v _SHELLFRAME_ED_ed_GOAL_COL '%d' -1
_shellframe_ed_move_down "ed"
_shellframe_ed_move_up "ed"
_gc_var="_SHELLFRAME_ED_ed_GOAL_COL"
assert_eq "5" "${!_gc_var:-X}" "goal_col stored as 5 after vertical nav"
shellframe_editor_on_key $'\033[D'
assert_eq "-1" "${!_gc_var:-X}" "goal_col reset to -1 after left"

ptyunit_test_begin "goal_col: resets on printable char"
_reset_goal_col
printf -v _SHELLFRAME_ED_ed_GOAL_COL '%d' 7
_gc_var="_SHELLFRAME_ED_ed_GOAL_COL"
shellframe_editor_on_key "a"
assert_eq "-1" "${!_gc_var:-X}" "goal_col reset after printable char"

ptyunit_test_begin "goal_col: resets on right key"
_reset_goal_col
printf -v _SHELLFRAME_ED_ed_GOAL_COL '%d' 7
_gc_var="_SHELLFRAME_ED_ed_GOAL_COL"
shellframe_editor_on_key $'\033[C'
assert_eq "-1" "${!_gc_var:-X}" "goal_col reset after right"

ptyunit_test_begin "goal_col: resets on home key"
_reset_goal_col
printf -v _SHELLFRAME_ED_ed_GOAL_COL '%d' 7
_gc_var="_SHELLFRAME_ED_ed_GOAL_COL"
shellframe_editor_on_key $'\033[H'
assert_eq "-1" "${!_gc_var:-X}" "goal_col reset after home"

ptyunit_test_begin "goal_col: up then down returns to original col (wrap=1)"
_reset_goal_col
printf -v _SHELLFRAME_ED_ed_ROW '%d' 2
printf -v _SHELLFRAME_ED_ed_COL '%d' 8
printf -v _SHELLFRAME_ED_ed_GOAL_COL '%d' -1
# Up → blank line row=1 col=0 (GOAL_COL=8 stored)
_shellframe_ed_move_up "ed"
assert_output "1" shellframe_editor_row "ed"
assert_output "0" shellframe_editor_col "ed"
# Up again → row=0 "hello world", col restored to 8
_shellframe_ed_move_up "ed"
assert_output "0" shellframe_editor_row "ed"
assert_output "8" shellframe_editor_col "ed"

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

# ── shellframe_editor_get_text: out_var form ──────────────────────────────────

ptyunit_test_begin "get_text: out_var form stores result in named variable"
_reset
shellframe_editor_set_text "ed" $'line1\nline2'
_got=""
shellframe_editor_get_text "ed" _got
assert_eq $'line1\nline2' "$_got" "out_var receives full text"

# ── _shellframe_ed_is_printable ───────────────────────────────────────────────

ptyunit_test_begin "is_printable: single printable char returns 0"
_shellframe_ed_is_printable "a"
assert_eq "0" "$?" "printable char returns 0"

ptyunit_test_begin "is_printable: multi-char string returns 1"
_shellframe_ed_is_printable "ab"
assert_eq "1" "$?" "multi-char string returns 1"

ptyunit_test_begin "is_printable: escape byte returns 1"
_shellframe_ed_is_printable $'\033'
assert_eq "1" "$?" "non-printable byte returns 1"

# ── _shellframe_ed_insert_string: empty string ────────────────────────────────

ptyunit_test_begin "insert_string: empty string is a no-op"
_reset
shellframe_editor_set_text "ed" "hello"
shellframe_editor_on_key $'\033[C'
shellframe_editor_on_key $'\033[C'   # col → 2
_shellframe_ed_insert_string "ed" ""
assert_output "hello" shellframe_editor_line "ed" 0
assert_output "2"     shellframe_editor_col  "ed"

# ── _shellframe_ed_line_segments: zero width ─────────────────────────────────

ptyunit_test_begin "line_segments: width=0 returns full-length single segment"
assert_output "0:5" _shellframe_ed_line_segments "hello" 0

# ── _shellframe_ed_vrow_count: out_var form ───────────────────────────────────

ptyunit_test_begin "vrow_count: out_var form stores result in named variable"
_setup_vmap 80 "hello" "world"
_vc=""
_shellframe_ed_vrow_count "ed" _vc
assert_eq "2" "$_vc" "out_var receives row count"

# ── right at EOL of last line ─────────────────────────────────────────────────

ptyunit_test_begin "right: at EOL of last line is no-op"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\033[F'   # End → col 2
shellframe_editor_on_key $'\033[C'   # right at last-line EOL → no-op
assert_output "0" shellframe_editor_row "ed"
assert_output "2" shellframe_editor_col "ed"

# ── ctrl-k at EOL of last line ────────────────────────────────────────────────

ptyunit_test_begin "ctrl-k: at EOL of last line is no-op"
_reset
shellframe_editor_set_text "ed" "hi"
shellframe_editor_on_key $'\033[F'   # End → col 2
shellframe_editor_on_key $'\x0b'     # Ctrl-K at EOL of last line → no-op
assert_output "1"  shellframe_editor_line_count "ed"
assert_output "hi" shellframe_editor_line "ed" 0
assert_output "2"  shellframe_editor_col "ed"

# ── no-wrap mode: up/down with goal column ────────────────────────────────────

_reset_nowrap_multiline() {
    SHELLFRAME_EDITOR_WRAP=0
    SHELLFRAME_EDITOR_CTX="ed"
    SHELLFRAME_EDITOR_FOCUSED=0
    SHELLFRAME_EDITOR_RESULT=""
    SHELLFRAME_EDITOR_LINES=("hello world" "hi" "goodbye world")
    shellframe_editor_init "ed" 10
    printf -v "_SHELLFRAME_ED_ed_VWIDTH" '%d' 20
}

ptyunit_test_begin "no_wrap move_up: stores goal_col and clamps col on shorter line"
_reset_nowrap_multiline
printf -v _SHELLFRAME_ED_ed_ROW      '%d' 2   # row 2: "goodbye world"
printf -v _SHELLFRAME_ED_ed_COL      '%d' 9   # col 9
printf -v _SHELLFRAME_ED_ed_GOAL_COL '%d' -1  # fresh goal col
_shellframe_ed_move_up "ed"
# "hi" has len=2 → col clamps to 2; GOAL_COL stored as 9
assert_output "1" shellframe_editor_row "ed"
assert_output "2" shellframe_editor_col "ed"
_gc_var="_SHELLFRAME_ED_ed_GOAL_COL"
assert_eq "9" "${!_gc_var}" "GOAL_COL stored as original col=9"

ptyunit_test_begin "no_wrap move_down: restores goal_col on longer line"
# State from previous: row=1, col=2, GOAL_COL=9
_shellframe_ed_move_down "ed"
# "goodbye world" len=13; GOAL_COL=9 used; 9<=13 → col=9
assert_output "2" shellframe_editor_row "ed"
assert_output "9" shellframe_editor_col "ed"

# ── no-wrap mode: page up / down ──────────────────────────────────────────────

_reset_nowrap_page() {
    SHELLFRAME_EDITOR_WRAP=0
    SHELLFRAME_EDITOR_CTX="ed"
    SHELLFRAME_EDITOR_FOCUSED=0
    SHELLFRAME_EDITOR_RESULT=""
    SHELLFRAME_EDITOR_LINES=()
    local _pi
    for (( _pi=0; _pi<20; _pi++ )); do SHELLFRAME_EDITOR_LINES+=("line${_pi}"); done
    shellframe_editor_init "ed" 5   # viewport = 5 rows
}

ptyunit_test_begin "no_wrap page_down: moves cursor down by viewport rows"
_reset_nowrap_page
_shellframe_ed_page_down "ed"
assert_output "5" shellframe_editor_row "ed"

ptyunit_test_begin "no_wrap page_up: moves cursor back up by viewport rows"
# State from previous: row=5
_shellframe_ed_page_up "ed"
assert_output "0" shellframe_editor_row "ed"

# Restore wrap=1 for safety
SHELLFRAME_EDITOR_WRAP=1

# ── Dirty-region integration ──────────────────────────────────────────────────
_SHELLFRAME_SHELL_DIRTY=0
shellframe_shell_mark_dirty() { _SHELLFRAME_SHELL_DIRTY=1; }

ptyunit_test_begin "editor_on_key: marks dirty on printable character"
shellframe_editor_init "e"
SHELLFRAME_EDITOR_CTX="e"
_SHELLFRAME_SHELL_DIRTY=0
shellframe_editor_on_key "a" || true
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "dirty set on char insert"

ptyunit_test_begin "editor_on_key: does not mark dirty on unrecognized key"
shellframe_editor_init "e"
SHELLFRAME_EDITOR_CTX="e"
_SHELLFRAME_SHELL_DIRTY=0
shellframe_editor_on_key $'\033[20~' || true   # F9 — not handled
assert_eq "0" "$_SHELLFRAME_SHELL_DIRTY" "dirty not set on unrecognized key"

ptyunit_test_summary
