#!/usr/bin/env bash
# tests/unit/test-shell.sh — Unit tests for src/shell.sh (focus ring + region bookkeeping)
#
# These tests cover the bookkeeping logic only.  The input loop and screen
# rendering require a PTY and are covered by integration tests.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/shell.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# ── Helpers ────────────────────────────────────────────────────────────────────

_reset_shell() {
    _SHELLFRAME_SHELL_REGIONS=()
    _SHELLFRAME_SHELL_FOCUS_RING=()
    _SHELLFRAME_SHELL_FOCUS_IDX=0
    _SHELLFRAME_SHELL_FOCUS_REQUEST=""
    _SHELLFRAME_SHELL_NEXT=""
}

# ── shellframe_shell_region ────────────────────────────────────────────────────

ptyunit_test_begin "shell_region: registers a focus region"
_reset_shell
shellframe_shell_region main 2 1 80 20 focus
assert_eq "1" "${#_SHELLFRAME_SHELL_REGIONS[@]}" "one region registered"
assert_eq "main:2:1:80:20:focus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "entry format correct"

ptyunit_test_begin "shell_region: registers a nofocus region"
_reset_shell
shellframe_shell_region topbar 1 1 80 1 nofocus
assert_eq "topbar:1:1:80:1:nofocus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "nofocus recorded"

ptyunit_test_begin "shell_region: default is focus when 6th arg omitted"
_reset_shell
shellframe_shell_region main 2 1 80 20
assert_eq "main:2:1:80:20:focus" "${_SHELLFRAME_SHELL_REGIONS[0]}" "defaults to focus"

ptyunit_test_begin "shell_region: multiple regions accumulate"
_reset_shell
shellframe_shell_region topbar 1 1 80 1 nofocus
shellframe_shell_region main 2 1 80 20 focus
shellframe_shell_region footer 22 1 80 1 nofocus
assert_eq "3" "${#_SHELLFRAME_SHELL_REGIONS[@]}" "three regions registered"

# ── _shellframe_shell_focus_init ──────────────────────────────────────────────

ptyunit_test_begin "focus_init: builds ring from focusable regions only"
_reset_shell
shellframe_shell_region topbar 1 1 80 1 nofocus
shellframe_shell_region main 2 1 80 20 focus
shellframe_shell_region sidebar 2 60 20 20 focus
shellframe_shell_region footer 22 1 80 1 nofocus
_shellframe_shell_focus_init
assert_eq "2" "${#_SHELLFRAME_SHELL_FOCUS_RING[@]}" "ring has 2 focusable regions"
assert_eq "main" "${_SHELLFRAME_SHELL_FOCUS_RING[0]}" "first focusable is main"
assert_eq "sidebar" "${_SHELLFRAME_SHELL_FOCUS_RING[1]}" "second focusable is sidebar"

ptyunit_test_begin "focus_init: ring is empty when no focusable regions"
_reset_shell
shellframe_shell_region topbar 1 1 80 1 nofocus
shellframe_shell_region footer 24 1 80 1 nofocus
_shellframe_shell_focus_init
assert_eq "0" "${#_SHELLFRAME_SHELL_FOCUS_RING[@]}" "empty ring"

ptyunit_test_begin "focus_init: resets idx to 0 when no prev focus"
_reset_shell
shellframe_shell_region main 2 1 80 20 focus
_SHELLFRAME_SHELL_FOCUS_IDX=99
_shellframe_shell_focus_init
assert_eq "0" "$_SHELLFRAME_SHELL_FOCUS_IDX" "idx reset to 0"

ptyunit_test_begin "focus_init: preserves focus on prev region by name"
_reset_shell
shellframe_shell_region main 2 1 40 20 focus
shellframe_shell_region sidebar 2 42 38 20 focus
_shellframe_shell_focus_init
# Move focus to sidebar (idx=1)
_shellframe_shell_focus_next
assert_eq "1" "$_SHELLFRAME_SHELL_FOCUS_IDX" "setup: focus on sidebar"
# Re-init (simulates redraw) — should stay on sidebar
shellframe_shell_region main 2 1 40 20 focus
shellframe_shell_region sidebar 2 42 38 20 focus
_shellframe_shell_focus_init
assert_eq "1" "$_SHELLFRAME_SHELL_FOCUS_IDX" "focus preserved on sidebar after re-init"

ptyunit_test_begin "focus_init: applies FOCUS_REQUEST and clears it"
_reset_shell
shellframe_shell_region main 2 1 40 20 focus
shellframe_shell_region modal 1 1 80 24 focus
_SHELLFRAME_SHELL_FOCUS_REQUEST="modal"
_shellframe_shell_focus_init
assert_eq "1" "$_SHELLFRAME_SHELL_FOCUS_IDX" "focus moved to modal"
assert_eq "" "$_SHELLFRAME_SHELL_FOCUS_REQUEST" "request cleared"

# ── _shellframe_shell_focus_next / prev ───────────────────────────────────────

