#!/usr/bin/env bash
# tests/unit/test-autocomplete.sh — Unit tests for src/widgets/autocomplete.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/src/cursor.sh"
source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/selection.sh"
source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/panel.sh"
source "$SHELLFRAME_DIR/src/widgets/editor.sh"
source "$SHELLFRAME_DIR/src/widgets/context-menu.sh"
source "$SHELLFRAME_DIR/src/widgets/autocomplete.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# ── helpers ───────────────────────────────────────────────────────────────────

_reset_ac() {
    _SHELLFRAME_AC_CTX=""
    _SHELLFRAME_AC_MODE=""
    _SHELLFRAME_AC_ACTIVE=0
    _SHELLFRAME_AC_MATCHES=()
    _SHELLFRAME_AC_PREFIX=""
    SHELLFRAME_AC_RESULT=""
}

# ── shellframe_ac_attach ──────────────────────────────────────────────────────

ptyunit_test_begin "ac_attach: sets _SHELLFRAME_AC_CTX"
_reset_ac
shellframe_ac_attach "myctx" "field"
assert_eq "myctx" "$_SHELLFRAME_AC_CTX"

ptyunit_test_begin "ac_attach: sets _SHELLFRAME_AC_MODE to field"
_reset_ac
shellframe_ac_attach "myctx" "field"
assert_eq "field" "$_SHELLFRAME_AC_MODE"

ptyunit_test_begin "ac_attach: sets _SHELLFRAME_AC_MODE to editor"
_reset_ac
shellframe_ac_attach "myctx" "editor"
assert_eq "editor" "$_SHELLFRAME_AC_MODE"

ptyunit_test_begin "ac_attach: resets active to 0"
_reset_ac
_SHELLFRAME_AC_ACTIVE=1
shellframe_ac_attach "myctx" "field"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"

ptyunit_test_begin "ac_attach: resets prefix to empty"
_reset_ac
_SHELLFRAME_AC_PREFIX="oldprefix"
shellframe_ac_attach "myctx" "field"
assert_eq "" "$_SHELLFRAME_AC_PREFIX"

ptyunit_test_begin "ac_attach: resets matches to empty array"
_reset_ac
_SHELLFRAME_AC_MATCHES=("a" "b" "c")
shellframe_ac_attach "myctx" "field"
assert_eq "0" "${#_SHELLFRAME_AC_MATCHES[@]}"

ptyunit_test_begin "ac_attach: works for editor mode"
_reset_ac
shellframe_ac_attach "edctx" "editor"
assert_eq "edctx" "$_SHELLFRAME_AC_CTX"
assert_eq "editor" "$_SHELLFRAME_AC_MODE"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"

# ── shellframe_ac_detach ──────────────────────────────────────────────────────

ptyunit_test_begin "ac_detach: clears _SHELLFRAME_AC_CTX"
_reset_ac
shellframe_ac_attach "myctx" "field"
shellframe_ac_detach
assert_eq "" "$_SHELLFRAME_AC_CTX"

ptyunit_test_begin "ac_detach: clears _SHELLFRAME_AC_MODE"
_reset_ac
shellframe_ac_attach "myctx" "field"
shellframe_ac_detach
assert_eq "" "$_SHELLFRAME_AC_MODE"

ptyunit_test_begin "ac_detach: clears _SHELLFRAME_AC_ACTIVE"
_reset_ac
shellframe_ac_attach "myctx" "field"
_SHELLFRAME_AC_ACTIVE=1
shellframe_ac_detach
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"

ptyunit_test_begin "ac_detach: clears _SHELLFRAME_AC_PREFIX"
_reset_ac
_SHELLFRAME_AC_PREFIX="some_prefix"
shellframe_ac_detach
assert_eq "" "$_SHELLFRAME_AC_PREFIX"

ptyunit_test_begin "ac_detach: clears _SHELLFRAME_AC_MATCHES array"
_reset_ac
_SHELLFRAME_AC_MATCHES=("x" "y")
shellframe_ac_detach
assert_eq "0" "${#_SHELLFRAME_AC_MATCHES[@]}"

ptyunit_test_begin "ac_detach: clears SHELLFRAME_AC_RESULT"
_reset_ac
SHELLFRAME_AC_RESULT="something"
shellframe_ac_detach
assert_eq "" "$SHELLFRAME_AC_RESULT"

# ── _shellframe_ac_prefix: field mode ────────────────────────────────────────

ptyunit_test_begin "ac_prefix field: extracts word at end of text"
_reset_ac
shellframe_cur_init "f" "hello"
shellframe_ac_attach "f" "field"
_out=""
_shellframe_ac_prefix _out
assert_eq "hello" "$_out"

ptyunit_test_begin "ac_prefix field: extracts partial word at end"
_reset_ac
shellframe_cur_init "f" "foo bar"
shellframe_ac_attach "f" "field"
_out=""
_shellframe_ac_prefix _out
assert_eq "bar" "$_out"

ptyunit_test_begin "ac_prefix field: cursor in middle of word"
_reset_ac
shellframe_cur_init "f" "hello"
shellframe_cur_set "f" "hello" 3
shellframe_ac_attach "f" "field"
_out=""
_shellframe_ac_prefix _out
assert_eq "hel" "$_out"

