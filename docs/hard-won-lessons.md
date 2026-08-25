# shellframe — Hard-won lessons

These are the bugs that took iteration to find. Documented so they aren't
rediscovered.

---

### 1. `read -t` requires integers on bash 3.2 (macOS)

macOS ships bash 3.2 (GPL licensing). Decimal timeouts like `read -t 0.1`
produce `read: 0.1: invalid timeout specification` and fail silently.
**Use `-t 1` (integer).** For arrow keys this is fine — the follow-on `[A`/`[B`
bytes are already in the buffer when the second `read` fires, so `-t 1` is
never actually reached. It only matters for standalone ESC detection.

```bash
# ✗ breaks on bash 3.2
IFS= read -r -n1 -t 0.1 next

# ✓ works everywhere
IFS= read -r -n1 -t 1 next
```

---

### 2. `case '[A')` is a glob, not a string

In bash `case` patterns, `[A` begins a bracket expression (like in globs and
`[[ ]]`). Without a closing `]`, the behavior is undefined and in practice the
pattern often matches nothing useful. Store sequences in variables and compare
with `[[ "$key" == "$var" ]]` for exact matching.

```bash
# ✗ — [A is a bracket expression
case "$key" in
    $'\x1b[A') echo up ;;
esac

# ✓ — exact string comparison
local K_UP=$'\x1b[A'
if [[ "$key" == "$K_UP" ]]; then echo up; fi
```

---

### 3. `read -s` is per-call, not per-session

`read -s` suppresses echo only while that `read` call is executing. The moment
it returns, the terminal is back to echoing mode. If the next bytes of an
escape sequence arrive between two `read` calls they echo visibly (you'll see
`[B` appear on screen). Use `stty -echo` to suppress echo for the whole
session.

```bash
# ✗ — echo suppressed only during read
while true; do IFS= read -rsn1 key; ...; done

# ✓ — echo suppressed for the entire loop
stty -echo -icanon min 1 time 0
while true; do IFS= read -r -n1 key; ...; done
stty "$saved"
```

---

### 4. `read -n2` with `stty min 1` returns after 1 byte

`stty min 1 time 0` tells the OS to return from `read()` as soon as at least
1 byte is available. bash's `read -nN` reads *at most* N characters, so
`read -n2` may satisfy itself with just 1 byte. Read escape sequences one byte
at a time with `read -n1`.

```bash
# ✗ — may only read '[', leaves 'A' in buffer
IFS= read -r -n2 -t 1 rest

# ✓ — reads exactly 1 byte each call
IFS= read -r -n1 -t 1 c1
IFS= read -r -n1 -t 1 c2
```

---

### 5. Use raw sequences, not `tput smcup`/`rmcup`

`tput smcup` and `tput rmcup` depend on the terminfo database and can exit 0
without producing output when `$TERM` is unset or unrecognized. The raw ANSI
sequences are universally supported by modern terminal emulators.

```bash
# ✗ — may silently do nothing
tput smcup
tput rmcup

# ✓ — always works in VT100-compatible terminals
printf '\033[?1049h'   # enter alternate screen
printf '\033[?1049l'   # exit alternate screen
```

---

### 6. ANSI codes inflate byte counts for printf width padding

`printf "%-20s"` measures field width in bytes. An ANSI reset sequence like
`\033[0m` adds 4 bytes of width with 0 visible characters. Colored strings
come out under-padded. Keep a plain-text `raw` copy of every colored string
and use its `${#raw}` length to compute padding manually.

```bash
# ✗ — padding is too short because ANSI bytes inflate the measurement
printf "%-20b" "${SHELLFRAME_GREEN}hello${SHELLFRAME_RESET}"

# ✓ — measure raw, output rendered + explicit padding
printf '%s' "$(shellframe_pad_left "hello" "${SHELLFRAME_GREEN}hello${SHELLFRAME_RESET}" 20)"
```

---

### 7. bash `read` converts `\r` to `\n` internally — use `read -d ''` for Enter

Even with `stty -icrnl` set (so the PTY line discipline does NOT translate
CR→LF), bash's own `read` builtin converts `\r` (0x0D) to `\n` (0x0A) before
storing the result. The consequence:

