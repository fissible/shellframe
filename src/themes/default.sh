#!/usr/bin/env bash
# src/themes/default.sh — the shellframe default theme (#53)
#
# A theme file assigns the SHELLFRAME_* presentation globals. Colors come
# from terminus capabilities where available and degrade to empty strings,
# which renders plain but never breaks layout.
SHELLFRAME_BOLD=$(tput bold     2>/dev/null || true)
SHELLFRAME_DIM=$(tput dim       2>/dev/null || true)
SHELLFRAME_RESET=$(tput sgr0    2>/dev/null || printf '\033[0m')
SHELLFRAME_REVERSE=$(tput rev   2>/dev/null || printf '\033[7m')
SHELLFRAME_GREEN=$(tput setaf 2 2>/dev/null || printf '\033[32m')
SHELLFRAME_RED=$(tput setaf 1   2>/dev/null || printf '\033[31m')
SHELLFRAME_YELLOW=$(tput setaf 3 2>/dev/null || printf '\033[33m')
SHELLFRAME_PURPLE=$(tput setaf 5 2>/dev/null || printf '\033[35m')
SHELLFRAME_GRAY=$(tput setaf 8 2>/dev/null || tput setaf 7 2>/dev/null || printf '\033[90m')
SHELLFRAME_WHITE=$(tput setaf 7 2>/dev/null || printf '\033[37m')