ptyunit_test_begin "ac_prefix field: cursor after space returns empty"
_reset_ac
shellframe_cur_init "f" "foo "
shellframe_ac_attach "f" "field"
_out=""
_shellframe_ac_prefix _out
assert_eq "" "$_out"

ptyunit_test_begin "ac_prefix field: word with underscore and dot"
_reset_ac
shellframe_cur_init "f" "foo.bar_baz"
shellframe_ac_attach "f" "field"
_out=""
_shellframe_ac_prefix _out
assert_eq "foo.bar_baz" "$_out"

ptyunit_test_begin "ac_prefix field: word with hyphen"
_reset_ac
shellframe_cur_init "f" "my-option"
shellframe_ac_attach "f" "field"
_out=""
_shellframe_ac_prefix _out
assert_eq "my-option" "$_out"

ptyunit_test_begin "ac_prefix field: empty text returns empty"
_reset_ac
shellframe_cur_init "f" ""
shellframe_ac_attach "f" "field"
_out=""
_shellframe_ac_prefix _out
assert_eq "" "$_out"

ptyunit_test_begin "ac_prefix field: cursor at position 0 returns empty"
_reset_ac
shellframe_cur_set "f" "hello" 0
shellframe_ac_attach "f" "field"
_out=""
_shellframe_ac_prefix _out
assert_eq "" "$_out"

# ── _shellframe_ac_prefix: editor mode ───────────────────────────────────────

ptyunit_test_begin "ac_prefix editor: extracts word at end of line"
_reset_ac
SHELLFRAME_EDITOR_CTX="ed"
SHELLFRAME_EDITOR_LINES=()
shellframe_editor_init "ed" 10
shellframe_editor_set_text "ed" "foo bar"
# cursor is at 0,0 after set_text — move to end of line
shellframe_editor_on_key $'\033[F'
shellframe_ac_attach "ed" "editor"
_out=""
_shellframe_ac_prefix _out
assert_eq "bar" "$_out"

ptyunit_test_begin "ac_prefix editor: single word on line"
_reset_ac
SHELLFRAME_EDITOR_CTX="ed"
SHELLFRAME_EDITOR_LINES=()
shellframe_editor_init "ed" 10
shellframe_editor_set_text "ed" "hello"
shellframe_editor_on_key $'\033[F'
shellframe_ac_attach "ed" "editor"
_out=""
_shellframe_ac_prefix _out
assert_eq "hello" "$_out"

ptyunit_test_begin "ac_prefix editor: empty line returns empty"
_reset_ac
SHELLFRAME_EDITOR_CTX="ed"
SHELLFRAME_EDITOR_LINES=()
shellframe_editor_init "ed" 10
shellframe_editor_set_text "ed" ""
shellframe_ac_attach "ed" "editor"
_out=""
_shellframe_ac_prefix _out
assert_eq "" "$_out"

# ── shellframe_ac_dismiss ─────────────────────────────────────────────────────

ptyunit_test_begin "ac_dismiss: sets _SHELLFRAME_AC_ACTIVE to 0"
_reset_ac
_SHELLFRAME_AC_ACTIVE=1
shellframe_ac_dismiss
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"

ptyunit_test_begin "ac_dismiss: clears _SHELLFRAME_AC_MATCHES"
_reset_ac
_SHELLFRAME_AC_MATCHES=("foo" "bar")
shellframe_ac_dismiss
assert_eq "0" "${#_SHELLFRAME_AC_MATCHES[@]}"

ptyunit_test_begin "ac_dismiss: clears _SHELLFRAME_AC_PREFIX"
_reset_ac
_SHELLFRAME_AC_PREFIX="fo"
shellframe_ac_dismiss
assert_eq "" "$_SHELLFRAME_AC_PREFIX"

ptyunit_test_begin "ac_prefix: stops at non-word chars like @"
_reset_ac
shellframe_cur_init "pfspecial" "user@us"
shellframe_ac_attach "pfspecial" "field"
_pfx=""
_shellframe_ac_prefix _pfx
assert_eq "us" "$_pfx" "stops at @ boundary"

# ── _shellframe_ac_update ─────────────────────────────────────────────────────

_test_provider() {
    local _prefix="$1" _out="$2"
    local _all=("users" "user_roles" "products" "profiles")
    local _matches=()
    local _i
    for _i in "${_all[@]}"; do
        case "$_i" in "${_prefix}"*) _matches+=("$_i") ;; esac
    done
    eval "$_out=(\"\${_matches[@]+\"\${_matches[@]}\"}\")"
}

ptyunit_test_begin "ac_update: populates matches from provider"
_reset_ac
shellframe_cur_init "upd1" "us"
shellframe_ac_attach "upd1" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
_shellframe_ac_update
assert_eq "2" "${#_SHELLFRAME_AC_MATCHES[@]}"
assert_eq "users" "${_SHELLFRAME_AC_MATCHES[0]}"
assert_eq "user_roles" "${_SHELLFRAME_AC_MATCHES[1]}"

