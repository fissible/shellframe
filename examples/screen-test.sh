#!/usr/bin/env bash
# examples/screen-test.sh — Screen enter/exit/raw roundtrip fixture
#
# Exercises shellframe_screen_enter, shellframe_cursor_hide, shellframe_raw_enter,
# shellframe_raw_save, shellframe_raw_exit, shellframe_cursor_show, and
# shellframe_screen_exit in sequence. Prints "screen-test-done" to stdout on
# clean exit.
#
# Used by tests/integration/test-screen.sh.

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

# shellframe_screen_enter opens fd 3 to /dev/tty internally; do not open it here.
shellframe_screen_enter

saved=""   # initialised before trap so it is always bound under set -u
_cleanup() {
    shellframe_raw_exit "$saved"
    shellframe_cursor_show
    shellframe_screen_exit
}
trap '_cleanup' EXIT
trap 'exit 1' INT TERM

shellframe_cursor_hide
shellframe_raw_enter
printf '\033[1;1HScreen entered\n' >&3
saved=$(shellframe_raw_save)
shellframe_raw_exit "$saved"
shellframe_cursor_show

trap - EXIT INT TERM
_cleanup
printf 'screen-test-done\n'
