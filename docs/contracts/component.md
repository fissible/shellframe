# Component Contract

> Phase 1 spec — no deps. Defines the conventions every new shellframe
> component must follow. Read this before implementing anything in Phase 3+.

---

## Two widget tiers

shellframe has two generations of widgets. Both are valid; they serve different
purposes.

| Tier | Examples | Owns its loop? | Region-aware? |
|------|----------|----------------|---------------|
| **v1 — standalone** | `action-list`, `table`, `confirm`, `alert` | Yes — enters raw mode, runs its own `read` loop, exits raw mode | No — takes the whole terminal |
| **v2 — composable** | `text`, `box`, `scroll`, `list`, `input-field`, `tab-bar`, `modal` | No — app shell owns the loop | Yes — renders within a given `(top, left, width, height)` region |

Phase 3 and 4 build **v2 composable components**. v1 widgets remain as-is;
they are not refactored.

---

## Composable component API

Every v2 component lives in `src/widgets/<name>.sh` and exposes:

### 1. Input globals

Set by the caller (or app shell's render hook) before calling any component
function. Named `SHELLFRAME_<NAME>_*` where `<NAME>` is the component's
uppercase identifier (e.g. `SHELLFRAME_LIST_*`, `SHELLFRAME_INPUT_*`).

These are the component's configuration and data. The component reads them;
it never writes them.

### 2. Output globals

Set by the component after user interaction completes. Named
`SHELLFRAME_<NAME>_*` with suffixes like `_VALUE`, `_SELECTED`, `_SCROLL`.

These are readable by the caller. They must persist after the component
function returns.

### 3. `shellframe_<name>_render top left width height`

Draw the component within the given terminal region:

| Param | Type | Description |
|-------|------|-------------|
| `top` | int | 1-based row of the region's top-left corner |
| `left` | int | 1-based column of the region's top-left corner |
| `width` | int | Width of the region in terminal columns |
| `height` | int | Height of the region in terminal rows |

**Rules:**
- All output goes to `/dev/tty` (stdout may be a pipe — never assume it is the terminal).
- Rendering must stay within the given region. Do not move the cursor outside `[top, top+height-1]` × `[left, left+width-1]`.
- Use absolute ANSI cursor positioning (`\033[R;CH`) rather than relative movement so renders compose cleanly.
- Erase each row before drawing it: `printf '\033[%d;%dH\033[2K'` (erase-to-end-of-line is fine if the component owns the full row width).
- Leave the cursor in a predictable position after render (convention: last row of the region, column `left`).

### 4. `shellframe_<name>_on_key key`

Called by the app shell's input dispatcher when this component has focus and a
key is pressed.

**Return codes:**

| rc | Meaning |
|----|---------|
| `0` | Key handled — app shell redraws the component |
| `1` | Key not handled — app shell offers the key to the next handler |
| `2` | Quit / dismiss requested — app shell routes the appropriate event |

The function must not produce any output (stdout or stderr). Side effects go
to the component's own globals, which `render` will pick up on the next draw.

### 5. `shellframe_<name>_on_focus focused`

Called by the app shell when this component's focus state changes.

| `focused` | Meaning |
|-----------|---------|
| `1` | Component gained focus |
| `0` | Component lost focus |

Used to toggle a focus indicator (e.g. highlighted border). The component
should not redraw itself here — the app shell calls `render` after
`on_focus`.

This function is **optional**. Omit it for components that have no visible
focus state (e.g. read-only text).

### 6. `shellframe_<name>_size` *(optional)*

Print four space-separated integers to stdout:

```
min_width min_height preferred_width preferred_height
```

Used by the layout system to allocate space. `0` means "no preference" for
that dimension. If this function is absent, the layout system treats all four
values as `0` (no constraints).

---

## Invariants

Every v2 component must satisfy these invariants at all times:

1. **No side effects on source.** Sourcing `src/widgets/<name>.sh` must not
   execute any code, allocate any fds, or modify terminal state.

2. **UI to `/dev/tty`.** All screen output uses `printf ... >/dev/tty` or
   redirects stdout to `/dev/tty`. Never assume fd 1 reaches the terminal.

3. **Pure render.** `render` must be idempotent — calling it twice with the
   same globals must produce identical screen output.

4. **No raw mode management.** v2 components never call `shellframe_raw_enter`,
   `shellframe_raw_exit`, `shellframe_screen_enter`, or `shellframe_screen_exit`.
   The app shell owns these.

5. **No input loop.** v2 components never call `shellframe_read_key`. Input is
   delivered via `on_key`.

6. **`local` for all internals.** All variables private to a function must be
   declared with `local`. No caller-scope pollution.

7. **Exit codes are exit codes.** A function's return value communicates status
   (see `on_key` table above). Data goes to globals, not stdout — except for
   `size`, which is intentionally pure/subshell-safe.

---

## Global naming conventions

| Prefix | Used for |
|--------|----------|
| `SHELLFRAME_<NAME>_*` | Public input/output globals for component `<NAME>` |
| `_shellframe_<name>_*` | Internal helper functions (not callable by consumers) |

No other globals may be introduced by a component. If two components need
shared state (e.g. a list and its scroll container), one owns the globals and
the other reads them.

---

## Exit code semantics (widget return values)

When a v2 component is used standalone (rare, but supported for testing):

| Code | Meaning |
|------|---------|
| `0` | User confirmed / accepted |
| `1` | User cancelled / quit |

Within the app shell the return code drives the FSM event — see
`docs/contracts/layout.md` and `src/app.sh`.

---

## Checklist for new components

Before marking a Phase 3/4 issue closed, verify:

- [ ] Lives in `src/widgets/<name>.sh`
- [ ] All public globals prefixed `SHELLFRAME_<NAME>_`
- [ ] `shellframe_<name>_render top left width height` implemented
- [ ] `shellframe_<name>_on_key key` implemented (returns 0/1/2)
- [ ] `shellframe_<name>_on_focus focused` implemented (or explicitly omitted with a comment)
- [ ] `shellframe_<name>_size` implemented (or explicitly omitted)
- [ ] No `shellframe_raw_enter` / `shellframe_screen_enter` calls
- [ ] No `shellframe_read_key` calls
- [ ] All internal variables declared `local`
- [ ] Unit test in `tests/unit/test-<name>.sh`
- [ ] Docker matrix passes (`bash tests/docker/run-matrix.sh`)
