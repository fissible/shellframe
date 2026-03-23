#!/usr/bin/env bash
# tests/unit/test-menu-bar.sh — Unit tests for src/widgets/menu-bar.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/selection.sh"
source "$SHELLFRAME_DIR/src/panel.sh"
source "$SHELLFRAME_DIR/src/widgets/menu-bar.sh"
source "$PTYUNIT_HOME/assert.sh"

exec 3>/dev/null   # discard render output (no terminal in unit tests)

# ── Helpers ────────────────────────────────────────────────────────────────────

_reset_mb() {
    SHELLFRAME_MENU_NAMES=("File" "Edit" "View")
    SHELLFRAME_MENU_FILE=("Open" "Save" "---" "@RECENT:Recent Files" "---" "Quit")
    SHELLFRAME_MENU_EDIT=("Undo" "Redo" "---" "Cut" "Copy" "Paste")
    SHELLFRAME_MENU_VIEW=("Zoom In" "Zoom Out" "---" "Full Screen")
    SHELLFRAME_MENU_RECENT=("demo.db" "work.db" "archive.db")
    SHELLFRAME_MENUBAR_CTX="mb"
    SHELLFRAME_MENUBAR_FOCUSED=0
    SHELLFRAME_MENUBAR_RESULT=""
    shellframe_menubar_init "mb"
}

# ── _shellframe_mb_is_sep ──────────────────────────────────────────────────────

ptyunit_test_begin "mb_is_sep: '---' is separator"
_shellframe_mb_is_sep "---"
assert_eq "0" "$?" "--- returns 0"

ptyunit_test_begin "mb_is_sep: plain item is not separator"
_shellframe_mb_is_sep "Open"
assert_eq "1" "$?" "plain item returns 1"

ptyunit_test_begin "mb_is_sep: sigil item is not separator"
_shellframe_mb_is_sep "@RECENT:Recent Files"
assert_eq "1" "$?" "sigil item returns 1"

# ── _shellframe_mb_parse_sigil ────────────────────────────────────────────────

ptyunit_test_begin "mb_parse_sigil: extracts VARNAME from @VARNAME:Label"
_shellframe_mb_parse_sigil "@RECENT:Recent Files" _varname _label
assert_eq "RECENT" "$_varname" "VARNAME extracted"
assert_eq "Recent Files" "$_label" "label extracted"

ptyunit_test_begin "mb_parse_sigil: returns 1 for plain item"
_shellframe_mb_parse_sigil "Open" _varname _label
assert_eq "1" "$?" "plain item returns 1"

ptyunit_test_begin "mb_parse_sigil: returns 1 for separator"
_shellframe_mb_parse_sigil "---" _varname _label
assert_eq "1" "$?" "separator returns 1"

ptyunit_test_begin "mb_parse_sigil: VARNAME validated against [A-Z0-9_]+"
_shellframe_mb_parse_sigil "@bad-name:Label" _varname _label
assert_eq "1" "$?" "invalid VARNAME returns 1"

# ── shellframe_menubar_init ────────────────────────────────────────────────────

ptyunit_test_begin "menubar_init: state starts idle"
_reset_mb
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "idle" "${!_st_var}" "state=idle after init"

ptyunit_test_begin "menubar_init: bar_idx starts 0"
_reset_mb
_idx_var="_SHELLFRAME_MB_mb_BAR_IDX"
assert_eq "0" "${!_idx_var}" "bar_idx=0"

ptyunit_test_begin "menubar_init: PREV_DD_W zeroed"
_reset_mb
_w_var="_SHELLFRAME_MB_mb_PREV_DD_W"
assert_eq "0" "${!_w_var}" "PREV_DD_W=0"

ptyunit_test_begin "menubar_init: dropdown sel context created"
_reset_mb
assert_output "0" shellframe_sel_cursor "mb_mb_dd"

ptyunit_test_begin "menubar_init: submenu sel context created"
_reset_mb
assert_output "0" shellframe_sel_cursor "mb_mb_sm"

# ── shellframe_menubar_on_focus ────────────────────────────────────────────────

ptyunit_test_begin "on_focus 1: state → bar"
_reset_mb
shellframe_menubar_on_focus 1
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "bar" "${!_st_var}" "state=bar"

ptyunit_test_begin "on_focus 1: FOCUSED set"
_reset_mb
shellframe_menubar_on_focus 1
assert_eq "1" "$SHELLFRAME_MENUBAR_FOCUSED" "FOCUSED=1"

ptyunit_test_begin "on_focus 0 from bar: state → idle"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_focus 0
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "idle" "${!_st_var}" "state=idle"

ptyunit_test_begin "on_focus 0 from dropdown: state → idle"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_ENTER"
shellframe_menubar_on_focus 0
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "idle" "${!_st_var}" "state=idle from dropdown"

# ── shellframe_menubar_size ────────────────────────────────────────────────────

ptyunit_test_begin "menubar_size: prints 1 1 0 1"
assert_output "1 1 0 1" shellframe_menubar_size

# ── on_key BAR state ──────────────────────────────────────────────────────────

ptyunit_test_begin "on_key BAR: Right moves bar_idx, wraps"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_RIGHT"
_idx_var="_SHELLFRAME_MB_mb_BAR_IDX"
assert_eq "1" "${!_idx_var}" "bar_idx=1 after Right"

ptyunit_test_begin "on_key BAR: Right wraps from last to 0"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_RIGHT"
shellframe_menubar_on_key "$SHELLFRAME_KEY_RIGHT"
shellframe_menubar_on_key "$SHELLFRAME_KEY_RIGHT"
_idx_var="_SHELLFRAME_MB_mb_BAR_IDX"
assert_eq "0" "${!_idx_var}" "bar_idx wraps to 0"

ptyunit_test_begin "on_key BAR: Left wraps from 0 to last"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_LEFT"
_idx_var="_SHELLFRAME_MB_mb_BAR_IDX"
assert_eq "2" "${!_idx_var}" "bar_idx wraps to 2 (last)"

ptyunit_test_begin "on_key BAR: Enter → dropdown state"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_ENTER"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "dropdown" "${!_st_var}" "state=dropdown"

ptyunit_test_begin "on_key BAR: Down → dropdown state"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "dropdown" "${!_st_var}" "state=dropdown via Down"

ptyunit_test_begin "on_key BAR: Esc → idle, RESULT empty, returns 2"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_ESC"; _rc=$?
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "2" "$_rc" "Esc returns 2"
assert_eq "idle" "${!_st_var}" "state=idle"
assert_eq "" "$SHELLFRAME_MENUBAR_RESULT" "RESULT empty"

ptyunit_test_begin "on_key BAR: unrecognised key returns 1"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "x"; _rc=$?
assert_eq "1" "$_rc" "unrecognised key returns 1"

ptyunit_test_summary
