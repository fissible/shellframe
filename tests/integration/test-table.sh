#!/usr/bin/env bash
# tests/integration/test-table.sh — PTY tests for examples/table.sh (legacy table widget)

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/table.sh"

source "$PTYUNIT_HOME/assert.sh"

_pty() { python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null; }

ptyunit_test_begin "table: renders without crash — confirm on Enter"
out=$(_pty ENTER)
assert_contains "$out" "Selected: "

ptyunit_test_begin "table: q quits"
out=$(_pty q)
assert_contains "$out" "Aborted."

ptyunit_test_summary

# ── #56: pager escape hatch ───────────────────────────────────────────────────

ptyunit_test_begin "table #56: 'v' with PAGER=cat shows plain rows, table redraws intact"
out=$( PAGER=cat python3 "$PTY_RUN" "$SCRIPT" v q 2>/dev/null )
assert_contains "$out" "apple"                          # rows in pager dump
assert_contains "$out" "↑/↓ move"                   # table chrome redrawn after pager

ptyunit_test_begin "table #56: PAGER with arguments runs (less -R style)"
out=$( ( export PAGER="cat -n"; python3 "$PTY_RUN" "$SCRIPT" v q 2>/dev/null ) )
assert_contains "$out" "apple"

ptyunit_test_begin "table #56: missing pager binary warns and falls back to cat"
out=$( ( export PAGER="/nonexistent-pager-xyz"; python3 "$PTY_RUN" "$SCRIPT" v q 2>&1 ) || true )
assert_contains "$out" "falling back to cat"
assert_contains "$out" "apple"

ptyunit_test_begin "table #56: SHELLFRAME_DUMP=1 prints plain text to stdout, no TUI"
dump=$( SHELLFRAME_DUMP=1 python3 "$PTY_RUN" "$SCRIPT" 2>/dev/null )
assert_contains "$dump" "apple"
if [[ "$dump" == *"Ctrl-D"* || "$dump" == *$'\033[?1049h'* ]]; then
    ptyunit_fail "TUI chrome present in dump mode"
else
    ptyunit_pass
fi

ptyunit_test_summary
