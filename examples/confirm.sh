#!/usr/bin/env bash
# examples/confirm.sh — Demo for clui_confirm modal widget

set -u
CLUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CLUI_DIR/clui.sh"

clui_confirm "Delete 3 files permanently?" \
    "  config.json        delete" \
    "  cache/data.db      delete" \
    "  tmp/session.lock   delete"

if (( $? == 0 )); then
    printf "Confirmed: deleting files.\n"
else
    printf "Cancelled.\n"
fi
