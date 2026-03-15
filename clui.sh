#!/usr/bin/env bash
# clui.sh — Bash TUI library entry point
#
# Source this file to load all clui utilities:
#   source /path/to/clui/clui.sh

CLUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$CLUI_DIR/src/screen.sh"
source "$CLUI_DIR/src/input.sh"
source "$CLUI_DIR/src/draw.sh"
source "$CLUI_DIR/src/widgets/action-list.sh"
