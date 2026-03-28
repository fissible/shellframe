#!/usr/bin/env bash
# shellframe/src/input.sh — Keyboard input reading
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
# SHELLFRAME_KEY_ENTER must be $'\n', not $'\r'.
#   Additionally, `read -r -n1` (default \n delimiter) returns an empty string
#   when \n is received (because \n is the delimiter and is stripped). To
#   capture \n as a value, use `-d ''` (NUL delimiter) so that \n is treated
#   as a regular character instead of a line terminator.

# Pre-built key sequence constants for use with shellframe_read_key.
# Arrow keys (3-byte CSI sequences)
SHELLFRAME_KEY_UP=$'\x1b[A'
SHELLFRAME_KEY_DOWN=$'\x1b[B'
SHELLFRAME_KEY_RIGHT=$'\x1b[C'
SHELLFRAME_KEY_LEFT=$'\x1b[D'
# Common single-byte keys
SHELLFRAME_KEY_ENTER=$'\n'    # bash read converts \r→\n internally; use \n here
SHELLFRAME_KEY_SPACE=' '
SHELLFRAME_KEY_ESC=$'\x1b'
SHELLFRAME_KEY_TAB=$'\t'
SHELLFRAME_KEY_BACKSPACE=$'\x7f'
# Ctrl key combos (single-byte)
SHELLFRAME_KEY_CTRL_A=$'\x01'
SHELLFRAME_KEY_CTRL_E=$'\x05'
SHELLFRAME_KEY_CTRL_K=$'\x0b'
SHELLFRAME_KEY_CTRL_U=$'\x15'
SHELLFRAME_KEY_CTRL_W=$'\x17'
# 3-byte CSI sequences
SHELLFRAME_KEY_SHIFT_TAB=$'\x1b[Z'
SHELLFRAME_KEY_HOME=$'\x1b[H'
SHELLFRAME_KEY_END=$'\x1b[F'
# 4-byte CSI sequences: ESC [ <digit> ~
SHELLFRAME_KEY_DELETE=$'\x1b[3~'
SHELLFRAME_KEY_PAGE_UP=$'\x1b[5~'
SHELLFRAME_KEY_PAGE_DOWN=$'\x1b[6~'
# Bracketed paste mode sequences (6-byte): enabled by shellframe_raw_enter
SHELLFRAME_KEY_PASTE_START=$'\x1b[200~'
SHELLFRAME_KEY_PASTE_END=$'\x1b[201~'
# Function keys F1–F4: SS3 sequences (ESC O P–S)
SHELLFRAME_KEY_F1=$'\x1bOP'
SHELLFRAME_KEY_F2=$'\x1bOQ'
SHELLFRAME_KEY_F3=$'\x1bOR'
SHELLFRAME_KEY_F4=$'\x1bOS'
# Function keys F5–F12: CSI sequences (ESC [ <num> ~)
# Note: F6=17, F7=18, F8=19, F9=20, F10=21 (F11 skips to 23, F12=24)
SHELLFRAME_KEY_F5=$'\x1b[15~'
SHELLFRAME_KEY_F6=$'\x1b[17~'
SHELLFRAME_KEY_F7=$'\x1b[18~'
SHELLFRAME_KEY_F8=$'\x1b[19~'
SHELLFRAME_KEY_F9=$'\x1b[20~'
SHELLFRAME_KEY_F10=$'\x1b[21~'
SHELLFRAME_KEY_F11=$'\x1b[23~'
SHELLFRAME_KEY_F12=$'\x1b[24~'
# Modifier+arrow sequences: ESC [ 1 ; <mod> <dir>
# Modifier codes: 2=Shift, 3=Alt, 5=Ctrl
SHELLFRAME_KEY_SHIFT_UP=$'\x1b[1;2A'
# Mouse sentinel — set by shellframe_read_key when an SGR mouse event is parsed.
# Callers branch on [[ "$key" == "$SHELLFRAME_KEY_MOUSE" ]] and read the vars below.
SHELLFRAME_KEY_MOUSE='MOUSE'
SHELLFRAME_KEY_SHIFT_DOWN=$'\x1b[1;2B'
SHELLFRAME_KEY_SHIFT_RIGHT=$'\x1b[1;2C'
SHELLFRAME_KEY_SHIFT_LEFT=$'\x1b[1;2D'
SHELLFRAME_KEY_ALT_UP=$'\x1b[1;3A'
SHELLFRAME_KEY_ALT_DOWN=$'\x1b[1;3B'
SHELLFRAME_KEY_ALT_RIGHT=$'\x1b[1;3C'
SHELLFRAME_KEY_ALT_LEFT=$'\x1b[1;3D'
SHELLFRAME_KEY_CTRL_UP=$'\x1b[1;5A'
SHELLFRAME_KEY_CTRL_DOWN=$'\x1b[1;5B'
SHELLFRAME_KEY_CTRL_RIGHT=$'\x1b[1;5C'
SHELLFRAME_KEY_CTRL_LEFT=$'\x1b[1;5D'

