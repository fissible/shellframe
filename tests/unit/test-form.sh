#!/usr/bin/env bash
_SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$_SHELLFRAME_DIR/src/clip.sh"
source "$_SHELLFRAME_DIR/src/draw.sh"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$_SHELLFRAME_DIR/src/cursor.sh"
source "$_SHELLFRAME_DIR/src/widgets/input-field.sh"
source "$_SHELLFRAME_DIR/src/widgets/form.sh"
source "$PTYUNIT_HOME/assert.sh"

_setup_form() {
    SHELLFRAME_FORM_FIELDS=(
        "Name"$'\t'"f_name"$'\t'"text"
        "Email"$'\t'"f_email"$'\t'"text"
        "Notes"$'\t'"f_notes"$'\t'"text"
    )
    shellframe_form_init "myform"
}

ptyunit_test_begin "form_init: initializes cursor contexts for each field"
_setup_form
_text=""
shellframe_cur_text "f_name" _text
assert_eq "" "$_text" "init: f_name cursor initialized (empty)"
shellframe_cur_text "f_email" _text
assert_eq "" "$_text" "init: f_email cursor initialized (empty)"

ptyunit_test_begin "form_init: sets focus to field 0"
_setup_form
_focus_var="_SHELLFRAME_FORM_myform_FOCUS"
assert_eq "0" "${!_focus_var}" "init: focus starts at 0"

ptyunit_test_begin "form_set_value: pre-fills field by index"
_setup_form
shellframe_form_set_value "myform" 0 "Alice"
_text=""
shellframe_cur_text "f_name" _text
assert_eq "Alice" "$_text" "set_value: f_name set to Alice"

ptyunit_test_begin "form_values: reads all field values"
_setup_form
shellframe_form_set_value "myform" 0 "Alice"
shellframe_form_set_value "myform" 1 "alice@example.com"
_vals=()
shellframe_form_values "myform" _vals
assert_eq "3" "${#_vals[@]}" "values: returns 3 entries"
assert_eq "Alice" "${_vals[0]}" "values: index 0 is Alice"
assert_eq "alice@example.com" "${_vals[1]}" "values: index 1 is email"
assert_eq "" "${_vals[2]}" "values: index 2 is empty"

ptyunit_test_begin "form_on_key: Tab advances focus"
_setup_form
shellframe_form_on_key "myform" $'\t'
_focus_var="_SHELLFRAME_FORM_myform_FOCUS"
assert_eq "1" "${!_focus_var}" "Tab: focus moves to 1"

ptyunit_test_begin "form_on_key: Tab wraps at last field"
_setup_form
shellframe_form_on_key "myform" $'\t'
shellframe_form_on_key "myform" $'\t'
shellframe_form_on_key "myform" $'\t'
_focus_var="_SHELLFRAME_FORM_myform_FOCUS"
assert_eq "0" "${!_focus_var}" "Tab wrap: focus back to 0"

ptyunit_test_begin "form_on_key: Shift-Tab moves back"
_setup_form
shellframe_form_on_key "myform" $'\t'   # → 1
shellframe_form_on_key "myform" $'\033[Z'  # Shift-Tab → 0
_focus_var="_SHELLFRAME_FORM_myform_FOCUS"
assert_eq "0" "${!_focus_var}" "Shift-Tab: focus back to 0"

ptyunit_test_begin "form_on_key: Shift-Tab wraps from 0 to last"
_setup_form
shellframe_form_on_key "myform" $'\033[Z'
_focus_var="_SHELLFRAME_FORM_myform_FOCUS"
assert_eq "2" "${!_focus_var}" "Shift-Tab from 0: wraps to last"

ptyunit_test_begin "form_on_key: Enter returns 2 (submit)"
_setup_form
shellframe_form_on_key "myform" $'\r'
_rc=$?
assert_eq "2" "$_rc" "Enter: returns 2"

ptyunit_test_begin "form_on_key: Esc returns 1 (cancel)"
_setup_form
shellframe_form_on_key "myform" $'\033'
_rc=$?
assert_eq "1" "$_rc" "Esc: returns 1"

ptyunit_test_begin "form_on_key: printable keys forwarded to focused field"
_setup_form
shellframe_form_on_key "myform" "A"
shellframe_form_on_key "myform" "l"
shellframe_form_on_key "myform" "i"
shellframe_form_on_key "myform" "c"
shellframe_form_on_key "myform" "e"
_text=""
shellframe_cur_text "f_name" _text
assert_eq "Alice" "$_text" "printable: text typed into focused field"

ptyunit_test_begin "form_on_key: readonly field skipped on Tab from previous"
SHELLFRAME_FORM_FIELDS=(
    "Name2"$'\t'"f_name2"$'\t'"text"
    "ID"$'\t'"f_id2"$'\t'"readonly"
    "Email2"$'\t'"f_email2"$'\t'"text"
)
shellframe_form_init "rdform"
# focus is 0 (Name2). Tab should skip readonly ID (1) → land on Email2 (2)
shellframe_form_on_key "rdform" $'\t'
_focus_var="_SHELLFRAME_FORM_rdform_FOCUS"
assert_eq "2" "${!_focus_var}" "readonly skip: Tab skips readonly field to 2"

ptyunit_test_begin "form_set_error: sets error message"
_setup_form
shellframe_form_set_error "myform" "Name is required"
_err_var="_SHELLFRAME_FORM_myform_ERROR"
assert_eq "Name is required" "${!_err_var}" "set_error: error stored"

ptyunit_test_begin "form_set_error: clears error with empty string"
_setup_form
shellframe_form_set_error "myform" "some error"
shellframe_form_set_error "myform" ""
_err_var="_SHELLFRAME_FORM_myform_ERROR"
assert_eq "" "${!_err_var}" "set_error: cleared with empty string"

ptyunit_test_summary
