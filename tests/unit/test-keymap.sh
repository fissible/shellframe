#!/usr/bin/env bash
# tests/unit/test-keymap.sh — Unit tests for src/keymap.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/keymap.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── shellframe_keyname: known key sequences ────────────────────────────────────

ptyunit_test_begin "keyname: up"
assert_output "up" shellframe_keyname "$SHELLFRAME_KEY_UP"

ptyunit_test_begin "keyname: down"
assert_output "down" shellframe_keyname "$SHELLFRAME_KEY_DOWN"

ptyunit_test_begin "keyname: left"
assert_output "left" shellframe_keyname "$SHELLFRAME_KEY_LEFT"

ptyunit_test_begin "keyname: right"
assert_output "right" shellframe_keyname "$SHELLFRAME_KEY_RIGHT"

ptyunit_test_begin "keyname: enter"
assert_output "enter" shellframe_keyname "$SHELLFRAME_KEY_ENTER"

ptyunit_test_begin "keyname: tab"
assert_output "tab" shellframe_keyname "$SHELLFRAME_KEY_TAB"

ptyunit_test_begin "keyname: shift_tab"
assert_output "shift_tab" shellframe_keyname "$SHELLFRAME_KEY_SHIFT_TAB"

ptyunit_test_begin "keyname: space"
assert_output "space" shellframe_keyname "$SHELLFRAME_KEY_SPACE"

ptyunit_test_begin "keyname: esc"
assert_output "esc" shellframe_keyname "$SHELLFRAME_KEY_ESC"

ptyunit_test_begin "keyname: backspace"
assert_output "backspace" shellframe_keyname "$SHELLFRAME_KEY_BACKSPACE"

ptyunit_test_begin "keyname: delete"
assert_output "delete" shellframe_keyname "$SHELLFRAME_KEY_DELETE"

ptyunit_test_begin "keyname: home"
assert_output "home" shellframe_keyname "$SHELLFRAME_KEY_HOME"

ptyunit_test_begin "keyname: end"
assert_output "end" shellframe_keyname "$SHELLFRAME_KEY_END"

ptyunit_test_begin "keyname: page_up"
assert_output "page_up" shellframe_keyname "$SHELLFRAME_KEY_PAGE_UP"

ptyunit_test_begin "keyname: page_down"
assert_output "page_down" shellframe_keyname "$SHELLFRAME_KEY_PAGE_DOWN"

ptyunit_test_begin "keyname: ctrl_a"
assert_output "ctrl_a" shellframe_keyname "$SHELLFRAME_KEY_CTRL_A"

ptyunit_test_begin "keyname: ctrl_e"
assert_output "ctrl_e" shellframe_keyname "$SHELLFRAME_KEY_CTRL_E"

ptyunit_test_begin "keyname: ctrl_k"
assert_output "ctrl_k" shellframe_keyname "$SHELLFRAME_KEY_CTRL_K"

ptyunit_test_begin "keyname: ctrl_u"
assert_output "ctrl_u" shellframe_keyname "$SHELLFRAME_KEY_CTRL_U"

ptyunit_test_begin "keyname: ctrl_w"
assert_output "ctrl_w" shellframe_keyname "$SHELLFRAME_KEY_CTRL_W"

# ── shellframe_keyname: printable single chars ─────────────────────────────────

ptyunit_test_begin "keyname: single char 'q'"
assert_output "q" shellframe_keyname "q"

ptyunit_test_begin "keyname: single char 'A'"
assert_output "A" shellframe_keyname "A"

ptyunit_test_begin "keyname: single char '3'"
assert_output "3" shellframe_keyname "3"

# ── shellframe_keyname: out_var form ──────────────────────────────────────────

ptyunit_test_begin "keyname: out_var stores result"
_kn_result=""
shellframe_keyname "$SHELLFRAME_KEY_UP" _kn_result
assert_eq "up" "$_kn_result"

# ── shellframe_keyname: unknown sequences return empty ────────────────────────

ptyunit_test_begin "keyname: unknown multi-byte sequence returns empty"
assert_output "" shellframe_keyname $'\x1b[999~'

# ── shellframe_keymap_bind + shellframe_keymap_lookup ─────────────────────────

