#!/usr/bin/env bash
# examples/diff-view.sh — Minimal diff-view fixture for integration tests

set -u
SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHELLFRAME_DIR/shellframe.sh"

# Build a minimal diff
shellframe_diff_parse_string \
    "--- a/foo.sh
+++ b/foo.sh
@@ -1,3 +1,3 @@
 context line
-old line
+new line
 another context"

shellframe_diff_view_init

SHELLFRAME_DIFF_VIEW_LEFT_FOOTER="a/foo.sh"
SHELLFRAME_DIFF_VIEW_RIGHT_FOOTER="b/foo.sh"

saved_stty=$(shellframe_raw_save)

_cleanup() {
    shellframe_raw_exit "$saved_stty"
    shellframe_cursor_show
    shellframe_screen_exit
}
trap '_cleanup' EXIT
trap 'exit 1' INT TERM

shellframe_screen_enter
shellframe_screen_clear
shellframe_raw_enter

cols=$(tput cols 2>/dev/null); cols=${cols:-80}
lines=$(tput lines 2>/dev/null); lines=${lines:-24}

shellframe_fb_frame_start "$lines" "$cols"
shellframe_diff_view_render 1 1 "$cols" "$(( lines - 1 ))"
shellframe_screen_flush

key=""
shellframe_read_key key

trap - EXIT INT TERM
_cleanup

printf 'diff-view rendered\n'
