#!/usr/bin/env bash
# tests/unit/test-modal.sh — Unit tests for src/widgets/modal.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/cursor.sh"
source "$SHELLFRAME_DIR/src/panel.sh"
source "$SHELLFRAME_DIR/src/widgets/input-field.sh"
source "$SHELLFRAME_DIR/src/widgets/modal.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── Helpers ────────────────────────────────────────────────────────────────────

_reset_modal() {
    SHELLFRAME_MODAL_TITLE=""
    SHELLFRAME_MODAL_MESSAGE="Are you sure?"
    SHELLFRAME_MODAL_BUTTONS=("OK" "Cancel")
    SHELLFRAME_MODAL_ACTIVE_BTN=0
    SHELLFRAME_MODAL_STYLE="single"
    SHELLFRAME_MODAL_FOCUSED=0
    SHELLFRAME_MODAL_WIDTH=0
    SHELLFRAME_MODAL_HEIGHT=0
    SHELLFRAME_MODAL_INPUT=0
    SHELLFRAME_MODAL_INPUT_CTX="modal_input"
    SHELLFRAME_MODAL_RESULT=-1
}

# ── shellframe_modal_on_key: Enter ─────────────────────────────────────────────

ptyunit_test_begin "modal_on_key: Enter (\\r) returns 2"
_reset_modal
shellframe_modal_on_key $'\r'
assert_eq "2" "$?" "Enter returns 2"

ptyunit_test_begin "modal_on_key: Enter sets RESULT to active button index"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=1
shellframe_modal_on_key $'\r'
assert_eq "1" "$SHELLFRAME_MODAL_RESULT" "RESULT = 1 (Cancel)"

ptyunit_test_begin "modal_on_key: Enter (\\n) returns 2"
_reset_modal
shellframe_modal_on_key $'\n'
assert_eq "2" "$?" "newline returns 2"

ptyunit_test_begin "modal_on_key: Enter (\\n) sets RESULT to active button"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_on_key $'\n'
assert_eq "0" "$SHELLFRAME_MODAL_RESULT" "RESULT = 0 (OK)"

# ── shellframe_modal_on_key: Escape ───────────────────────────────────────────

ptyunit_test_begin "modal_on_key: Escape returns 2"
_reset_modal
shellframe_modal_on_key $'\033'
assert_eq "2" "$?" "Escape returns 2"

ptyunit_test_begin "modal_on_key: Escape sets RESULT to -1"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_on_key $'\033'
assert_eq "-1" "$SHELLFRAME_MODAL_RESULT" "RESULT = -1 (dismiss)"

# ── shellframe_modal_on_key: Left/Right arrow ─────────────────────────────────

ptyunit_test_begin "modal_on_key: right arrow increments active button"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_on_key $'\033[C'
assert_eq "0" "$?" "right returns 0"
assert_eq "1" "$SHELLFRAME_MODAL_ACTIVE_BTN" "active incremented to 1"

ptyunit_test_begin "modal_on_key: right arrow clamps at last button"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=1
shellframe_modal_on_key $'\033[C'
assert_eq "1" "$SHELLFRAME_MODAL_ACTIVE_BTN" "active stays at 1 (last)"

ptyunit_test_begin "modal_on_key: left arrow decrements active button"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=1
shellframe_modal_on_key $'\033[D'
assert_eq "0" "$?" "left returns 0"
assert_eq "0" "$SHELLFRAME_MODAL_ACTIVE_BTN" "active decremented to 0"

ptyunit_test_begin "modal_on_key: left arrow clamps at 0"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_on_key $'\033[D'
assert_eq "0" "$SHELLFRAME_MODAL_ACTIVE_BTN" "active stays at 0"

# ── shellframe_modal_on_key: Tab ──────────────────────────────────────────────

ptyunit_test_begin "modal_on_key: Tab increments active button"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_on_key $'\t'
assert_eq "0" "$?" "Tab returns 0"
assert_eq "1" "$SHELLFRAME_MODAL_ACTIVE_BTN" "Tab moves to next button"

