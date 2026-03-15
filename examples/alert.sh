#!/usr/bin/env bash
# examples/alert.sh — Demo for clui_alert informational modal widget

set -u
CLUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
source "$CLUI_DIR/clui.sh"

clui_alert "Deploy complete" \
    "web-server    restarted" \
    "cache         flushed" \
    "config.json   reloaded"

printf "Alert dismissed.\n"