ptyunit_test_begin "ac_update: activates popup when matches > 1"
_reset_ac
shellframe_cur_init "upd2" "us"
shellframe_ac_attach "upd2" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
_shellframe_ac_update
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE"

ptyunit_test_begin "ac_update: deactivates when 0 matches"
_reset_ac
shellframe_cur_init "upd3" "xyz"
shellframe_ac_attach "upd3" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
_shellframe_ac_update
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"
assert_eq "0" "${#_SHELLFRAME_AC_MATCHES[@]}"

ptyunit_test_begin "ac_update: single match does not open popup (tab trigger)"
_reset_ac
shellframe_cur_init "upd4" "prod"
shellframe_ac_attach "upd4" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
_shellframe_ac_update
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"
SHELLFRAME_AC_TRIGGER="auto"

ptyunit_test_begin "ac_update: single match opens popup in auto mode"
_reset_ac
shellframe_cur_init "upd5" "prod"
shellframe_ac_attach "upd5" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="auto"
_shellframe_ac_update
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE"

# ── shellframe_ac_on_key ─────────────────────────────────────────────────────

ptyunit_test_begin "ac_on_key: idle returns 1 for unrelated key"
_reset_ac
shellframe_cur_init "ok1" "hello"
shellframe_ac_attach "ok1" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
shellframe_ac_on_key "x"
assert_eq "1" "$?"

ptyunit_test_begin "ac_on_key: Tab triggers popup in tab mode"
_reset_ac
shellframe_cur_init "ok2" "us"
shellframe_ac_attach "ok2" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
assert_eq "0" "$?"
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE"
SHELLFRAME_AC_TRIGGER="auto"

ptyunit_test_begin "ac_on_key: Tab auto-completes single match"
_reset_ac
shellframe_cur_init "ok3" "prod"
shellframe_ac_attach "ok3" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
assert_eq "0" "$?"
_ok3_text=""
shellframe_cur_text "ok3" _ok3_text
assert_eq "products" "$_ok3_text"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"
SHELLFRAME_AC_TRIGGER="auto"

ptyunit_test_begin "ac_on_key: Enter accepts selected suggestion"
_reset_ac
shellframe_cur_init "ok4" "us"
shellframe_ac_attach "ok4" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
shellframe_ac_on_key $'\r'
assert_eq "0" "$?"
_ok4_text=""
shellframe_cur_text "ok4" _ok4_text
assert_eq "users" "$_ok4_text"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"
SHELLFRAME_AC_TRIGGER="auto"

ptyunit_test_begin "ac_on_key: Esc dismisses popup"
_reset_ac
shellframe_cur_init "ok5" "us"
shellframe_ac_attach "ok5" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE"
shellframe_ac_on_key $'\033'
assert_eq "0" "$?"
assert_eq "0" "$_SHELLFRAME_AC_ACTIVE"
SHELLFRAME_AC_TRIGGER="auto"

ptyunit_test_begin "ac_on_key: Down moves selection in active popup"
_reset_ac
shellframe_cur_init "ok6" "us"
shellframe_ac_attach "ok6" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
shellframe_ac_on_key "$SHELLFRAME_KEY_DOWN"
_cur=0
shellframe_sel_cursor "ac_popup" _cur
assert_eq "1" "$_cur"
SHELLFRAME_AC_TRIGGER="auto"

# ── shellframe_ac_render ─────────────────────────────────────────────────────

ptyunit_test_begin "ac_render: inactive produces no framebuffer output"
_reset_ac
shellframe_cur_init "rn1" "hello"
shellframe_ac_attach "rn1" "field"
# _SHELLFRAME_AC_ACTIVE is already 0 from _reset_ac / attach
_SF_ROW_PREV=()
shellframe_fb_frame_start 24 80
_f=$(mktemp)
exec 3>"$_f"
shellframe_ac_render 1 1 80 24 5 10
shellframe_screen_flush
exec 3>&- 2>/dev/null || true
_rn1_content=$(cat "$_f")
rm -f "$_f"
assert_eq "" "$_rn1_content" "inactive: no output expected"

ptyunit_test_begin "ac_render: active renders popup with matches"
_reset_ac
shellframe_cur_init "rn2" "us"
shellframe_ac_attach "rn2" "field"
SHELLFRAME_AC_PROVIDER="_test_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_on_key $'\t'
assert_eq "1" "$_SHELLFRAME_AC_ACTIVE"
_SF_ROW_PREV=()
shellframe_fb_frame_start 24 80
_f=$(mktemp)
exec 3>"$_f"
shellframe_ac_render 1 1 80 24 5 10
shellframe_screen_flush
exec 3>&- 2>/dev/null || true
_rn2_content=$(sed 's/\033\[[0-9;]*[A-Za-z]//g' "$_f")
rm -f "$_f"
SHELLFRAME_AC_TRIGGER="auto"
assert_contains "$_rn2_content" "users" "popup should contain 'users'"
assert_contains "$_rn2_content" "user_roles" "popup should contain 'user_roles'"

ptyunit_test_summary
