#!/usr/bin/env bash
# clui/src/input.sh — Keyboard input reading
#
# COMPATIBILITY: bash 3.2+ (macOS default).
#
# GOTCHA 1 — decimal timeouts: bash 3.2 does not accept fractional values for
# `read -t`. Use integers only. `-t 0.1` produces "invalid timeout
# specification" and silently fails, leaving the ESC byte as the entire key
# value while `[B` etc. remain in the buffer and echo on the next read.
#
# GOTCHA 2 — read -n2 with stty min 1: with `stty min 1 time 0` set, the OS
# satisfies a read() syscall as soon as ONE byte is available. bash's
# `read -nN` reads AT MOST N chars, so `read -n2` may return with just 1 char
# (the `[`), leaving `A`/`B`/`C`/`D` in the buffer unread. Read escape
# sequences one byte at a time instead.
#
# GOTCHA 3 — case pattern glob: in a bash `case` statement, `[A` is a glob
# bracket expression that matches the single character `A`, not the 2-char
# string `[A`. Store sequences in variables and compare with `[[ == ]]`.

# Pre-built key sequence constants for use with clui_read_key.
CLUI_KEY_UP=$'\x1b[A'
CLUI_KEY_DOWN=$'\x1b[B'
CLUI_KEY_RIGHT=$'\x1b[C'
CLUI_KEY_LEFT=$'\x1b[D'
CLUI_KEY_ENTER=$'\r'
CLUI_KEY_SPACE=' '
CLUI_KEY_ESC=$'\x1b'

# Read one keypress (including full escape sequences) into a variable.
#
# Usage:
#   local key
#   clui_read_key key
#   if   [[ "$key" == "$CLUI_KEY_UP"    ]]; then ...
#   elif [[ "$key" == "$CLUI_KEY_DOWN"  ]]; then ...
#   elif [[ "$key" == "$CLUI_KEY_ENTER" ]]; then ...
#
# Prerequisites: call inside a clui_raw_enter session so the terminal is in
# raw mode. Without raw mode, escape sequence bytes may echo between reads.
#
# The -t 1 timeout on the follow-on reads handles a standalone ESC press
# gracefully (waits 1 s then returns just $'\x1b'). For arrow keys the
# follow-on bytes are already in the buffer and return immediately.
clui_read_key() {
    local _out_var="${1:-_CLUI_KEY}"
    local _k _c1 _c2
    IFS= read -r -n1 _k
    if [[ "$_k" == $'\x1b' ]]; then
        IFS= read -r -n1 -t 1 _c1
        IFS= read -r -n1 -t 1 _c2
        _k+="${_c1}${_c2}"
    fi
    printf -v "$_out_var" '%s' "$_k"
}
