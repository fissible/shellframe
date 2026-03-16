#!/usr/bin/env bash
# shellframe.sh — Bash TUI library entry point
#
# Source this file to load all shellframe utilities:
#   source /path/to/shellframe/shellframe.sh

SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/clip.sh"
source "$SHELLFRAME_DIR/src/selection.sh"
source "$SHELLFRAME_DIR/src/keymap.sh"
source "$SHELLFRAME_DIR/src/cursor.sh"
source "$SHELLFRAME_DIR/src/text.sh"
source "$SHELLFRAME_DIR/src/scroll.sh"
source "$SHELLFRAME_DIR/src/panel.sh"
source "$SHELLFRAME_DIR/src/widgets/action-list.sh"
source "$SHELLFRAME_DIR/src/widgets/confirm.sh"
source "$SHELLFRAME_DIR/src/widgets/alert.sh"
source "$SHELLFRAME_DIR/src/widgets/table.sh"
source "$SHELLFRAME_DIR/src/widgets/tab-bar.sh"
source "$SHELLFRAME_DIR/src/widgets/input-field.sh"
source "$SHELLFRAME_DIR/src/widgets/list.sh"
source "$SHELLFRAME_DIR/src/widgets/modal.sh"
source "$SHELLFRAME_DIR/src/shell.sh"
source "$SHELLFRAME_DIR/src/app.sh"
