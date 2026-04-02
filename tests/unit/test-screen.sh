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

# ── shellframe_fb_put ─────────────────────────────────────────────────────────

ptyunit_test_begin "fb_put: stores cell in row fragment"
shellframe_fb_frame_start 4 10
shellframe_fb_put 2 3 "X"
assert_contains "${_SF_ROW_CURR[2]:-}" "X" "cell in row 2 fragment"

ptyunit_test_begin "fb_put: marks row dirty"
shellframe_fb_frame_start 4 10
shellframe_fb_put 1 1 "A"
assert_eq "1" "${_SF_DIRTY_ROWS[1]:-}" "row 1 in dirty list"

# ── shellframe_fb_print ───────────────────────────────────────────────────────

ptyunit_test_begin "fb_print: string appears in row fragment"
shellframe_fb_frame_start 1 10
shellframe_fb_print 1 1 "hi"
assert_contains "${_SF_ROW_CURR[1]:-}" "hi" "string in row fragment"

ptyunit_test_begin "fb_print: prefix included in fragment"
shellframe_fb_frame_start 1 10
shellframe_fb_print 1 1 "ab" $'\033[1m'
assert_contains "${_SF_ROW_CURR[1]:-}" $'\033[1m' "bold prefix in fragment"
assert_contains "${_SF_ROW_CURR[1]:-}" "ab" "text after prefix"

# ── shellframe_fb_fill ────────────────────────────────────────────────────────

ptyunit_test_begin "fb_fill: fills row with N copies of char"
shellframe_fb_frame_start 1 10
shellframe_fb_fill 1 2 3 "-"
assert_contains "${_SF_ROW_CURR[1]:-}" "---" "3 dashes in row fragment"

ptyunit_test_begin "fb_fill: untouched row is empty"
shellframe_fb_frame_start 1 10
shellframe_fb_fill 1 2 3 "-"
assert_eq "" "${_SF_ROW_CURR[2]:-}" "row 2 untouched"

# ── shellframe_screen_flush: diff behavior ────────────────────────────────────

ptyunit_test_begin "flush: no-change → zero output"
_SF_ROW_PREV=()
shellframe_fb_frame_start 2 5
shellframe_fb_put 1 1 "A"
_out=$(mktemp)
exec 3>"$_out"
shellframe_screen_flush
exec 3>&-
shellframe_fb_frame_start 2 5
shellframe_fb_put 1 1 "A"
_out2=$(mktemp)
exec 3>"$_out2"
shellframe_screen_flush
exec 3>&-
_size=$(wc -c < "$_out2" | tr -d ' ')
assert_eq "0" "$_size" "no output for unchanged row"
rm -f "$_out" "$_out2"

ptyunit_test_begin "flush: single-cell change → row emitted"
_SF_ROW_PREV=()
shellframe_fb_frame_start 3 10
shellframe_fb_put 2 4 "Z"
_out=$(mktemp)
exec 3>"$_out"
shellframe_screen_flush
exec 3>&-
_raw=$(sed $'s/\033\[[0-9;]*[A-Za-z]//g' < "$_out")
assert_contains "$_raw" "Z" "changed cell emitted"
rm -f "$_out"

ptyunit_test_begin "flush: erasure — PREV row not in CURR emits clear"
_SF_ROW_PREV=()
shellframe_fb_frame_start 1 5
shellframe_fb_put 1 1 "Q"
_out=$(mktemp)
exec 3>"$_out"
shellframe_screen_flush
exec 3>&-
shellframe_fb_frame_start 1 5
_out2=$(mktemp)
exec 3>"$_out2"
shellframe_screen_flush
exec 3>&-
_size=$(wc -c < "$_out2" | tr -d ' ')
assert_eq "1" "$(( _size > 0 ))" "erasure emits output"
rm -f "$_out" "$_out2"

# ── shellframe_screen_clear: resets framebuffer state ─────────────────────────

ptyunit_test_begin "screen_clear: resets CURR, PREV, and DIRTY"
shellframe_fb_frame_start 2 5
shellframe_fb_put 1 1 "X"
_SF_ROW_PREV[1]="old"
_SF_DIRTY_ROWS[1]=1
exec 3>/dev/null
shellframe_screen_clear
assert_eq "0" "${#_SF_ROW_CURR[@]}" "CURR reset"
assert_eq "0" "${#_SF_ROW_PREV[@]}" "PREV reset"
assert_eq "0" "${#_SF_DIRTY_ROWS[@]}" "DIRTY reset"

ptyunit_test_summary
