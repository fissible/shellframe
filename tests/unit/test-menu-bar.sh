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
