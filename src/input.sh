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

# Output variable set by shellframe_read_key when stdin has reached EOF
# (#44). 1 = EOF; reset to 0 at the start of every call. The initial read is
# untimed, so EOF (rc=1, empty value) is unambiguous on all bash versions.
# Widget loops must check this flag and exit cancelled instead of spinning.
SHELLFRAME_KEY_EOF=0

# Output variable set by shellframe_read_key when an optional timeout was
# given and expired with no input. 1 = timed out; reset to 0 every call.
SHELLFRAME_KEY_TIMEOUT=0

# Output variable set by _shellframe_parse_sgr_mouse when the event is a
# motion report (button-mask bit 32). Motion events are parsed then DISCARDED
# by both readers — hover/drag is #57 scope — but the flag documents what was
# seen. Reset on every parse.
SHELLFRAME_MOUSE_MOTION=0

# _shellframe_parse_sgr_mouse <sequence>
#
# The single SGR mouse decoder (ESC [ < Pb ; Px ; Py M|m) used by every
# reader (#46 — the two inline copies had already drifted). Validates that
# exactly three numeric fields are present; malformed sequences are silently
# discarded, because a terminal emitting them will emit more and one bad
# event must never poison the coordinate globals.
#
# Motion reports (bit 32) are validated, flagged via SHELLFRAME_MOUSE_MOTION,
# and discarded: no consumer supports hover yet (#57), and letting bit 32
# leak into SHELLFRAME_MOUSE_BUTTON surfaced as phantom "button 32" presses.
#
# Returns 0 and sets the SHELLFRAME_MOUSE_* globals on a consumable press or
# release; returns 1 on discard (malformed or motion).
_shellframe_parse_sgr_mouse() {
    local _seq="$1"
    local _sgr_pfx=$'\033[<'
    SHELLFRAME_MOUSE_MOTION=0

    [[ "$_seq" == "${_sgr_pfx}"* ]] || return 1

    local _params="${_seq#"${_sgr_pfx}"}"
    _params="${_params%[Mm]}"
    # Quoted via variable: an unquoted regex containing ';' is a parse error
    local _num_re='^[0-9]+;[0-9]+;[0-9]+$'
    [[ "$_params" =~ $_num_re ]] || return 1

    # ACTION is set only after validation so a rejected sequence cannot leave
    # a stale disposition behind (review round 3)
    case "$_seq" in
        *M) SHELLFRAME_MOUSE_ACTION="press"   ;;
        *m) SHELLFRAME_MOUSE_ACTION="release" ;;
    esac

    local _raw_btn="${_params%%;*}"
    local _rest="${_params#*;}"

    if (( _raw_btn & 32 )); then
        SHELLFRAME_MOUSE_MOTION=1
        return 1   # motion: parsed, flagged, dropped (#46; hover is #57)
    fi

    SHELLFRAME_MOUSE_SHIFT=$(( (_raw_btn >> 2) & 1 ))
    SHELLFRAME_MOUSE_META=$(( (_raw_btn >> 3) & 1 ))
    SHELLFRAME_MOUSE_CTRL=$(( (_raw_btn >> 4) & 1 ))
    # Clear shift/alt/ctrl/motion bits (4+8+16+32); keep buttons 0-2, wheel 64/65.
    SHELLFRAME_MOUSE_BUTTON=$(( _raw_btn & ~60 ))
    SHELLFRAME_MOUSE_COL="${_rest%%;*}"
    SHELLFRAME_MOUSE_ROW="${_rest#*;}"
    return 0
}

# Read one keypress (including full escape sequences) into a variable.
#
# Usage:
#   local key
#   shellframe_read_key key              # block until a key arrives
#   shellframe_read_key key 5            # give up after 5 idle seconds
#
# On timeout expiry the output variable is set to "" and
# SHELLFRAME_KEY_TIMEOUT=1; no data means the caller decides what silence
# means (e.g. the editor's paste drain treats it as paste-end, #45).
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
    local _timeout="${2:-}"
    local _k _c _rc=0

    SHELLFRAME_KEY_EOF=0
    SHELLFRAME_KEY_TIMEOUT=0

    # Fractional timeouts are invalid on bash 3.2 (integer-only -t); floor to
    # a minimum of 1 s there so a sub-second limit cannot end reads instantly.
    if [[ -n "$_timeout" ]] && (( BASH_VERSINFO[0] < 4 )); then
        _timeout="${_timeout%%.*}"
        [[ -z "$_timeout" ]] && _timeout=1
        (( _timeout < 1 )) && _timeout=1
    fi

    if [[ -n "$_timeout" ]]; then
        IFS= read -r -n1 -d '' -t "$_timeout" _k || _rc=$?
        if [[ -z "$_k" ]]; then
            # Three ways to arrive here with an empty value:
            #   rc > 128        timer expired            -> TIMEOUT
            #   0 < rc <= 128   stdin EOF                -> EOF
            #   rc == 0         the delimiter (a NUL byte) was read -> a
            #                     literal NUL keystroke: empty key, NO flags
            #                   (treating it as EOF made the editor drop a
            #                   whole paste containing one NUL — review #45)
            if (( _rc == 0 )); then
                :
            elif (( BASH_VERSINFO[0] >= 4 )) && (( _rc > 128 )); then
                SHELLFRAME_KEY_TIMEOUT=1
            elif (( BASH_VERSINFO[0] >= 4 )); then
                SHELLFRAME_KEY_EOF=1
            else
                SHELLFRAME_KEY_TIMEOUT=1   # 3.2 cannot separate them; conservative
            fi
            printf -v "$_out_var" '%s' ""
            return 0
        fi
    else
        IFS= read -r -n1 -d '' _k || _rc=$?
        if [[ -z "$_k" ]]; then
            if (( _rc != 0 )); then
                SHELLFRAME_KEY_EOF=1
                printf -v "$_out_var" '%s' ""
                return 0
            fi
            # else: a literal NUL keystroke — fall through with empty value
        fi
    fi
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
            # SGR mouse only (ESC[< prefix): decode via the shared validated
            # parser (#46). Malformed or motion events are CONSUMED silently
            # (review round 2, blocker 2) — letting them fall through made
            # "any key" widgets dismiss on drag steps. All other sequences
            # fall through and are returned raw.
            case "$_k" in
                $'\x1b[<'*)
                    if _shellframe_parse_sgr_mouse "$_k"; then
                        printf -v "$_out_var" '%s' "$SHELLFRAME_KEY_MOUSE"
                    else
                        printf -v "$_out_var" '%s' ""
                    fi
                    return 0 ;;
            esac
        fi
    fi
    printf -v "$_out_var" '%s' "$_k"
}
