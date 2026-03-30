#!/usr/bin/env bash
_SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$_SHELLFRAME_DIR/src/clip.sh"
source "$_SHELLFRAME_DIR/src/draw.sh"
source "$_SHELLFRAME_DIR/src/screen.sh"
source "$_SHELLFRAME_DIR/src/widgets/toast.sh"
source "$PTYUNIT_HOME/assert.sh"

ptyunit_test_begin "toast_show: queues a toast"
shellframe_toast_clear
shellframe_toast_show "Hello"
assert_eq "1" "${#_SHELLFRAME_TOAST_QUEUE[@]}" "show: queue has 1 entry"
assert_contains "${_SHELLFRAME_TOAST_QUEUE[0]}" "Hello" "show: entry contains message"

ptyunit_test_begin "toast_show: default style is info"
shellframe_toast_clear
shellframe_toast_show "Msg"
assert_contains "${_SHELLFRAME_TOAST_QUEUE[0]}" "info" "show: default style is info"

ptyunit_test_begin "toast_show: queues with explicit style"
shellframe_toast_clear
shellframe_toast_show "OK" success
assert_contains "${_SHELLFRAME_TOAST_QUEUE[0]}" "success" "show: explicit style stored"

ptyunit_test_begin "toast_tick: decrements TTL"
shellframe_toast_clear
shellframe_toast_show "X" info 5
shellframe_toast_tick
_ttl="${_SHELLFRAME_TOAST_QUEUE[0]##*$'\t'}"
assert_eq "4" "$_ttl" "tick: TTL decremented to 4"

ptyunit_test_begin "toast_tick: removes expired entries"
shellframe_toast_clear
shellframe_toast_show "X" info 1
shellframe_toast_tick
assert_eq "0" "${#_SHELLFRAME_TOAST_QUEUE[@]}" "tick: expired entry removed"

ptyunit_test_begin "toast_tick: keeps non-expired entries"
shellframe_toast_clear
shellframe_toast_show "A" info 2
shellframe_toast_show "B" info 1
shellframe_toast_tick
assert_eq "1" "${#_SHELLFRAME_TOAST_QUEUE[@]}" "tick: 1 entry remains"
assert_contains "${_SHELLFRAME_TOAST_QUEUE[0]}" "A" "tick: correct entry remains"

ptyunit_test_begin "toast_show: max 3 entries (oldest dropped)"
shellframe_toast_clear
shellframe_toast_show "A" info 30
shellframe_toast_show "B" info 30
shellframe_toast_show "C" info 30
shellframe_toast_show "D" info 30
assert_eq "3" "${#_SHELLFRAME_TOAST_QUEUE[@]}" "show: capped at 3"
assert_contains "${_SHELLFRAME_TOAST_QUEUE[0]}" "D" "show: newest (D) is at index 0"
assert_contains "${_SHELLFRAME_TOAST_QUEUE[2]}" "B" "show: oldest kept (B) is at index 2"

ptyunit_test_summary
