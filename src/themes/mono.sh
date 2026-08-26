#!/usr/bin/env bash
# src/themes/mono.sh — attributes only, zero color (#53)
#
# For NO_COLOR-style deployments, monochrome terminals, and screenshot
# tests: bold/reverse keep their effect, every color renders empty.
SHELLFRAME_BOLD=$(tput bold  2>/dev/null || printf '\033[1m')
SHELLFRAME_DIM=$(tput dim    2>/dev/null || printf '\033[2m')
SHELLFRAME_RESET=$(tput sgr0 2>/dev/null || printf '\033[0m')
SHELLFRAME_REVERSE=$(tput rev 2>/dev/null || printf '\033[7m')
SHELLFRAME_GREEN=""
SHELLFRAME_RED=""
SHELLFRAME_YELLOW=""
SHELLFRAME_PURPLE=""
SHELLFRAME_GRAY=""
SHELLFRAME_WHITE=""