ptyunit_test_begin "modal_on_key: Tab clamps at last button"
_reset_modal
SHELLFRAME_MODAL_ACTIVE_BTN=1
shellframe_modal_on_key $'\t'
assert_eq "1" "$SHELLFRAME_MODAL_ACTIVE_BTN" "Tab clamps at 1"

# ── shellframe_modal_on_key: single-button modal ──────────────────────────────

ptyunit_test_begin "modal_on_key: single button — right does nothing"
_reset_modal
SHELLFRAME_MODAL_BUTTONS=("OK")
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_on_key $'\033[C'
assert_eq "0" "$SHELLFRAME_MODAL_ACTIVE_BTN" "single button: right clamps at 0"

ptyunit_test_begin "modal_on_key: single button — Enter sets RESULT=0"
_reset_modal
SHELLFRAME_MODAL_BUTTONS=("OK")
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_on_key $'\r'
assert_eq "2" "$?" "returns 2"
assert_eq "0" "$SHELLFRAME_MODAL_RESULT" "RESULT=0"

# ── shellframe_modal_on_key: unhandled ────────────────────────────────────────

ptyunit_test_begin "modal_on_key: unhandled key returns 1"
_reset_modal
shellframe_modal_on_key "x"
assert_eq "1" "$?" "unhandled key returns 1"

ptyunit_test_begin "modal_on_key: Page Up returns 1"
_reset_modal
shellframe_modal_on_key $'\033[5~'
assert_eq "1" "$?" "Page Up returns 1"

# ── shellframe_modal_on_key: input mode ──────────────────────────────────────

ptyunit_test_begin "modal_on_key: printable char in input mode goes to field"
_reset_modal
SHELLFRAME_MODAL_INPUT=1
SHELLFRAME_MODAL_INPUT_CTX="mi"
shellframe_field_init "mi"
shellframe_modal_on_key "h"
assert_eq "0" "$?" "returns 0"
assert_output "h" shellframe_cur_text "mi"

ptyunit_test_begin "modal_on_key: Enter in input mode confirms (returns 2)"
_reset_modal
SHELLFRAME_MODAL_INPUT=1
SHELLFRAME_MODAL_INPUT_CTX="mi"
shellframe_field_init "mi"
shellframe_modal_on_key $'\r'
assert_eq "2" "$?" "Enter still returns 2 in input mode"

ptyunit_test_begin "modal_on_key: Esc in input mode dismisses (returns 2)"
_reset_modal
SHELLFRAME_MODAL_INPUT=1
SHELLFRAME_MODAL_INPUT_CTX="mi"
shellframe_field_init "mi"
shellframe_modal_on_key $'\033'
assert_eq "2" "$?" "Esc returns 2 in input mode"
assert_eq "-1" "$SHELLFRAME_MODAL_RESULT" "RESULT=-1"

ptyunit_test_begin "modal_on_key: Tab in input mode cycles buttons, not field"
_reset_modal
SHELLFRAME_MODAL_INPUT=1
SHELLFRAME_MODAL_INPUT_CTX="mi"
shellframe_field_init "mi"
SHELLFRAME_MODAL_ACTIVE_BTN=0
shellframe_modal_on_key $'\t'
assert_eq "1" "$SHELLFRAME_MODAL_ACTIVE_BTN" "Tab cycles button, not field"

# ── shellframe_modal_on_focus ──────────────────────────────────────────────────

ptyunit_test_begin "modal_on_focus: sets FOCUSED=1"
SHELLFRAME_MODAL_FOCUSED=0
shellframe_modal_on_focus 1
assert_eq "1" "$SHELLFRAME_MODAL_FOCUSED" "focused set to 1"

ptyunit_test_begin "modal_on_focus: sets FOCUSED=0"
SHELLFRAME_MODAL_FOCUSED=1
shellframe_modal_on_focus 0
assert_eq "0" "$SHELLFRAME_MODAL_FOCUSED" "focused set to 0"

# ── shellframe_modal_size ──────────────────────────────────────────────────────

ptyunit_test_begin "modal_size: returns 20 7 0 0"
assert_output "20 7 0 0" shellframe_modal_size

ptyunit_test_summary