ptyunit_test_begin "focus_next: advances index"
_reset_shell
shellframe_shell_region a 1 1 80 10 focus
shellframe_shell_region b 11 1 80 10 focus
shellframe_shell_region c 21 1 80 3 focus
_shellframe_shell_focus_init
_shellframe_shell_focus_next
assert_eq "1" "$_SHELLFRAME_SHELL_FOCUS_IDX" "idx advanced to 1"

ptyunit_test_begin "focus_next: wraps at end of ring"
_reset_shell
shellframe_shell_region a 1 1 80 10 focus
shellframe_shell_region b 11 1 80 10 focus
_shellframe_shell_focus_init
_SHELLFRAME_SHELL_FOCUS_IDX=1
_shellframe_shell_focus_next
assert_eq "0" "$_SHELLFRAME_SHELL_FOCUS_IDX" "wraps to 0"

ptyunit_test_begin "focus_next: empty ring is a no-op"
_reset_shell
_SHELLFRAME_SHELL_FOCUS_RING=()
_SHELLFRAME_SHELL_FOCUS_IDX=0
_shellframe_shell_focus_next
assert_eq "0" "$_SHELLFRAME_SHELL_FOCUS_IDX" "empty ring: no change"

ptyunit_test_begin "focus_prev: retreats index"
_reset_shell
shellframe_shell_region a 1 1 80 10 focus
shellframe_shell_region b 11 1 80 10 focus
shellframe_shell_region c 21 1 80 3 focus
_shellframe_shell_focus_init
_SHELLFRAME_SHELL_FOCUS_IDX=2
_shellframe_shell_focus_prev
assert_eq "1" "$_SHELLFRAME_SHELL_FOCUS_IDX" "idx retreated to 1"

ptyunit_test_begin "focus_prev: wraps at start of ring"
_reset_shell
shellframe_shell_region a 1 1 80 10 focus
shellframe_shell_region b 11 1 80 10 focus
_shellframe_shell_focus_init
_SHELLFRAME_SHELL_FOCUS_IDX=0
_shellframe_shell_focus_prev
assert_eq "1" "$_SHELLFRAME_SHELL_FOCUS_IDX" "wraps to last (1)"

ptyunit_test_begin "focus_prev: empty ring is a no-op"
_reset_shell
_SHELLFRAME_SHELL_FOCUS_RING=()
_SHELLFRAME_SHELL_FOCUS_IDX=0
_shellframe_shell_focus_prev
assert_eq "0" "$_SHELLFRAME_SHELL_FOCUS_IDX" "empty ring: no change"

# ── _shellframe_shell_focus_owner ─────────────────────────────────────────────

ptyunit_test_begin "focus_owner: returns focused region name to stdout"
_reset_shell
shellframe_shell_region main 2 1 80 20 focus
shellframe_shell_region sidebar 2 60 20 20 focus
_shellframe_shell_focus_init
_SHELLFRAME_SHELL_FOCUS_IDX=1
assert_output "sidebar" _shellframe_shell_focus_owner

ptyunit_test_begin "focus_owner: stores result in out_var"
_reset_shell
shellframe_shell_region main 2 1 80 20 focus
_shellframe_shell_focus_init
_owner=""
_shellframe_shell_focus_owner _owner
assert_eq "main" "$_owner" "out_var set correctly"

ptyunit_test_begin "focus_owner: returns empty string when ring is empty"
_reset_shell
_SHELLFRAME_SHELL_FOCUS_RING=()
assert_output "" _shellframe_shell_focus_owner

# ── _shellframe_shell_region_bounds ───────────────────────────────────────────

ptyunit_test_begin "region_bounds: retrieves correct values by name"
_reset_shell
shellframe_shell_region topbar 1 1 80 1 nofocus
shellframe_shell_region main 3 5 70 18 focus
_rtop="" _rleft="" _rwidth="" _rheight=""
_shellframe_shell_region_bounds main _rtop _rleft _rwidth _rheight
assert_eq "3" "$_rtop" "top=3"
assert_eq "5" "$_rleft" "left=5"
assert_eq "70" "$_rwidth" "width=70"
assert_eq "18" "$_rheight" "height=18"

ptyunit_test_begin "region_bounds: returns 1 for unknown region name"
_reset_shell
shellframe_shell_region main 2 1 80 20 focus
_shellframe_shell_region_bounds nonexistent _t _l _w _h
assert_eq "1" "$?" "returns 1 for unknown"

# ── shellframe_shell_focus_set ────────────────────────────────────────────────

ptyunit_test_begin "shell_focus_set: sets FOCUS_REQUEST"
_reset_shell
shellframe_shell_focus_set "modal"
assert_eq "modal" "$_SHELLFRAME_SHELL_FOCUS_REQUEST" "FOCUS_REQUEST set to modal"

ptyunit_test_begin "shell_focus_set: applied by next focus_init"
_reset_shell
shellframe_shell_region main 2 1 40 20 focus
shellframe_shell_region modal 1 1 80 24 focus
shellframe_shell_focus_set "modal"
_shellframe_shell_focus_init
assert_output "modal" _shellframe_shell_focus_owner

ptyunit_test_summary
