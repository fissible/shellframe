#!/usr/bin/env bash
# examples/table.sh — Table widget demo (used by integration tests)
#
# Renders a navigable table of fruits. ENTER confirms selection; q quits.
# Prints "Selected: <label>" or "Aborted." to stdout on exit.

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

SHELLFRAME_TBL_LABELS=("apple" "banana" "cherry" "date" "elderberry")
SHELLFRAME_TBL_ACTIONS=("nothing" "nothing" "nothing" "nothing" "nothing")
SHELLFRAME_TBL_IDX=(0 0 0 0 0)
SHELLFRAME_TBL_META=("" "" "" "" "")
SHELLFRAME_TBL_SCROLL=0
SHELLFRAME_TBL_SELECTED=0

shellframe_table "" "" "↑/↓ move  Enter confirm  q quit"
_result=$?

if (( _result == 0 )); then
    printf 'Selected: %s\n' "${SHELLFRAME_TBL_LABELS[$SHELLFRAME_TBL_SELECTED]}"
else
    printf 'Aborted.\n'
fi