- `IFS= read -r -n1 key` with default `\n` delimiter: `\r` → `\n` → delimiter
  → `key` is empty (the delimiter is consumed, not stored).
- The fix is `read -d ''` (NUL delimiter), so `\n` is not the stop character
  and is captured as the key value.
- Set `SHELLFRAME_KEY_ENTER=$'\n'`, not `$'\r'`.

```bash
# ✗ — Enter becomes the delimiter; key is always empty on Enter
IFS= read -r -n1 key
[[ "$key" == $'\r' ]]  # never matches

# ✓ — NUL delimiter; \n (from bash's \r→\n conversion) is stored in key
IFS= read -r -n1 -d '' key
[[ "$key" == $'\n' ]]  # matches Enter
```

This was verified empirically: `dd` correctly receives `\r` from the PTY
(confirming `-icrnl` works), but bash's `read` returns `\n`. The behavior
holds on bash 3.2 (macOS) in both PTY and real-terminal contexts.

---

### 8. `exec fd_redirect 2>/dev/null` permanently silences stderr

When `exec` is used without a command (to permanently redirect file
descriptors), all redirections on the `exec` line are applied permanently to
the shell process — including `2>/dev/null`. This is not a "suppress errors
from this one command" guard; it destroys stderr for all future code in the
process.

This matters whenever a TUI function restores stdout from a saved fd. The
`2>/dev/null` is typically added to suppress "bad file descriptor" noise if
the saved fd is somehow invalid, but it silently breaks all subsequent
`read -p` prompts, `printf >&2` output, and anything else that writes to fd 2.

```bash
# ✗ — permanently redirects fd 2 to /dev/null for the rest of the shell
exec 1>&3  2>/dev/null || true   # stderr is now gone for the caller too

# ✓ — wrap in a compound command to scope the error suppression
{ exec 1>&3; } 2>/dev/null || true   # stderr is restored after the { } block
```

The symptom is subtle: `read -p "prompt"` appears to hang (it's waiting for
input that never comes because the invisible prompt prevents the user from
knowing they need to type), and any diagnostic `printf ... >&2` lines you add
to debug the hang also disappear — which is what makes this bug hard to find.

---

### 9. Command substitution `$()` pipes stdout away from the terminal

Calling a TUI function as `result=$(my_tui)` creates a subshell where stdout
is a pipe, not the terminal. All `printf` screen output silently disappears
into the pipe and the UI never renders — the script just hangs on `read`.

Fix: redirect stdout to `/dev/tty` inside the function for all display output,
then restore the original stdout before printing the return value.

```bash
my_tui() {
    # Use fixed fd 3; {varname} fd allocation requires bash 4.1+ (macOS has 3.2)
    exec 3>&1
    exec 1>/dev/tty          # TUI output goes to the real terminal

    # ... screen enter, draw loop, input loop ...

    exec 1>&3                # restore so the result is captured by $()
    exec 3>&-

    printf '%s\n' "$result"  # this reaches the $() caller
}

chosen=$(my_tui)             # works correctly
```

## 10. `read -t 0` destroys buffered input — never use it as an "input pending" probe

**Symptom:** the v2 shell runtime's original render-coalescing prototype
(`read -t 0` to check for queued input before drawing) was blamed for a
"crash in raw terminal mode" and disabled.

**Correction (2026-08-25, after reviewer challenge):** an initial re-
investigation claimed the probe consumes buffered input on bash ≥4; that was
an artifact of testing against a pipe whose writer had already closed — under
realistic held-open conditions (fifo/PTY, plain or raw-mode) input survives
the probe intact on bash 3.2 and 5.x. The consumption claim is withdrawn.

What remains true and load-bearing:
- `read -t 0` availability semantics are version- and option-dependent
  (rc=1/no-read on 3.2; rc=0-empty vs rc=0-with-data varies with -n/-d),
  making any probe-based gate fragile across the matrix.
- The historical crash was never actually explained.

The time-based coalescing now shipped is therefore justified on its own
merits: it never touches the input stream at all, so it is correct regardless
of probe semantics, and it renders at a bounded rate. See
`_shellframe_should_defer_render` in `src/shell.sh`. The original crash
remains open as an unsolved mystery — if it resurfaces, investigate the
deferred-render path first.
