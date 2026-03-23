#!/usr/bin/env bash
# tests/unit/test-alert.sh — Unit tests for _shellframe_alert_render

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$TESTS_DIR/ptyunit/assert.sh"

# Render alert to a temp file, strip ANSI, return plain text
_render_alert() {
    local _title="$1" _n_details="$2"
    shift 2
    local _out
    _out=$(mktemp "${TMPDIR:-/tmp}/sf-test-alert.XXXXXX")
    exec 3>"$_out"
    _shellframe_alert_render "$_title" "$_n_details" "$@"
    exec 3>&-
    # Strip ANSI escape sequences
    sed 's/\033\[[0-9;]*m//g; s/\033\[[0-9;]*[A-Za-z]//g' "$_out"
    rm -f "$_out"
}

# ── Title rendering ──────────────────────────────────────────────────────────

ptyunit_test_begin "alert_render: title appears in output"
out=$(_render_alert "File saved" 0)
assert_contains "$out" "File saved"

ptyunit_test_begin "alert_render: footer hint appears"
out=$(_render_alert "Done" 0)
assert_contains "$out" "Any key to continue"

ptyunit_test_begin "alert_render: border chars present"
out=$(_render_alert "Done" 0)
assert_contains "$out" "+"
assert_contains "$out" "|"

# ── Detail lines ─────────────────────────────────────────────────────────────

ptyunit_test_begin "alert_render: single detail line appears"
out=$(_render_alert "Done" 1 "Changes applied successfully")
assert_contains "$out" "Changes applied successfully"

ptyunit_test_begin "alert_render: multiple detail lines appear"
out=$(_render_alert "Error" 2 "Connection failed" "Retry in 5 seconds")
assert_contains "$out" "Connection failed"
assert_contains "$out" "Retry in 5 seconds"

ptyunit_test_begin "alert_render: title still present with details"
out=$(_render_alert "Error" 1 "Something went wrong")
assert_contains "$out" "Error"

ptyunit_test_summary
