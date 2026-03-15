# shellframe — API Reference

---

## `src/clip.sh`

String measurement and clipping utilities using the **raw + rendered** convention:
`raw` is the plain-text version of the string (no ANSI codes) — its byte length
equals its visible character count. `rendered` is the same content with ANSI
escape codes interspersed. This sidesteps ANSI-stripping regex portability bugs.

**`shellframe_str_len raw`**

Print the visible character count of `$raw` (i.e. `${#raw}`).

**`shellframe_str_clip raw rendered width`**

Print `$rendered` hard-clipped to at most `$width` visible characters.
If the visible length already fits, `$rendered` is printed unchanged (fast path).
If `$width ≤ 0`, prints nothing.
Appends `\033[0m` (SGR reset) only when truncation occurred **and** ANSI sequences
were present in the consumed portion, to prevent color bleed.

**`shellframe_str_clip_ellipsis raw rendered width`**

Like `shellframe_str_clip` but replaces the last character with `…` when
truncation occurs. If `$width == 1`, prints just `…`. If `$width ≤ 0`, prints nothing.

**`shellframe_str_pad raw rendered width`**

Left-align `$rendered` in a field of `$width` visible characters (space-padded right).
Does not truncate — combine with `shellframe_str_clip` first if needed.
Replacement for `shellframe_pad_left` with consistent naming; `shellframe_pad_left`
is retained for backwards compatibility.

```bash
local raw="hello world"
local rendered="${SHELLFRAME_GREEN}hello world${SHELLFRAME_RESET}"
printf '%s\n' "$(shellframe_str_clip "$raw" "$rendered" 5)"        # → green "hello"
printf '%s\n' "$(shellframe_str_clip_ellipsis "$raw" "$rendered" 6)" # → green "hello…"
printf '%s\n' "$(shellframe_str_pad "$raw" "$rendered" 15)"         # → green "hello world    "
```

---

## `src/selection.sh`

Shared cursor and multi-select state model for list-like components.
State is keyed by a **context name** (`ctx`) — an alphanumeric identifier that
allows multiple independent selection states to coexist on screen simultaneously.

### Cursor

The cursor is the currently highlighted row index (0-based integer, always in
range `[0, count-1]`).

### Multi-select

An independent boolean flag per row. Toggling an item adds/removes it from the
selection set. The cursor position and selection set are orthogonal — moving the
cursor does not change selection.

### Functions

**`shellframe_sel_init ctx count`**

Initialise (or reset) a context with `count` items. Sets cursor to 0, clears all
flags. Must be called before any other function for a new context.

**`shellframe_sel_move ctx direction [page_size]`**

Move the cursor. `direction`: `up` | `down` | `home` | `end` | `page_up` | `page_down`.
`page_size` defaults to 10. Cursor is clamped to `[0, count-1]`.

**`shellframe_sel_toggle ctx [index]`**

Toggle the multi-select flag for `$index` (default: current cursor row).

**`shellframe_sel_select_all ctx`** / **`shellframe_sel_clear_all ctx`**

Set all flags to 1 (or 0).

**`shellframe_sel_cursor ctx`** → prints cursor index

**`shellframe_sel_count ctx`** → prints total item count

**`shellframe_sel_selected ctx`** → prints space-separated selected indices (blank line if none)

**`shellframe_sel_selected_count ctx`** → prints count of selected items

**`shellframe_sel_is_selected ctx index`** → returns 0 if selected, 1 if not

```bash
shellframe_sel_init "mylist" 5
shellframe_sel_move "mylist" down
shellframe_sel_toggle "mylist"                     # toggle item at cursor (1)
shellframe_sel_toggle "mylist" 3                   # toggle item 3 explicitly
shellframe_sel_selected "mylist"                   # → "1 3"
shellframe_sel_is_selected "mylist" 1 && echo yes  # → yes
```

---

## `src/screen.sh`

