# clui — Bash TUI Library

A composable, full-featured terminal UI library for bash. Designed to be
sourced by other tools — each widget gathers input from a human and returns
clean data to the caller.

**Requirements:** bash 3.2+ (macOS default), a VT100-compatible terminal.

---

## Design goals

- **LEGO composability** — small, single-purpose components that snap together.
  Source only what you need; widgets never implicitly depend on each other.
- **Full UI lifecycle** — covers input gathering, selection, feedback, and output
  formatting. Every widget maps to a clear data shape (string, index, flag set).
- **Two audiences** — human-friendly keyboard behavior with discoverable footer
  hints; developer-friendly exit codes, namespaced globals, and stdout/tty split
  so widgets work correctly inside `$()` command substitution.
- **Self-configuring** — on first load, clui detects the bash version and
  terminal capabilities, writes feature flags to `.toolrc.local`, and reads them
  back on subsequent runs so code paths are chosen once per machine.
- **Cross-version tested** — a Docker-based test matrix runs the suite against
  bash 3.2, 4.4, and 5.x to catch portability regressions before they ship.

See [`CLAUDE.md`](CLAUDE.md) for the full development guidelines.

---

## Quick start

```bash
source /path/to/clui/clui.sh

clui_screen_enter
clui_raw_enter
clui_cursor_hide

# ... draw and loop ...

clui_raw_exit "$saved_stty"
clui_cursor_show
clui_screen_exit
```

See [`examples/list-select.sh`](examples/list-select.sh) for a complete
working interactive list selector.

---

## API

### `src/screen.sh`

| Function | Description |
|---|---|
| `clui_screen_enter` | Switch to alternate screen buffer + clear |
| `clui_screen_exit` | Restore original screen (undoes `clui_screen_enter`) |
| `clui_screen_clear` | Clear screen + move cursor home (for redraws) |
| `clui_cursor_hide` | Hide cursor (`\033[?25l`) |
| `clui_cursor_show` | Show cursor (`\033[?25h`) |
| `clui_raw_save` | Print current stty state (capture with `$(...)`) |
| `clui_raw_enter` | Set raw terminal mode for the TUI session |
| `clui_raw_exit "$saved"` | Restore terminal to saved stty state |

### `src/input.sh`

| Symbol | Value | Description |
|---|---|---|
| `CLUI_KEY_UP` | `\x1b[A` | Up arrow |
| `CLUI_KEY_DOWN` | `\x1b[B` | Down arrow |
| `CLUI_KEY_RIGHT` | `\x1b[C` | Right arrow |
| `CLUI_KEY_LEFT` | `\x1b[D` | Left arrow |
| `CLUI_KEY_ENTER` | `\n` | Enter / Return (bash converts `\r`→`\n` internally) |
| `CLUI_KEY_SPACE` | ` ` | Space |
| `CLUI_KEY_ESC` | `\x1b` | Standalone Escape |

**`clui_read_key <varname>`**

Reads one keypress (including full escape sequences) into `$varname`.
Call inside a `clui_raw_enter` session. Compare results against the
`CLUI_KEY_*` constants using `[[ "$key" == "$CLUI_KEY_UP" ]]`.
Uses `read -d ''` (NUL delimiter) so Enter (`\n`) is captured rather
than consumed as the line terminator (see Lesson 7 in Hard-won Lessons).

### `src/draw.sh`

**`clui_pad_left <raw> <rendered> <width>`**

Left-aligns `$rendered` in a column of `$width` *visible* characters.
`$raw` must be the plain-text (no ANSI codes) equivalent of `$rendered`
so its `${#raw}` byte count equals its visible character count.

```bash
local raw="~/bin/gflow"
local rendered="${CLUI_GRAY}~/bin/${CLUI_RESET}${CLUI_BOLD}gflow${CLUI_RESET}"
printf '%b' "$(clui_pad_left "$raw" "$rendered" 20)"
```

Color constants `CLUI_BOLD`, `CLUI_RESET`, `CLUI_GREEN`, `CLUI_RED`,
`CLUI_PURPLE`, `CLUI_GRAY`, `CLUI_WHITE` are set via `tput` at source time.

### `src/widgets/action-list.sh`

**`clui_action_list [draw_row_fn] [extra_key_fn] [footer_text]`**

Full-screen interactive list where each row has a set of named actions the
user cycles through. Returns 0 on confirm, 1 on quit.

**Caller sets globals before calling:**

| Global | Description |
|---|---|
| `CLUI_AL_LABELS[@]` | Display label per row |
| `CLUI_AL_ACTIONS[@]` | Space-separated action list per row (e.g. `"nothing install"`) |
| `CLUI_AL_IDX[@]` | Current action index per row (init to 0) |
| `CLUI_AL_META[@]` | Optional per-row metadata string passed to callbacks |

**Widget sets globals (readable from callbacks):**

| Global | Description |
|---|---|
| `CLUI_AL_SELECTED` | Index of the currently highlighted row |
| `CLUI_AL_SAVED_STTY` | Saved stty state — use with `clui_raw_exit` in `extra_key_fn` |

**Built-in key bindings:** `↑`/`↓` move, `Space`/`→` cycle action, `Enter`/`c` confirm, `q` quit.

**draw_row_fn** signature: `draw_row_fn "$i" "$label" "$acts_str" "$aidx" "$meta"`
Must print one complete line (with `\n`). `CLUI_AL_SELECTED` is set globally.

**extra_key_fn** signature: `extra_key_fn "$key"`
Called for unhandled keys. Return 0=handled+redraw, 1=not handled, 2=quit.
Use `CLUI_AL_SAVED_STTY` to suspend the TUI (e.g. to run a pager).

See [`examples/action-list.sh`](examples/action-list.sh) for a complete demo.