ptyunit_test_begin "keymap_bind/lookup: roundtrip"
shellframe_keymap_bind "tmap" "$SHELLFRAME_KEY_UP" "scroll_up"
assert_output "scroll_up" shellframe_keymap_lookup "tmap" "$SHELLFRAME_KEY_UP"

ptyunit_test_begin "keymap_lookup: unbound key returns empty"
assert_output "" shellframe_keymap_lookup "tmap" "$SHELLFRAME_KEY_DOWN"

ptyunit_test_begin "keymap_bind: overwrite existing binding"
shellframe_keymap_bind "tmap" "$SHELLFRAME_KEY_UP" "move_up"
assert_output "move_up" shellframe_keymap_lookup "tmap" "$SHELLFRAME_KEY_UP"

ptyunit_test_begin "keymap_lookup: out_var form"
_km_action=""
shellframe_keymap_lookup "tmap" "$SHELLFRAME_KEY_UP" _km_action
assert_eq "move_up" "$_km_action"

# ── Two keymaps are independent ───────────────────────────────────────────────

ptyunit_test_begin "keymap: two keymaps do not interfere"
shellframe_keymap_bind "mapA" "$SHELLFRAME_KEY_ENTER" "confirm"
shellframe_keymap_bind "mapB" "$SHELLFRAME_KEY_ENTER" "submit"
assert_output "confirm" shellframe_keymap_lookup "mapA" "$SHELLFRAME_KEY_ENTER"
assert_output "submit"  shellframe_keymap_lookup "mapB" "$SHELLFRAME_KEY_ENTER"

# ── shellframe_keymap_default_nav ─────────────────────────────────────────────

shellframe_keymap_default_nav "nav"

ptyunit_test_begin "default_nav: up → up"
assert_output "up" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_UP"

ptyunit_test_begin "default_nav: down → down"
assert_output "down" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_DOWN"

ptyunit_test_begin "default_nav: enter → confirm"
assert_output "confirm" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_ENTER"

ptyunit_test_begin "default_nav: esc → cancel"
assert_output "cancel" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_ESC"

ptyunit_test_begin "default_nav: q → quit"
assert_output "quit" shellframe_keymap_lookup "nav" "q"

ptyunit_test_begin "default_nav: Q → quit"
assert_output "quit" shellframe_keymap_lookup "nav" "Q"

ptyunit_test_begin "default_nav: space → toggle"
assert_output "toggle" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_SPACE"

ptyunit_test_begin "default_nav: tab → focus_next"
assert_output "focus_next" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_TAB"

ptyunit_test_begin "default_nav: shift_tab → focus_prev"
assert_output "focus_prev" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_SHIFT_TAB"

ptyunit_test_begin "default_nav: page_up → page_up"
assert_output "page_up" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_PAGE_UP"

ptyunit_test_begin "default_nav: page_down → page_down"
assert_output "page_down" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_PAGE_DOWN"

ptyunit_test_begin "default_nav: home → home"
assert_output "home" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_HOME"

ptyunit_test_begin "default_nav: end → end"
assert_output "end" shellframe_keymap_lookup "nav" "$SHELLFRAME_KEY_END"

# ── shellframe_keymap_default_edit ────────────────────────────────────────────

shellframe_keymap_default_edit "edit"

ptyunit_test_begin "default_edit: backspace → backspace"
assert_output "backspace" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_BACKSPACE"

ptyunit_test_begin "default_edit: delete → delete"
assert_output "delete" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_DELETE"

ptyunit_test_begin "default_edit: ctrl_a → home"
assert_output "home" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_CTRL_A"

ptyunit_test_begin "default_edit: ctrl_e → end"
assert_output "end" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_CTRL_E"

ptyunit_test_begin "default_edit: ctrl_k → kill_to_end"
assert_output "kill_to_end" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_CTRL_K"

ptyunit_test_begin "default_edit: ctrl_u → kill_to_start"
assert_output "kill_to_start" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_CTRL_U"

ptyunit_test_begin "default_edit: ctrl_w → kill_word_left"
assert_output "kill_word_left" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_CTRL_W"

ptyunit_test_begin "default_edit: enter → confirm"
assert_output "confirm" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_ENTER"

ptyunit_test_begin "default_edit: esc → cancel"
assert_output "cancel" shellframe_keymap_lookup "edit" "$SHELLFRAME_KEY_ESC"

ptyunit_test_summary