| Function | Description |
|---|---|
| `shellframe_screen_enter` | Switch to alternate screen buffer + clear |
| `shellframe_screen_exit` | Restore original screen (undoes `shellframe_screen_enter`) |
| `shellframe_screen_clear` | Clear screen + move cursor home (for redraws) |
| `shellframe_cursor_hide` | Hide cursor (`\033[?25l`) |
| `shellframe_cursor_show` | Show cursor (`\033[?25h`) |
| `shellframe_raw_save` | Print current stty state (capture with `$(...)`) |
| `shellframe_raw_enter` | Set raw terminal mode for the TUI session |
| `shellframe_raw_exit "$saved"` | Restore terminal to saved stty state |

---

## `src/input.sh`

| Symbol | Value | Description |
|---|---|---|
| `SHELLFRAME_KEY_UP` | `\x1b[A` | Up arrow |
| `SHELLFRAME_KEY_DOWN` | `\x1b[B` | Down arrow |
| `SHELLFRAME_KEY_RIGHT` | `\x1b[C` | Right arrow |
| `SHELLFRAME_KEY_LEFT` | `\x1b[D` | Left arrow |
| `SHELLFRAME_KEY_ENTER` | `\n` | Enter / Return (bash converts `\r`→`\n` internally) |
| `SHELLFRAME_KEY_SPACE` | ` ` | Space |
| `SHELLFRAME_KEY_ESC` | `\x1b` | Standalone Escape |

**`shellframe_read_key <varname>`**

