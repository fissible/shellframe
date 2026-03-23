#!/usr/bin/env bash
# tests/unit/test-app.sh — Unit tests for shellframe_app + _shellframe_app_event

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── _shellframe_app_event ────────────────────────────────────────────────────

ptyunit_test_begin "app_event: action-list rc=0 → confirm"
assert_output "confirm" _shellframe_app_event "action-list" 0

ptyunit_test_begin "app_event: action-list rc=1 → quit"
assert_output "quit" _shellframe_app_event "action-list" 1

ptyunit_test_begin "app_event: table rc=0 → confirm"
assert_output "confirm" _shellframe_app_event "table" 0

ptyunit_test_begin "app_event: table rc=1 → quit"
assert_output "quit" _shellframe_app_event "table" 1

ptyunit_test_begin "app_event: confirm rc=0 → yes"
assert_output "yes" _shellframe_app_event "confirm" 0

ptyunit_test_begin "app_event: confirm rc=1 → no"
assert_output "no" _shellframe_app_event "confirm" 1

ptyunit_test_begin "app_event: alert rc=0 → dismiss"
assert_output "dismiss" _shellframe_app_event "alert" 0

ptyunit_test_begin "app_event: alert rc=1 → dismiss (any rc)"
assert_output "dismiss" _shellframe_app_event "alert" 1

# ── shellframe_app event loop ────────────────────────────────────────────────
# Mock all four widget functions so no TTY is needed.

ptyunit_test_begin "shellframe_app: alert screen → dismiss → quit"
ptyunit_mock shellframe_alert --exit 0
ptyunit_mock shellframe_action_list --exit 0
ptyunit_mock shellframe_confirm --exit 0
ptyunit_mock shellframe_table --exit 0

_app_ROOT_type()    { printf 'alert'; }
_app_ROOT_render()  { _SHELLFRAME_APP_TITLE="Hello"; }
_app_ROOT_dismiss() { _SHELLFRAME_APP_NEXT="__QUIT__"; }

shellframe_app "_app" "ROOT"
assert_called "shellframe_alert"
assert_called_with "shellframe_alert" "Hello"

ptyunit_test_begin "shellframe_app: confirm yes → next screen → quit"
ptyunit_mock shellframe_alert --exit 0
ptyunit_mock shellframe_confirm --exit 0   # rc=0 → yes

_app2_ROOT_type()    { printf 'confirm'; }
_app2_ROOT_render()  { _SHELLFRAME_APP_QUESTION="Apply?"; }
_app2_ROOT_yes()     { _SHELLFRAME_APP_NEXT="DONE"; }
_app2_ROOT_no()      { _SHELLFRAME_APP_NEXT="__QUIT__"; }

_app2_DONE_type()    { printf 'alert'; }
_app2_DONE_render()  { _SHELLFRAME_APP_TITLE="Done"; }
_app2_DONE_dismiss() { _SHELLFRAME_APP_NEXT="__QUIT__"; }

shellframe_app "_app2" "ROOT"
assert_called "shellframe_confirm"
assert_called "shellframe_alert"

ptyunit_test_begin "shellframe_app: confirm no → quit"
ptyunit_mock shellframe_confirm --exit 1   # rc=1 → no

_app3_ROOT_type()    { printf 'confirm'; }
_app3_ROOT_render()  { _SHELLFRAME_APP_QUESTION="Proceed?"; }
_app3_ROOT_yes()     { _SHELLFRAME_APP_NEXT="DONE"; }
_app3_ROOT_no()      { _SHELLFRAME_APP_NEXT="__QUIT__"; }

shellframe_app "_app3" "ROOT"
assert_called_times "shellframe_confirm" 1
assert_not_called "shellframe_alert"

ptyunit_test_summary
