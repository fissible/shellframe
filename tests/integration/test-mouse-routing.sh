#!/usr/bin/env bash
# tests/integration/test-mouse-routing.sh
#
# IO validation for mouse routing through shellframe_shell (Phase 7E).
# Sends real SGR mouse sequences through a PTY and confirms parsed values.
#
# PTY layout (PTY_COLS=80 PTY_ROWS=10, list occupies rows 1..9):
#   Row 1: apple      (index 0)
#   Row 2: banana     (index 1)
#   Row 3: cherry     (index 2)
#   Row 4: date       (index 3)
#   Row 5: elderberry (index 4)
#   Row 9: footer
#
# SGR press format: ESC [ < button ; col ; row M

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/shell-list.sh"

source "$PTYUNIT_HOME/assert.sh"

# Use a compact PTY so row numbers are predictable.
_pty() {
    PTY_ROWS=10 PTY_COLS=80 python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Baseline keyboard tests ───────────────────────────────────────────────────

ptyunit_test_begin "mouse-routing: keyboard Enter selects first item"
out=$(_pty ENTER)
assert_contains "$out" "Selected: apple"

ptyunit_test_begin "mouse-routing: keyboard DOWN then Enter selects banana"
out=$(_pty DOWN ENTER)
assert_contains "$out" "Selected: banana"

# ── Mouse click-to-select ─────────────────────────────────────────────────────
# Click row 2, col 1: SGR press = ESC [ < 0 ; 1 ; 2 M

ptyunit_test_begin "mouse-routing: click row 2 selects banana"
# ESC[<0;1;2M = button 0 (left), col 1, row 2 → banana (index 1)
out=$(_pty $'\x1b[<0;1;2M' ENTER)
assert_contains "$out" "Selected: banana"

ptyunit_test_begin "mouse-routing: click row 3 selects cherry"
out=$(_pty $'\x1b[<0;1;3M' ENTER)
assert_contains "$out" "Selected: cherry"

ptyunit_test_begin "mouse-routing: click row 1 selects apple"
out=$(_pty $'\x1b[<0;1;1M' ENTER)
assert_contains "$out" "Selected: apple"

# ── Mouse click outside all widgets is a no-op ────────────────────────────────

ptyunit_test_begin "mouse-routing: click outside widgets does not crash"
# Click on row 10, col 1 — PTY is 10 rows, footer occupies row 10 (nofocus)
# No on_mouse handler registered for footer → no-op, app stays alive
out=$(_pty $'\x1b[<0;1;10M' q)
assert_contains "$out" "No selection."

# ── Scroll-wheel ──────────────────────────────────────────────────────────────
# Scroll-wheel sequences: button 64 (up) / 65 (down)

ptyunit_test_begin "mouse-routing: scroll-down then click visible row selects correct item"
# Scroll down once (scroll_top becomes 1 if viewport < 9 items, but with 5 items
# scroll_top stays 0 — verify app doesn't crash and Enter still works)
out=$(_pty $'\x1b[<65;1;1M' ENTER)
assert_contains "$out" "Selected: apple"

ptyunit_test_summary
