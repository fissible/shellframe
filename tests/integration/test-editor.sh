#!/usr/bin/env bash
# tests/integration/test-editor.sh — PTY tests for examples/editor.sh

set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SHELLFRAME_DIR="$(cd "$TESTS_DIR/.."; pwd)"
PTY_RUN="$PTYUNIT_HOME/pty_run.py"
SCRIPT="$SHELLFRAME_DIR/examples/editor.sh"

source "$PTYUNIT_HOME/assert.sh"

_pty() {
    python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null
}

# ── Tests ─────────────────────────────────────────────────────────────────────

ptyunit_test_begin "editor: type text then Ctrl-D — text on stdout"
out=$(_pty h e l l o '\x04')
assert_contains "$out" "hello"

ptyunit_test_begin "editor: Enter creates a new line"
out=$(_pty h e l l o ENTER w o r l d '\x04')
assert_contains "$out" "hello"
assert_contains "$out" "world"

ptyunit_test_begin "editor: Backspace deletes last char"
out=$(_pty h e l l o BACKSPACE '\x04')
assert_contains "$out" "hell"

ptyunit_test_begin "editor: Ctrl-K clears line; replacement text is submitted"
# Type 'hello', go Home, kill to EOL, type 'abc', submit — result should be 'abc'
out=$(_pty h e l l o HOME '\x0b' a b c '\x04')
assert_contains "$out" "abc"

ptyunit_test_begin "editor: Ctrl-U clears to start of line; prefix text is submitted"
# Type 'helloworld', Left×5, Ctrl-U clears 'hello', result should be 'world'
out=$(_pty h e l l o w o r l d LEFT LEFT LEFT LEFT LEFT '\x15' '\x04')
assert_contains "$out" "world"


# ── #45: bracketed-paste bounds and sanitization ──────────────────────────────

# Exported so both the pty_run child AND the fixture inherit them
# (env-prefixing a shell function would not reach either).
_pty_paste() {
    ( export PTY_TIMEOUT=5 SHELLFRAME_EDITOR_PASTE_SILENCE_LIMIT=1
      python3 "$PTY_RUN" "$SCRIPT" "$@" 2>/dev/null )
}

ptyunit_test_begin "editor #45: lost paste terminator — drain ends on silence, text survives"
# Send ESC[200~ + text and NEVER send ESC[201~: the drain must end after
# SHELLFRAME_EDITOR_PASTE_SILENCE_LIMIT seconds of silence and insert what it
# gathered. Recovery is asserted via the status line moving to col 7
# (6 pasted chars): a submit keystroke cannot follow in this scenario —
# everything sent after a lost terminator is legitimately absorbed as
# paste content until the silence window fires.
out=$(_pty_paste $'\x1b[200~' p a s t e d)
assert_contains "$out" "col 7"

ptyunit_test_begin "editor #45: pasted ANSI escapes are stripped before insertion"
# pty_run strips ANSI from its capture, so a plain assertion is vacuous —
# it passes even with sanitization disabled. Capture RAW output instead and
# assert the injected SGR never reaches stdout through the submitted result.
# (The editor chrome emits reverse-video/dim, never red foreground.)
_raw_out=$( export PTY_TIMEOUT=15 SHELLFRAME_EDITOR_PASTE_SILENCE_LIMIT=5
            PTY_RAW=1 python3 "$PTY_RUN" "$SCRIPT" $'\x1b[200~' $'a\033[31mb' $'\x1b[201~' '\x04' 2>/dev/null )
if printf '%s' "$_raw_out" | grep -q $'\033[31m'; then
    ptyunit_fail "injected SGR survived into submitted text"
else
    ptyunit_pass
fi
out=$(_pty $'\x1b[200~' $'a\033[31mb' $'\x1b[201~' '\x04')
assert_contains "$out" "ab"

ptyunit_test_summary
