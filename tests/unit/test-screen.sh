#!/usr/bin/env bash
# tests/unit/test-screen.sh — Unit tests for src/screen.sh
#
# shellframe_screen_enter is NOT tested here: it calls exec 3>/dev/tty which
# requires a real TTY (covered by tests/integration/test-screen.sh instead).
# All other functions write to fd 3 and can be unit-tested by redirecting
# fd 3 to a temp file.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$SHELLFRAME_DIR/shellframe.sh"
source "$PTYUNIT_HOME/assert.sh"

# Helper: call a function with fd 3 pointing at a temp file; return raw bytes.
_fd3_capture() {
    local _fn="$1"; shift
    local _out
    _out=$(mktemp "${TMPDIR:-/tmp}/sf-test-screen.XXXXXX")
    trap '{ exec 3>&- 2>/dev/null || true; rm -f "$_out"; }' RETURN
    exec 3>"$_out"
    "$_fn" "$@"
    exec 3>&- 2>/dev/null || true
    printf '%s' "$(cat "$_out")"
}

# ── shellframe_screen_clear ────────────────────────────────────────────────────

ptyunit_test_begin "screen_clear: writes cursor-home sequence to fd 3"
_out=$(_fd3_capture shellframe_screen_clear)
assert_contains "$_out" $'\033[H'

ptyunit_test_begin "screen_clear: writes erase-screen sequence to fd 3"
_out=$(_fd3_capture shellframe_screen_clear)
assert_contains "$_out" $'\033[2J'

ptyunit_test_begin "screen_clear: writes erase-scrollback sequence to fd 3"
_out=$(_fd3_capture shellframe_screen_clear)
assert_contains "$_out" $'\033[3J'

# ── shellframe_cursor_hide / show ─────────────────────────────────────────────

ptyunit_test_begin "cursor_hide: writes hide-cursor sequence to fd 3"
_out=$(_fd3_capture shellframe_cursor_hide)
assert_eq $'\033[?25l' "$_out"

ptyunit_test_begin "cursor_show: writes show-cursor sequence to fd 3"
_out=$(_fd3_capture shellframe_cursor_show)
assert_eq $'\033[?25h' "$_out"

# ── shellframe_screen_exit ────────────────────────────────────────────────────

ptyunit_test_begin "screen_exit: writes disable-alternate-screen sequence to fd 3"
_out=$(_fd3_capture shellframe_screen_exit)
assert_contains "$_out" $'\033[?1049l'

# ── shellframe_raw_enter ──────────────────────────────────────────────────────

ptyunit_test_begin "raw_enter: writes bracketed-paste-enable sequence to fd 3"
_out=$(_fd3_capture shellframe_raw_enter)
assert_contains "$_out" $'\033[?2004h'

# ── shellframe_raw_exit ───────────────────────────────────────────────────────

ptyunit_test_begin "raw_exit: writes bracketed-paste-disable sequence to fd 3"
_out=$(_fd3_capture shellframe_raw_exit "")
assert_contains "$_out" $'\033[?2004l'

# ── shellframe_raw_save ───────────────────────────────────────────────────────

ptyunit_test_begin "raw_save: suppresses stderr when no TTY is available"
_err=$({ shellframe_raw_save >/dev/null; } 2>&1)
assert_eq "" "$_err"

ptyunit_test_summary
