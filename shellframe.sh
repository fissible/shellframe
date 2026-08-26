#!/usr/bin/env bash
# shellframe.sh — Bash TUI library entry point
#
# Source this file to load all shellframe utilities:
#   source /path/to/shellframe/shellframe.sh

SHELLFRAME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Windows-native environments cannot provide the PTY semantics shellframe
# depends on. Detection is exposed as a FUNCTION (the library must have no
# source-time side effects); callers may invoke it after sourcing (#58).
shellframe_platform_check() {
    case "${OSTYPE:-}" in
        msys*|cygwin*)
            printf 'shellframe: %s is a Windows-native environment.\n' "${OSTYPE}" >&2
            printf 'shellframe: a POSIX layer (WSL recommended) is required for correct terminal behavior.\n' >&2
            return 1 ;;
        *) return 0 ;;
    esac
}

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
source "$SHELLFRAME_DIR/src/split.sh"
source "$SHELLFRAME_DIR/src/diff.sh"
source "$SHELLFRAME_DIR/src/sync-scroll.sh"
source "$SHELLFRAME_DIR/src/hitbox.sh"
source "$SHELLFRAME_DIR/src/widgets/action-list.sh"
source "$SHELLFRAME_DIR/src/widgets/confirm.sh"
source "$SHELLFRAME_DIR/src/widgets/alert.sh"
source "$SHELLFRAME_DIR/src/widgets/table.sh"
source "$SHELLFRAME_DIR/src/widgets/tab-bar.sh"
source "$SHELLFRAME_DIR/src/widgets/input-field.sh"
source "$SHELLFRAME_DIR/src/widgets/list.sh"
source "$SHELLFRAME_DIR/src/widgets/modal.sh"
source "$SHELLFRAME_DIR/src/widgets/form.sh"
source "$SHELLFRAME_DIR/src/widgets/tree.sh"
source "$SHELLFRAME_DIR/src/widgets/editor.sh"
source "$SHELLFRAME_DIR/src/widgets/grid.sh"
source "$SHELLFRAME_DIR/src/widgets/diff-view.sh"
source "$SHELLFRAME_DIR/src/widgets/menu-bar.sh"
source "$SHELLFRAME_DIR/src/widgets/context-menu.sh"
source "$SHELLFRAME_DIR/src/widgets/autocomplete.sh"
source "$SHELLFRAME_DIR/src/widgets/scrollbar.sh"
source "$SHELLFRAME_DIR/src/widgets/toast.sh"
source "$SHELLFRAME_DIR/src/widgets/spinner.sh"
source "$SHELLFRAME_DIR/src/pager.sh"
source "$SHELLFRAME_DIR/src/shell.sh"
source "$SHELLFRAME_DIR/src/sheet.sh"
source "$SHELLFRAME_DIR/src/app.sh"
