#!/usr/bin/env bash
# clui/src/input.sh — Keyboard input reading
#
# COMPATIBILITY: bash 3.2+ (macOS default). Note: {varname} fd allocation
# (exec {fd}>&1) requires bash 4.1+; use fixed fd numbers (e.g. fd 3) instead.
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
# GOTCHA 3 — do not match \x03 (Ctrl+C) in the key handler: with stty -icanon
# and isig still enabled (the default), Ctrl+C sends SIGINT to the process
# rather than putting a \x03 byte in the input stream. Matching \x03 will
# instead catch a buffered byte left over from a previous Ctrl+C that
# interrupted a prior command, causing the TUI to immediately "abort" on
# startup. Handle Ctrl+C exclusively via trap.
#
# GOTCHA 4 — case pattern glob: in a bash `case` statement, `[A` is a glob
# bracket expression that matches the single character `A`, not the 2-char
# string `[A`. Store sequences in variables and compare with `[[ == ]]`.
#
# GOTCHA 5 — bash `read` converts \r to \n internally: even with stty -icrnl
# set (so the PTY line discipline does NOT translate CR→LF), bash's own `read`
# builtin converts \r (0x0D) to \n (0x0A) before storing the value. This means
# CLUI_KEY_ENTER must be $'\n', not $'\r'.
#   Additionally, `read -r -n1` (default \n delimiter) returns an empty string
#   when \n is received (because \n is the delimiter and is stripped). To
#   capture \n as a value, use `-d ''` (NUL delimiter) so that \n is treated
#   as a regular character instead of a line terminator.

# Pre-built key sequence constants for use with clui_read_key.
CLUI_KEY_UP=$'\x1b[A'
CLUI_KEY_DOWN=$'\x1b[B'
CLUI_KEY_RIGHT=$'\x1b[C'
CLUI_KEY_LEFT=$'\x1b[D'
CLUI_KEY_ENTER=$'\n'   # bash read converts \r→\n internally; use \n here
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
# Uses `read -d ''` (NUL delimiter) so that \n (produced by bash's internal
# \r→\n conversion when Enter is pressed) is captured as the key value rather
# than silently consumed as the line terminator.
#
# The -t 1 timeout on the follow-on reads handles a standalone ESC press
# gracefully (waits 1 s then returns just $'\x1b'). For arrow keys the
# follow-on bytes are already in the buffer and return immediately.
clui_read_key() {
    local _out_var="${1:-_CLUI_KEY}"
    local _k _c1 _c2
    IFS= read -r -n1 -d '' _k
    if [[ "$_k" == $'\x1b' ]]; then
        IFS= read -r -n1 -d '' -t 1 _c1
        IFS= read -r -n1 -d '' -t 1 _c2
        _k+="${_c1}${_c2}"
    fi
    printf -v "$_out_var" '%s' "$_k"
}