### `src/widgets/confirm.sh`

**`clui_confirm <question> [detail ...]`**

Centered modal yes/no dialog. Optional plain-text `detail` lines are shown
above the question (e.g. a summary of pending changes). Returns 0 for Yes,
1 for No or cancel.

| Key | Action |
|---|---|
| `←`/`→`  `h`/`l` | Toggle between Yes and No |
| `y` / `Y` | Select Yes and confirm immediately |
| `n` / `N` | Select No and confirm immediately |
| `Enter` / `c` | Confirm current selection (default: Yes) |
| `Esc` / `q` / `Q` | Cancel (same as No) |

```bash
clui_confirm "Apply 3 pending changes?" \
    "  config.json   delete" \
    "  main.sh       install"

if (( $? == 0 )); then
    echo "applying..."
fi
```

See [`examples/confirm.sh`](examples/confirm.sh) for a complete demo.


---

## Recommended TUI skeleton

```bash
source /path/to/clui/clui.sh

my_tui() {
    # ── Setup ──────────────────────────────────────────────────────
    local saved_stty
    saved_stty=$(clui_raw_save)

    _exit() {
        clui_raw_exit "$saved_stty"
        clui_cursor_show
        clui_screen_exit
    }
    trap '_exit; exit 1' INT TERM

    clui_screen_enter   # enter alternate screen (restores on exit)
    clui_raw_enter      # raw mode: no echo, no line buffering
    clui_cursor_hide

    # ── Draw ───────────────────────────────────────────────────────
    _draw() {
        clui_screen_clear
        # ... printf your UI here ...
    }
    _draw

    # ── Input loop ─────────────────────────────────────────────────
    local key
    while true; do
        clui_read_key key
        if   [[ "$key" == "$CLUI_KEY_UP"    ]]; then : # handle up
        elif [[ "$key" == "$CLUI_KEY_DOWN"  ]]; then : # handle down
        elif [[ "$key" == "$CLUI_KEY_ENTER" ]]; then break
        elif [[ "$key" == 'q' ]]; then break
        fi
        _draw
    done

    # ── Teardown ───────────────────────────────────────────────────
    trap - INT TERM
    _exit
}
```

---

## Hard-won lessons

These are the bugs that took iteration to find. Document them so they aren't
rediscovered.

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

### 6. ANSI codes inflate byte counts for printf width padding

`printf "%-20s"` measures field width in bytes. An ANSI reset sequence like
`\033[0m` adds 4 bytes of width with 0 visible characters. Colored strings
come out under-padded. Keep a plain-text `raw` copy of every colored string
and use its `${#raw}` length to compute padding manually.

```bash
# ✗ — padding is too short because ANSI bytes inflate the measurement
printf "%-20b" "${CLUI_GREEN}hello${CLUI_RESET}"

# ✓ — measure raw, output rendered + explicit padding
printf '%b' "$(clui_pad_left "hello" "${CLUI_GREEN}hello${CLUI_RESET}" 20)"
```

### 7. bash `read` converts `\r` to `\n` internally — use `read -d ''` for Enter

Even with `stty -icrnl` set (so the PTY line discipline does NOT translate
CR→LF), bash's own `read` builtin converts `\r` (0x0D) to `\n` (0x0A) before
storing the result. The consequence:

- `IFS= read -r -n1 key` with default `\n` delimiter: `\r` → `\n` → delimiter
  → `key` is empty (the delimiter is consumed, not stored).
- The fix is `read -d ''` (NUL delimiter), so `\n` is not the stop character
  and is captured as the key value.
- Set `CLUI_KEY_ENTER=$'\n'`, not `$'\r'`.

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

### 9. `exec fd_redirect 2>/dev/null` permanently silences stderr

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

### 8. Command substitution `$()` pipes stdout away from the terminal

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

---

## Portability

The key known portability difference is bash 3.2 (macOS default): no decimal
`-t` timeouts, no `{varname}` fd allocation, and subtly different `read`
behavior — all documented in [Hard-won lessons](#hard-won-lessons).

To test against multiple bash versions locally, use the Docker matrix:

```bash
bash tests/docker/run-matrix.sh           # bash 3.2, 4.4, 5.x
bash tests/docker/run-matrix.sh --no-cache  # force clean rebuild
```

---

## File layout

```
clui/
├── clui.sh          # entry point — source this
├── .dockerignore    # excludes .git and .toolrc.local from Docker builds
├── src/
│   ├── screen.sh    # alternate screen, cursor, stty
│   ├── input.sh     # key reading + CLUI_KEY_* constants
│   ├── draw.sh      # clui_pad_left, color constants
│   └── widgets/
│       ├── action-list.sh  # interactive action-list widget
│       └── confirm.sh      # modal yes/no confirmation dialog
├── examples/
│   ├── list-select.sh      # single-select list demo
│   ├── action-list.sh      # action-list widget demo
│   └── confirm.sh          # confirm modal demo
└── tests/
    ├── assert.sh            # test assertion helpers
    ├── pty_run.py           # PTY-based integration test runner
    ├── run.sh               # test runner (discovers test-*.sh)
    ├── docker/              # cross-version portability matrix
    │   ├── run-matrix.sh    # runs suite against all bash versions
    │   ├── Dockerfile.bash3 # bash 3.2 (simulates macOS)
    │   ├── Dockerfile.bash4 # bash 4.4
    │   └── Dockerfile.bash5 # bash 5.x
    ├── unit/
    │   └── test-draw.sh     # unit tests for clui_pad_left
    └── integration/
        ├── test-list-select.sh   # PTY tests for list-select example
        ├── test-action-list.sh   # PTY tests for action-list widget
        └── test-confirm.sh       # PTY tests for confirm modal
```

