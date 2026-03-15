#!/usr/bin/env bash
# shellframe.sh — Bash TUI library entry point
#
# Source this file to load all shellframe utilities:
#   source /path/to/shellframe/shellframe.sh

SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SHELLFRAME_DIR/src/screen.sh"
source "$SHELLFRAME_DIR/src/input.sh"
source "$SHELLFRAME_DIR/src/draw.sh"
source "$SHELLFRAME_DIR/src/widgets/action-list.sh"
source "$SHELLFRAME_DIR/src/widgets/confirm.sh"
source "$SHELLFRAME_DIR/src/widgets/alert.sh"
source "$SHELLFRAME_DIR/src/widgets/table.sh"
source "$SHELLFRAME_DIR/src/app.sh"