# Output variables set by shellframe_read_key when a mouse event is parsed.
# Valid only when the most-recent key equals SHELLFRAME_KEY_MOUSE.
#   SHELLFRAME_MOUSE_BUTTON  — 0=left, 1=middle, 2=right, 64=scroll-up, 65=scroll-down
#   SHELLFRAME_MOUSE_COL     — 1-based terminal column
#   SHELLFRAME_MOUSE_ROW     — 1-based terminal row
#   SHELLFRAME_MOUSE_ACTION  — "press" or "release"
#   SHELLFRAME_MOUSE_SHIFT   — 1 if Shift was held during the mouse event
#   SHELLFRAME_MOUSE_META    — 1 if Meta/Alt was held during the mouse event
#   SHELLFRAME_MOUSE_CTRL    — 1 if Ctrl was held during the mouse event
SHELLFRAME_MOUSE_BUTTON=""
SHELLFRAME_MOUSE_COL=""
SHELLFRAME_MOUSE_ROW=""
SHELLFRAME_MOUSE_ACTION=""
SHELLFRAME_MOUSE_SHIFT=0
SHELLFRAME_MOUSE_META=0
SHELLFRAME_MOUSE_CTRL=0

# Read one keypress (including full escape sequences) into a variable.
#
# Usage:
#   local key
#   shellframe_read_key key
#   if   [[ "$key" == "$SHELLFRAME_KEY_UP"    ]]; then ...
#   elif [[ "$key" == "$SHELLFRAME_KEY_DOWN"  ]]; then ...
#   elif [[ "$key" == "$SHELLFRAME_KEY_ENTER" ]]; then ...
#
# Prerequisites: call inside a shellframe_raw_enter session so the terminal is in
# raw mode. Without raw mode, escape sequence bytes may echo between reads.
#
# Uses `read -d ''` (NUL delimiter) so that \n (produced by bash's internal
# \r→\n conversion when Enter is pressed) is captured as the key value rather
# than silently consumed as the line terminator.
#
# The -t 1 timeout on the follow-on reads handles a standalone ESC press
# gracefully (waits 1 s then returns just $'\x1b'). For arrow keys the
# follow-on bytes are already in the buffer and return immediately.
shellframe_read_key() {
    local _out_var="${1:-_SHELLFRAME_KEY}"
    local _k _c
    IFS= read -r -n1 -d '' _k
    if [[ "$_k" == $'\x1b' ]]; then
        IFS= read -r -n1 -d '' -t 1 _c
        _k+="${_c}"
        # CSI (ESC [) and SS3 (ESC O): read parameter bytes until a final byte.
        # Final bytes are letters (A-Z, a-z) or ~.  Bail on read timeout.
        #
        # This loop is the generic CSI drain path: it consumes the complete
        # sequence regardless of whether the resulting sequence is a recognized
        # key constant.  Unrecognized sequences (e.g. ESC [ 9 9 9 ~) are fully
        # drained so they cannot corrupt subsequent key reads.  The caller can
        # compare _k against any SHELLFRAME_KEY_* constant; unknown sequences
        # simply produce no match and are silently discarded.
        #
        # Sequence length coverage:
        #   3-byte:  ESC [ A           (arrow keys, shift_tab, home, end)
        #   4-byte:  ESC [ 3 ~         (delete, page_up, page_down, F5–F12)
        #   5-byte:  ESC O P           (F1–F4 via SS3; final byte in first read)
        #   7-byte:  ESC [ 1 ; 2 A     (modifier+arrow: shift/alt/ctrl + arrow)
        #   longer:  ESC [ 2 0 0 ~     (bracketed paste start/end)
        if [[ "$_c" == '[' || "$_c" == 'O' ]]; then
            while true; do
                IFS= read -r -n1 -d '' -t 1 _c || break
                _k+="${_c}"
                case "$_c" in
                    [A-Za-z~]) break ;;
                esac
            done
            # SGR mouse: ESC [ < Pb ; Px ; Py M (press) or m (release)
            # Detect by prefix ESC[< and letter final byte M or m.
            local _sgr_pfx=$'\x1b[<'
            if [[ "$_k" == "${_sgr_pfx}"* ]]; then
                local _params="${_k#"${_sgr_pfx}"}"   # strip ESC[<
                _params="${_params%[Mm]}"               # strip trailing M or m
                local _raw_btn="${_params%%;*}"
                SHELLFRAME_MOUSE_SHIFT=$(( (_raw_btn >> 2) & 1 ))
                SHELLFRAME_MOUSE_META=$(( (_raw_btn >> 3) & 1 ))
                SHELLFRAME_MOUSE_CTRL=$(( (_raw_btn >> 4) & 1 ))
                SHELLFRAME_MOUSE_BUTTON=$(( _raw_btn & ~28 ))
                local _rest="${_params#*;}"
                SHELLFRAME_MOUSE_COL="${_rest%%;*}"
                SHELLFRAME_MOUSE_ROW="${_rest#*;}"
                if [[ "$_k" == *M ]]; then
                    SHELLFRAME_MOUSE_ACTION="press"
                else
                    SHELLFRAME_MOUSE_ACTION="release"
                fi
                printf -v "$_out_var" '%s' "$SHELLFRAME_KEY_MOUSE"
                return 0
            fi
        fi
    fi
    printf -v "$_out_var" '%s' "$_k"
}
