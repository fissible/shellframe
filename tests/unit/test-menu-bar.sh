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

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
# ptyunit coverage uses BASH_XTRACEFD=3; widgets write to >&3. Dup the trace fd
# to 4 first, then redirect fd 3 to /dev/null so render output is discarded
# without killing the trace. In normal (non-coverage) runs fd 3 is not open, so
# exec 4>&3 is a silent no-op.
exec 4>&3 2>/dev/null || true   # dup trace fd; no-op outside coverage mode
exec 3>/dev/null                 # discard widget render output
BASH_XTRACEFD=4                  # keep trace on fd 4, safe from >&3 redirects

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

# ── on_key DROPDOWN state ──────────────────────────────────────────────────────

# Helper: put widget in dropdown state with File menu open
_open_file_dd() {
    _reset_mb
    shellframe_menubar_on_focus 1
    shellframe_menubar_on_key "$SHELLFRAME_KEY_ENTER"   # → dropdown
}

ptyunit_test_begin "on_key DROPDOWN: Down moves cursor, skips separator"
_open_file_dd
# SHELLFRAME_MENU_FILE=("Open" "Save" "---" "@RECENT:Recent Files" "---" "Quit")
# cursor starts at 0 (Open); Down → 1 (Save); Down → 3 (skips ---)
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
assert_output "3" shellframe_sel_cursor "mb_mb_dd"

ptyunit_test_begin "on_key DROPDOWN: Up moves cursor, skips separator"
_open_file_dd
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"  # → 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_UP"    # → 0
assert_output "0" shellframe_sel_cursor "mb_mb_dd"

ptyunit_test_begin "on_key DROPDOWN: Enter on leaf → RESULT + rc=2"
_open_file_dd
# cursor at 0 = "Open" (leaf), bar=0=File
shellframe_menubar_on_key "$SHELLFRAME_KEY_ENTER"; _rc=$?
assert_eq "2" "$_rc" "Enter on leaf returns 2"
assert_eq "File|Open" "$SHELLFRAME_MENUBAR_RESULT" "RESULT=File|Open"

ptyunit_test_begin "on_key DROPDOWN: Enter on sigil item → submenu state"
_open_file_dd
# Move to index 3 = "@RECENT:Recent Files"
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
shellframe_menubar_on_key "$SHELLFRAME_KEY_ENTER"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "submenu" "${!_st_var}" "state=submenu"

ptyunit_test_begin "on_key DROPDOWN: Right on sigil item → submenu state"
_open_file_dd
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
shellframe_menubar_on_key "$SHELLFRAME_KEY_RIGHT"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "submenu" "${!_st_var}" "state=submenu via Right"

ptyunit_test_begin "on_key DROPDOWN: Right on leaf → moves to next top-level menu"
_open_file_dd
# cursor at 0 (leaf=Open); Right should move to Edit
shellframe_menubar_on_key "$SHELLFRAME_KEY_RIGHT"
_idx_var="_SHELLFRAME_MB_mb_BAR_IDX"
assert_eq "1" "${!_idx_var}" "bar_idx=1 (Edit)"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "dropdown" "${!_st_var}" "still in dropdown"

ptyunit_test_begin "on_key DROPDOWN: Left moves to previous top-level menu"
_open_file_dd
shellframe_menubar_on_key "$SHELLFRAME_KEY_RIGHT"  # File→Edit
shellframe_menubar_on_key "$SHELLFRAME_KEY_LEFT"   # Edit→File
_idx_var="_SHELLFRAME_MB_mb_BAR_IDX"
assert_eq "0" "${!_idx_var}" "bar_idx=0 (File)"

ptyunit_test_begin "on_key DROPDOWN: Left/Right cursor resets to first selectable"
_open_file_dd
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"  # cursor→1
shellframe_menubar_on_key "$SHELLFRAME_KEY_RIGHT" # → Edit menu
assert_output "0" shellframe_sel_cursor "mb_mb_dd"

ptyunit_test_begin "on_key DROPDOWN: Esc → bar state"
_open_file_dd
shellframe_menubar_on_key "$SHELLFRAME_KEY_ESC"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "bar" "${!_st_var}" "state=bar after Esc"

ptyunit_test_begin "on_key DROPDOWN: separator never reached by Down"
_open_file_dd
# MENU_FILE: Open(0) Save(1) ---(2) @RECENT(3) ---(4) Quit(5)
# Down×4 from 0 should land at Quit(5), skipping both ---
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
assert_output "5" shellframe_sel_cursor "mb_mb_dd"

# ── on_key SUBMENU state ───────────────────────────────────────────────────────

# Helper: put widget in submenu state (File → Recent Files)
_open_submenu() {
    _open_file_dd
    shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"   # → Save(1)
    shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"   # → @RECENT(3)
    shellframe_menubar_on_key "$SHELLFRAME_KEY_ENTER"  # → submenu
}

ptyunit_test_begin "on_key SUBMENU: Down moves submenu cursor"
_open_submenu
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"
assert_output "1" shellframe_sel_cursor "mb_mb_sm"