Reads one keypress (including full escape sequences) into `$varname`.
Call inside a `shellframe_raw_enter` session. Compare results against the
`SHELLFRAME_KEY_*` constants using `[[ "$key" == "$SHELLFRAME_KEY_UP" ]]`.
Uses `read -d ''` (NUL delimiter) so Enter (`\n`) is captured rather
than consumed as the line terminator (see [Hard-won lessons](hard-won-lessons.md#7-bash-read-converts-r-to-n-internally--use-read--d--for-enter)).

---

## `src/draw.sh`

**`shellframe_pad_left <raw> <rendered> <width>`**

Left-aligns `$rendered` in a column of `$width` *visible* characters.
`$raw` must be the plain-text (no ANSI codes) equivalent of `$rendered`
so its `${#raw}` byte count equals its visible character count.

```bash
local raw="~/bin/gflow"
local rendered="${SHELLFRAME_GRAY}~/bin/${SHELLFRAME_RESET}${SHELLFRAME_BOLD}gflow${SHELLFRAME_RESET}"
printf '%b' "$(shellframe_pad_left "$raw" "$rendered" 20)"
```

Color constants `SHELLFRAME_BOLD`, `SHELLFRAME_RESET`, `SHELLFRAME_GREEN`, `SHELLFRAME_RED`,
`SHELLFRAME_PURPLE`, `SHELLFRAME_GRAY`, `SHELLFRAME_WHITE` are set via `tput` at source time.

---

## `src/widgets/action-list.sh`

**`shellframe_action_list [draw_row_fn] [extra_key_fn] [footer_text]`**

Full-screen interactive list where each row has a set of named actions the
user cycles through. Returns 0 on confirm, 1 on quit.

**Caller sets globals before calling:**

| Global | Description |
|---|---|
| `SHELLFRAME_AL_LABELS[@]` | Display label per row |
| `SHELLFRAME_AL_ACTIONS[@]` | Space-separated action list per row (e.g. `"nothing install"`) |
| `SHELLFRAME_AL_IDX[@]` | Current action index per row (init to 0) |
| `SHELLFRAME_AL_META[@]` | Optional per-row metadata string passed to callbacks |

**Widget sets globals (readable from callbacks):**

| Global | Description |
|---|---|
| `SHELLFRAME_AL_SELECTED` | Index of the currently highlighted row |
| `SHELLFRAME_AL_SAVED_STTY` | Saved stty state — use with `shellframe_raw_exit` in `extra_key_fn` |

**Built-in key bindings:** `↑`/`↓` move, `Space`/`→` cycle action, `Enter`/`c` confirm, `q` quit.

**draw_row_fn** signature: `draw_row_fn "$i" "$label" "$acts_str" "$aidx" "$meta"`
Must print one complete line (with `\n`). `SHELLFRAME_AL_SELECTED` is set globally.

**extra_key_fn** signature: `extra_key_fn "$key"`
Called for unhandled keys. Return 0=handled+redraw, 1=not handled, 2=quit.
Use `SHELLFRAME_AL_SAVED_STTY` to suspend the TUI (e.g. to run a pager).

See [`examples/action-list.sh`](../examples/action-list.sh) for a complete demo.

---

## `src/widgets/table.sh`

**`shellframe_table [draw_row_fn] [extra_key_fn] [footer_text]`**

Full-page navigable table widget with column headers, full-height/full-width layout,
vertical scroll, optional page chrome (header bar, h1 title, footer bar), and an
optional below-hint area for inline contextual content.
Returns 0 on confirm, 1 on quit.

### Table data globals

Caller sets before calling `shellframe_table` (or in a `render()` hook for `shellframe_app`):

| Global | Description |
|---|---|
| `SHELLFRAME_TBL_LABELS[@]` | Primary display label per row |
| `SHELLFRAME_TBL_ACTIONS[@]` | Space-separated available actions per row (e.g. `"nothing install"`) |
| `SHELLFRAME_TBL_IDX[@]` | Current action index per row (caller initialises to 0) |
| `SHELLFRAME_TBL_META[@]` | (Optional) per-row metadata string passed verbatim to callbacks |
| `SHELLFRAME_TBL_HEADERS[@]` | Column header labels (plain text); empty disables the header row |
| `SHELLFRAME_TBL_COL_WIDTHS[@]` | Visible character width per column; columns are left-aligned |

### Page chrome globals

| Global | Description |
|---|---|
| `SHELLFRAME_TBL_PAGE_TITLE` | Header bar text — reverse-video, bold, full-width, row 1. Empty = no header. |
| `SHELLFRAME_TBL_PAGE_H1` | Content area h1 title — bold white, row 2. Empty = no h1. |
| `SHELLFRAME_TBL_PAGE_FOOTER` | Footer bar text — gray, full-width, pinned to bottom row. Empty = no footer. |

When `PAGE_TITLE` or `PAGE_H1` is set, rows 1-3 are occupied (header, h1, separator) and
data starts at row 4. When `PAGE_FOOTER` is set, the last two rows are the footer separator
and footer bar, and the content area shrinks accordingly.

### Panel and below-hint globals

| Global | Description |
|---|---|
| `SHELLFRAME_TBL_PANEL_FN` | Right-panel callback: `fn top_row left_col width height`. Splits the content area 50/50. Suppressed if the terminal is too narrow for a 20-column panel. Empty = full-width table. |
| `SHELLFRAME_TBL_BELOW_FN` | Below-hint callback: `fn first_row left_col cols height`. Called below the keyboard hint, separated by a thin `─` rule. Empty = no below area. |
| `SHELLFRAME_TBL_BELOW_ROWS` | Number of content rows to reserve for `SHELLFRAME_TBL_BELOW_FN`. Must be ≥ 1 to activate the below area. |

### State globals (readable from callbacks)

| Global | Description |
|---|---|
| `SHELLFRAME_TBL_SELECTED` | Index of the currently highlighted row |
| `SHELLFRAME_TBL_SCROLL` | First visible row index (vertical scroll offset). NOT reset by `shellframe_app` — set it to 0 in your render hook when loading new data. |
| `SHELLFRAME_TBL_SAVED_STTY` | Saved stty state — use with `shellframe_raw_exit` in `extra_key_fn` to temporarily suspend the TUI |

**Built-in key bindings:** `↑`/`↓` move, `Space`/`→` cycle action, `Enter`/`c` confirm, `q` quit.

**draw_row_fn** signature: `draw_row_fn "$i" "$label" "$acts_str" "$aidx" "$meta"`
Called once per visible row. The cursor is pre-positioned at `(row, 1)` and the line is
erased with `\033[2K`. Print one line of content. `SHELLFRAME_TBL_SELECTED` is set globally.

**extra_key_fn** signature: `extra_key_fn "$key"`
Called for unhandled keys. Return 0 = handled (redraw), 1 = not handled, 2 = quit requested.
Use `SHELLFRAME_TBL_SAVED_STTY` to suspend the TUI (e.g. to run a pager).

**draw_row_fn / extra_key_fn** within `shellframe_app`: pass callback names via
`_SHELLFRAME_APP_DRAW_FN` and `_SHELLFRAME_APP_KEY_FN` in your render hook.

### Layout diagram (all chrome enabled)

```
Row 1         : ██ PAGE_TITLE ██████████████████████████  ← reverse-video header bar
Row 2         :    PAGE_H1                                 ← bold h1
Row 3         :  ─────────────────────────────────────    ← separator
Rows 4..N-4   :    [col headers]                          ← if HEADERS set (+2 rows)
               :    data row 0
               :    data row 1
               :    ...
Row N-3       :    ↑/↓ move  Space cycle  Enter confirm   ← keyboard hint
Row N-2       :  ──────────────────────────────────────   ← below separator (if BELOW_FN)
Row N-1 (sep) :  ─────────────────────────────────────    ← separator above footer
Row N         : ░ PAGE_FOOTER ░░░░░░░░░░░░░░░░░░░░░░░░░  ← gray footer bar
```

---

## `src/widgets/confirm.sh`

**`shellframe_confirm <question> [detail ...]`**

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
shellframe_confirm "Apply 3 pending changes?" \
    "  config.json   delete" \
    "  main.sh       install"

if (( $? == 0 )); then
    echo "applying..."
fi
```

See [`examples/confirm.sh`](../examples/confirm.sh) for a complete demo.

---

## `src/widgets/alert.sh`

**`shellframe_alert <title> [detail ...]`**

Centered informational modal. Shows a bold `title` heading and optional
plain-text `detail` lines. Any keypress dismisses it. Always returns 0.

| Key | Action |
|---|---|
| Any key | Dismiss |

```bash
shellframe_alert "Deploy complete" \
    "web-server    restarted" \
    "cache         flushed"

echo "Back in the shell."
```

See [`examples/alert.sh`](../examples/alert.sh) for a complete demo.

---

## `src/app.sh`

**`shellframe_app <prefix> [initial_screen]`**

Declarative application runtime. Models a TUI application as a
finite-state machine: screens are states, keypresses produce events,
event handlers return the next screen name. `shellframe_app` owns the session
loop — you declare the screens; it handles widget dispatch and transitions.
`initial_screen` defaults to `ROOT`. Returns when any handler sets `_SHELLFRAME_APP_NEXT="__QUIT__"`.

### Screen functions

For each screen `FOO`, define three functions (replace `PREFIX` with your
chosen prefix):

| Function | How it outputs | Purpose |
|---|---|---|
| `PREFIX_FOO_type()` | `printf` | One of: `action-list` \| `table` \| `confirm` \| `alert` — called in a subshell, do not modify globals |
| `PREFIX_FOO_render()` | *(assigns globals)* | Populate widget context globals; called directly, safe to mutate state |
| `PREFIX_FOO_EVENT()` | `_SHELLFRAME_APP_NEXT=` | Set `_SHELLFRAME_APP_NEXT` to next screen name; called directly, safe to mutate state |

**Events** each widget type produces:

| Widget | rc=0 event | rc=1 event |
|---|---|---|
| `action-list` | `confirm` | `quit` |
| `table` | `confirm` | `quit` |
| `confirm` | `yes` | `no` |
| `alert` | `dismiss` | — |

### Output global

| Global | Set by | Purpose |
|---|---|---|
| `_SHELLFRAME_APP_NEXT` | `EVENT()` handlers | Next screen name (or `__QUIT__`). Reset to `""` before each event call. |

Event handlers run in the **current shell** (not a subshell), so they can freely
read and write application state globals alongside setting `_SHELLFRAME_APP_NEXT`.

### Widget context globals

Set these in your `render()` hook. They are reset to empty before every
`render()` call, so each screen starts from a clean slate.

| Global | Widget | Purpose |
|---|---|---|
| `_SHELLFRAME_APP_DRAW_FN` | `action-list` / `table` | Row renderer callback name (empty → built-in default) |
| `_SHELLFRAME_APP_KEY_FN` | `action-list` / `table` | Extra key handler callback name (empty → none) |
| `_SHELLFRAME_APP_HINT` | `action-list` / `table` | Footer hint text (empty → built-in default) |
| `_SHELLFRAME_APP_QUESTION` | `confirm` | Question text |
| `_SHELLFRAME_APP_TITLE` | `alert` | Title text |
| `_SHELLFRAME_APP_DETAILS` | `confirm` + `alert` | Array of detail lines |
| `SHELLFRAME_TBL_HEADERS[@]` | `table` | Column header labels |
| `SHELLFRAME_TBL_COL_WIDTHS[@]` | `table` | Visible width per column |
| `SHELLFRAME_TBL_PAGE_TITLE` | `table` | Header bar text |
| `SHELLFRAME_TBL_PAGE_H1` | `table` | H1 content title |
| `SHELLFRAME_TBL_PAGE_FOOTER` | `table` | Footer bar text (pinned to terminal bottom) |
| `SHELLFRAME_TBL_PANEL_FN` | `table` | Right-panel callback (50/50 split) |
| `SHELLFRAME_TBL_BELOW_FN` | `table` | Below-hint callback |
| `SHELLFRAME_TBL_BELOW_ROWS` | `table` | Content rows reserved for below-hint area |

> **Note:** `SHELLFRAME_TBL_SCROLL` is intentionally NOT reset by `shellframe_app` between
> screens so scroll position is preserved across FSM transitions. Reset it to `0` in your
> `render()` hook when loading new data.

### Application context

Application-level state shared between screens (e.g. a pending-changes list,
results from an apply step) is not managed by `shellframe_app`. Use your own
module-level globals, by convention prefixed with your app name:

```bash
_MYAPP_PENDING=()   # populated by ROOT_confirm, consumed by CONFIRM_render
_MYAPP_RESULTS=()   # populated by CONFIRM_yes, consumed by RESULT_render
```

### Example

```bash
# Module-level context
_MYAPP_RESULTS=()

_myapp_ROOT_type()    { printf 'action-list'; }
_myapp_ROOT_render()  {
    SHELLFRAME_AL_LABELS=("task-a" "task-b")
    SHELLFRAME_AL_ACTIONS=("nothing run" "nothing run")
    SHELLFRAME_AL_IDX=(0 0)
    _SHELLFRAME_APP_HINT="Space cycle  Enter confirm  q quit"
}
_myapp_ROOT_confirm() {
    # check SHELLFRAME_AL_IDX for selections; if nothing selected, go back
    _SHELLFRAME_APP_NEXT="CONFIRM"
}
_myapp_ROOT_quit() { _SHELLFRAME_APP_NEXT="__QUIT__"; }

_myapp_CONFIRM_type()    { printf 'confirm'; }
_myapp_CONFIRM_render()  { _SHELLFRAME_APP_QUESTION="Run selected tasks?"; }
_myapp_CONFIRM_yes()     { _MYAPP_RESULTS=("task-a: ok" "task-b: ok"); _SHELLFRAME_APP_NEXT="RESULT"; }
_myapp_CONFIRM_no()      { _SHELLFRAME_APP_NEXT="ROOT"; }

_myapp_RESULT_type()     { printf 'alert'; }
_myapp_RESULT_render()   { _SHELLFRAME_APP_TITLE="Done"; _SHELLFRAME_APP_DETAILS=("${_MYAPP_RESULTS[@]}"); }
_myapp_RESULT_dismiss()  { _SHELLFRAME_APP_NEXT="ROOT"; }

shellframe_app "_myapp" "ROOT"
```

For a full real-world example see [`macbin/scripts`](https://github.com/fissible/macbin)
— a three-screen app (action list → confirm → result alert) that manages
symlinks in `~/bin`.
