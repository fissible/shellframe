#!/usr/bin/env bash
# examples/modal.sh — Demo for shellframe_modal prompt widget
#
# Shows a rename dialog with an input field and OK / Cancel buttons.
# On OK:     prints the entered name to stdout.
# On Cancel: prints "Cancelled." and exits 1.

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

SHELLFRAME_MODAL_TITLE="Rename"
SHELLFRAME_MODAL_MESSAGE='New name for "report.csv":'
SHELLFRAME_MODAL_BUTTONS=("OK" "Cancel")
SHELLFRAME_MODAL_INPUT=1
SHELLFRAME_MODAL_FOCUSED=1
shellframe_modal_init

saved_stty=$(shellframe_raw_save)

_cleanup() {
    shellframe_raw_exit "$saved_stty"
    shellframe_cursor_show
    shellframe_screen_exit
}
trap '_cleanup' EXIT
trap 'exit 1' INT TERM

shellframe_screen_enter
shellframe_raw_enter
shellframe_cursor_show

cols=$(tput cols)
rows=$(tput lines)

while true; do
    shellframe_fb_frame_start "$rows" "$cols"
    shellframe_modal_render 1 1 "$cols" "$rows"
    shellframe_screen_flush
    shellframe_read_key key
    shellframe_modal_on_key "$key"
    (( $? == 2 )) && break
done

trap - EXIT INT TERM
_cleanup

if (( SHELLFRAME_MODAL_RESULT == 0 )); then
    name=$(shellframe_cur_text "${SHELLFRAME_MODAL_INPUT_CTX}")
    printf 'Renamed to: %s\n' "$name"
else
    printf 'Cancelled.\n'
    exit 1
fi