ptyunit_test_begin "on_key SUBMENU: Enter → RESULT with full path, rc=2"
_open_submenu
shellframe_menubar_on_key "$SHELLFRAME_KEY_ENTER"; _rc=$?
assert_eq "2" "$_rc" "Enter returns 2"
assert_eq "File|Recent Files|demo.db" "$SHELLFRAME_MENUBAR_RESULT" "full path RESULT"

ptyunit_test_begin "on_key SUBMENU: Enter on item 1 → correct RESULT"
_open_submenu
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"   # → work.db
shellframe_menubar_on_key "$SHELLFRAME_KEY_ENTER"; _rc=$?
assert_eq "File|Recent Files|work.db" "$SHELLFRAME_MENUBAR_RESULT" "RESULT=work.db"

ptyunit_test_begin "on_key SUBMENU: Esc → dropdown, cursor restored to ▶ item"
_open_submenu
shellframe_menubar_on_key "$SHELLFRAME_KEY_ESC"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "dropdown" "${!_st_var}" "state=dropdown"
assert_output "3" shellframe_sel_cursor "mb_mb_dd"

ptyunit_test_begin "on_key SUBMENU: Left → dropdown, cursor restored to ▶ item"
_open_submenu
shellframe_menubar_on_key "$SHELLFRAME_KEY_LEFT"
assert_output "3" shellframe_sel_cursor "mb_mb_dd"

ptyunit_test_begin "on_key SUBMENU: on_focus 0 → idle"
_open_submenu
shellframe_menubar_on_focus 0
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "idle" "${!_st_var}" "state=idle"

# ── shellframe_menubar_open ────────────────────────────────────────────────────

ptyunit_test_begin "menubar_open: opens named menu, state=dropdown"
_reset_mb
shellframe_menubar_open "Edit"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "dropdown" "${!_st_var}" "state=dropdown"
_idx_var="_SHELLFRAME_MB_mb_BAR_IDX"
assert_eq "1" "${!_idx_var}" "bar_idx=1 (Edit)"

ptyunit_test_begin "menubar_open: sets FOCUSED=1"
_reset_mb
shellframe_menubar_open "File"
assert_eq "1" "$SHELLFRAME_MENUBAR_FOCUSED" "FOCUSED=1"

ptyunit_test_begin "menubar_open: unknown name returns 1, no state change"
_reset_mb
shellframe_menubar_open "Nonexistent"; _rc=$?
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "1" "$_rc" "unknown name returns 1"
assert_eq "idle" "${!_st_var}" "state unchanged (idle)"

ptyunit_test_begin "on_key BAR: Up → idle, RESULT empty, returns 2"
_reset_mb
shellframe_menubar_on_focus 1
shellframe_menubar_on_key "$SHELLFRAME_KEY_UP"; _rc=$?
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "2" "$_rc" "Up returns 2"
assert_eq "idle" "${!_st_var}" "state=idle"
assert_eq "" "$SHELLFRAME_MENUBAR_RESULT" "RESULT empty"

ptyunit_test_begin "on_key DROPDOWN: Up at first selectable → bar state"
_open_file_dd
# cursor is at 0 (Open = first selectable); Up should close dropdown
shellframe_menubar_on_key "$SHELLFRAME_KEY_UP"
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "bar" "${!_st_var}" "state=bar after Up at top"

ptyunit_test_begin "on_key DROPDOWN: Up from second item moves up, does not close"
_open_file_dd
shellframe_menubar_on_key "$SHELLFRAME_KEY_DOWN"   # cursor → Save(1)
shellframe_menubar_on_key "$SHELLFRAME_KEY_UP"     # cursor → Open(0)
_st_var="_SHELLFRAME_MB_mb_STATE"
assert_eq "dropdown" "${!_st_var}" "still dropdown"
assert_output "0" shellframe_sel_cursor "mb_mb_dd"

# ── Dirty-region integration ──────────────────────────────────────────────────
_SHELLFRAME_SHELL_DIRTY=0
shellframe_shell_mark_dirty() { _SHELLFRAME_SHELL_DIRTY=1; }

ptyunit_test_begin "menubar_on_key: marks dirty on Right in BAR state"
_reset_mb
SHELLFRAME_MENUBAR_CTX="mb"
shellframe_menubar_on_focus 1   # → BAR state
_SHELLFRAME_SHELL_DIRTY=0
shellframe_menubar_on_key $'\033[C' || true   # Right arrow
assert_eq "1" "$_SHELLFRAME_SHELL_DIRTY" "dirty set in BAR state"

ptyunit_test_begin "menubar_on_key: does not mark dirty on unrecognized key in IDLE"
_reset_mb
SHELLFRAME_MENUBAR_CTX="mb"
shellframe_menubar_on_focus 0   # → IDLE state
_SHELLFRAME_SHELL_DIRTY=0
shellframe_menubar_on_key "x" || true
assert_eq "0" "$_SHELLFRAME_SHELL_DIRTY" "dirty not set on unrecognized key in IDLE"

ptyunit_test_summary
