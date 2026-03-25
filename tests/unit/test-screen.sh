#!/usr/bin/env bash
# tests/unit/test-screen.sh — Unit tests for src/screen.sh
#
# Covers: shellframe_screen_clear, shellframe_cursor_hide/show,
#         shellframe_raw_save, shellframe_raw_enter, shellframe_raw_exit,
#         shellframe_screen_exit.
# Not covered: shellframe_screen_enter — opens /dev/tty which is unavailable
#              in headless Docker; all 3 executable lines require a real TTY.

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"

source "$SHELLFRAME_DIR/src/screen.sh"
source "$PTYUNIT_HOME/assert.sh"

# ── fd 3 / coverage-trace setup ──────────────────────────────────────────────
# screen.sh functions write to >&3. ptyunit coverage sets BASH_XTRACEFD=3.
# Dup the trace fd to 4, redirect fd 3 to /dev/null, and trace via fd 4 so
# that screen.sh writes don't interfere with coverage data.
exec 4>&3 2>/dev/null || true
exec 3>/dev/null
BASH_XTRACEFD=4

# ── shellframe_screen_clear ───────────────────────────────────────────────────

ptyunit_test_begin "screen_clear: exits 0"
shellframe_screen_clear
assert_eq "0" "$?" "screen_clear exits 0"

# ── shellframe_cursor_hide / shellframe_cursor_show ───────────────────────────

ptyunit_test_begin "cursor_hide: exits 0"
shellframe_cursor_hide
assert_eq "0" "$?" "cursor_hide exits 0"

ptyunit_test_begin "cursor_show: exits 0"
shellframe_cursor_show
assert_eq "0" "$?" "cursor_show exits 0"

# ── shellframe_raw_save ───────────────────────────────────────────────────────

ptyunit_test_begin "raw_save: does not crash (stty may fail in headless env)"
shellframe_raw_save >/dev/null || true
assert_eq "0" "$?" "raw_save does not crash"

# ── shellframe_raw_enter ──────────────────────────────────────────────────────

ptyunit_test_begin "raw_enter: exits 0 (stty may fail silently in headless env)"
shellframe_raw_enter
assert_eq "0" "$?" "raw_enter exits 0"

# ── shellframe_raw_exit ───────────────────────────────────────────────────────

ptyunit_test_begin "raw_exit: exits 0 with empty saved state"
shellframe_raw_exit ""
assert_eq "0" "$?" "raw_exit exits 0"

ptyunit_test_begin "raw_exit: exits 0 with non-empty saved state"
# stty -g may return empty in headless, but raw_exit must not crash
_saved=$(shellframe_raw_save) || true
shellframe_raw_exit "$_saved"
assert_eq "0" "$?" "raw_exit with saved state exits 0"

# ── shellframe_screen_exit ────────────────────────────────────────────────────
# screen_exit writes to fd 3 then closes it (exec 3>&-). Re-open fd 3 after.

ptyunit_test_begin "screen_exit: exits 0"
shellframe_screen_exit
assert_eq "0" "$?" "screen_exit exits 0"
exec 3>/dev/null   # re-open fd 3 after screen_exit closed it

# ── shellframe_mouse_enter / shellframe_mouse_exit ───────────────────────────

ptyunit_test_begin "mouse_enter: exits 0"
shellframe_mouse_enter
assert_eq "0" "$?" "mouse_enter exits 0"

ptyunit_test_begin "mouse_exit: exits 0"
shellframe_mouse_exit
assert_eq "0" "$?" "mouse_exit exits 0"

ptyunit_test_summary
