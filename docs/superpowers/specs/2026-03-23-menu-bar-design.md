# Menu Bar Widget — Design Spec
_Date: 2026-03-23 | Issue: shellframe#22 | Effort: L_

## Overview

A composable v2 menu bar widget (`src/widgets/menu-bar.sh`) providing a horizontal label
bar, dropdown panels, and one level of submenu nesting. Follows the established v2 contract
(`init / render / on_key / on_focus / size`) and shellframe LEGO composability rules.

---

## Design Principles

### Double border = active container

The double border style (`╔═╗║╚╝`) is reserved for "this container is currently active".
Dropdown and submenu panels always use double borders. A widget MAY use a double border for
stylistic reasons, but MUST NOT apply active/focus colors unless it actually has keyboard
focus.

### Active colors = keyboard input is here

The theme's active/focus colors (reverse video, `SHELLFRAME_MENUBAR_ACTIVE_COLOR`) are
applied only when the MBW has keyboard focus. An unfocused menu bar renders with no
highlights — this signals to the user that no input is being accepted.

### These two can coincide but must never be conflated

A focused dropdown item has both the double-border panel AND active cursor highlight.
A stylistically double-bordered element without focus must not use active colors.

---

## Data Model

Menu data is declared by the caller as bash arrays. The widget reads them by convention.

```bash
# Top-level label order
SHELLFRAME_MENU_NAMES=("File" "Edit" "View")

# Per-menu item arrays — variable name = uppercased label, spaces → underscores
SHELLFRAME_MENU_FILE=("Open" "Save" "---" "@RECENT:Recent Files" "---" "Quit")
SHELLFRAME_MENU_EDIT=("Undo" "Redo" "---" "Cut" "Copy" "Paste")
SHELLFRAME_MENU_VIEW=("Zoom In" "Zoom Out" "---" "Full Screen")

# Submenu arrays — variable name referenced by @VARNAME sigil
SHELLFRAME_MENU_RECENT=("demo.db" "work.db" "archive.db")
```

### Item conventions

| Item value | Meaning |
|---|---|
| Any plain string | Selectable leaf item |
| `---` | Separator — drawn as a horizontal rule, never reachable by cursor |
| `@VARNAME:Display Label` | Submenu item — opens `SHELLFRAME_MENU_VARNAME` on Enter or Right |

### Result

On selection, `SHELLFRAME_MENUBAR_RESULT` is set to the full `|`-delimited label path.
Empty string means the widget was dismissed (Esc from BAR state).

```
File|Recent Files|demo.db   ← submenu selection
Edit|Copy                   ← leaf selection
(empty string)              ← dismissed with Esc
```

---

## State Machine

Four states. `Esc` always moves one level up.

### States

| State | Description |
|---|---|
| `idle` | MBW has no focus. Bar not rendered or rendered dim. No active colors. |
| `bar` | MBW focused. Bar visible. Active label highlighted. No dropdown open. |
| `dropdown` | Bar + open dropdown panel (double border) below active label. |
| `submenu` | Bar + dropdown (▶ item highlighted) + submenu panel (double border) to the right. |

### Transitions

**From IDLE:**
- `on_focus 1` → BAR (bar appears, first label highlighted)

**From BAR:**
- `Left` / `Right` → BAR (move active label; wraps around)
- `Enter` / `Down` → DROPDOWN (open dropdown; cursor = first selectable item)
- `Esc` → IDLE, set `SHELLFRAME_MENUBAR_RESULT=""`, return 2 (widget done; caller reads empty RESULT as dismiss)
- `on_focus 0` → IDLE

**From DROPDOWN:**
- `Up` / `Down` → DROPDOWN (move cursor; separators skipped automatically)
- `Left` / `Right` → DROPDOWN (move to adjacent top-level label, reopen that dropdown; cursor resets to first selectable item in new menu)
- `Enter` or `Right` on `▶` item → SUBMENU (open submenu; cursor = first selectable item)
- `Enter` on leaf item → IDLE, set RESULT to full path, return 2
- `Esc` → BAR (close dropdown; bar cursor unchanged; dropdown cursor reset)
- `on_focus 0` → IDLE

**From SUBMENU:**
- `Up` / `Down` → SUBMENU (move cursor within submenu)
- `Enter` → IDLE, set RESULT = `"Menu|Item|Subitem"`, return 2
- `Left` / `Esc` → DROPDOWN (close submenu; dropdown cursor restored to the `▶` item)
- `on_focus 0` → IDLE

### Return codes from `on_key`

| Code | Meaning |
|---|---|
| `0` | Key handled; app shell should redraw |
| `1` | Key not handled; pass to next handler (unrecognised key only) |
| `2` | Widget done; read `SHELLFRAME_MENUBAR_RESULT` (empty = dismissed, non-empty = selection) |

Return code `1` means only "this key was unrecognised." It is never used to signal
focus release. Focus release is signalled by return code `2` with an empty RESULT.
This is consistent with the modal widget pattern.

---

## Rendering (Approach A — Self-Contained Overdraw)

`shellframe_menubar_render top left width height` draws everything in a single call:

1. **Bar row** — one row at `top`. Each label rendered as ` Label ` with a single space
   padding. Active label (state ≠ idle) uses reverse video. Fills remaining width with spaces.

2. **Dropdown panel** (state = dropdown or submenu) — double-border panel drawn at
   `(top+1, label_col)` where `label_col` is the terminal column of the active label.
   Width = longest item + 4 (2 border + 2 padding). Items rendered inside; cursor row uses
   reverse video; `---` items drawn as `║ ══════════════ ║`; `▶` items show arrow on right.

3. **Submenu panel** (state = submenu) — drawn at:
   ```
   submenu_top  = dropdown_top + 1 + cursor_item_index
   submenu_left = dropdown_left + dropdown_width
   ```
   where `cursor_item_index` is the 0-based index of the `▶` item within the dropdown's
   item array (accounting for the top border row at offset 1). Width = longest submenu
   item + 4. Cursor row uses reverse video.

### Absolute terminal positioning

Dropdown and submenu panels use absolute terminal cursor positioning (`\033[row;colH`) —
they are NOT clipped to the widget's allocated region. This is the same approach used by
`modal.sh`. The layout engine allocates 1 row for the bar; overlay panels draw freely
below and to the right of that row at their computed absolute coordinates.

### Render teardown contract

`render` is responsible for clearing its own overlay area. When the state transitions
from DROPDOWN→BAR or SUBMENU→DROPDOWN, `render` blanks the cells of the panel that is
closing before drawing the new state. This is done by writing spaces over the old panel
region at the start of each `render` call, based on the previous panel dimensions stored
in `_SHELLFRAME_MB_${ctx}_PREV_DD_*` and `_SHELLFRAME_MB_${ctx}_PREV_SM_*` internal vars.

**Init lifecycle:** `shellframe_menubar_init` zeroes all `PREV_*` vars. A zero (or unset)
prev-dim value means "nothing to erase" — no blank pass is attempted, preventing stray
writes to terminal row 0 on the first render call.

The app shell does NOT need to do a full-screen repaint on menu state transitions.

### Mouse hit-test compatibility (Phase 7)

During `render`, the widget will register hit boxes for all visible interactive elements
using the planned `shellframe_widget_register name row col width height` API. A future
`shellframe_menubar_on_mouse row col button` handler will resolve clicks internally.

---

## API Surface

### Input globals

```bash
SHELLFRAME_MENU_NAMES=()            # top-level label order (caller sets)
SHELLFRAME_MENUBAR_CTX="menubar"    # context name for selection state
SHELLFRAME_MENUBAR_FOCUSED=0        # 0 | 1
SHELLFRAME_MENUBAR_FOCUSABLE=1      # 1 (default) | 0
SHELLFRAME_MENUBAR_ACTIVE_COLOR=""  # ANSI escape for double-border + active label color
                                    # default: SHELLFRAME_BOLD
```

### Output globals

```bash
SHELLFRAME_MENUBAR_RESULT=""        # set on return 2; pipe-delimited path or empty (dismiss)
```

### Public functions

```bash
shellframe_menubar_init [ctx]
  # Initialise selection contexts for bar, dropdown, and submenu.
  # Must be called once after SHELLFRAME_MENU_NAMES is set.

shellframe_menubar_render top left width height
  # Draw bar row + any open overlay panels. Blanks closed panels. Output to fd 3.

shellframe_menubar_on_key key
  # Drive the state machine. Returns 0, 1, or 2.

shellframe_menubar_on_focus focused
  # 1 → enter BAR state (sets SHELLFRAME_MENUBAR_FOCUSED=1, state=bar).
  # 0 → collapse to IDLE (sets state=idle, clears open panels on next render).

shellframe_menubar_size
  # Prints "1 1 0 1"
  # Format: min_width min_height pref_width pref_height
  # 0 = unconstrained (same sentinel used by all v2 widgets — e.g. panel_size prints "2 2 0 0").
  # pref_height=1: the bar row is always 1 row; dropdown/submenu are overlays rendered at
  # absolute terminal coordinates, independent of the allocated region (see Rendering section).

shellframe_menubar_open name
  # Programmatically focus the bar and open the named top-level menu.
  # Hotkey plug-in seam: e.g. shellframe_menubar_open "File"
  # Delegates to on_focus 1 first (so all on_focus initialisation runs), then sets
  # state=dropdown and bar_idx to the index of `name` in SHELLFRAME_MENU_NAMES.
  # If `name` is not found in SHELLFRAME_MENU_NAMES, returns 1 with no state change
  # (focus is NOT acquired and no dropdown opens).
```

### Internal state (context-keyed, not for callers)

```bash
_SHELLFRAME_MB_${ctx}_STATE          # idle | bar | dropdown | submenu
_SHELLFRAME_MB_${ctx}_BAR_IDX       # active bar label index (0-based)
_SHELLFRAME_MB_${ctx}_PREV_DD_TOP   # previous dropdown panel top row (for teardown)
_SHELLFRAME_MB_${ctx}_PREV_DD_LEFT  # previous dropdown panel left col
_SHELLFRAME_MB_${ctx}_PREV_DD_W     # previous dropdown panel width
_SHELLFRAME_MB_${ctx}_PREV_DD_H     # previous dropdown panel height
_SHELLFRAME_MB_${ctx}_PREV_SM_TOP   # previous submenu panel top row
_SHELLFRAME_MB_${ctx}_PREV_SM_LEFT  # previous submenu panel left col
_SHELLFRAME_MB_${ctx}_PREV_SM_W     # previous submenu panel width
_SHELLFRAME_MB_${ctx}_PREV_SM_H     # previous submenu panel height
# Selection contexts via selection.sh:
#   mb_${ctx}_dd   — dropdown item cursor
#   mb_${ctx}_sm   — submenu item cursor
```

---

## Visual & Theming Rules

| Element | Style |
|---|---|
| Bar label (active menu, MBW focused) | Reverse video |
| Bar label (active menu, MBW unfocused) | No highlight |
| Dropdown / submenu panel border | Double border + `SHELLFRAME_MENUBAR_ACTIVE_COLOR` |
| Dropdown / submenu cursor row (focused) | Reverse video |
| `▶` item when submenu is open | Dimmed (cursor has moved into submenu) |
| Separator `---` | `║ ══════════ ║` — not selectable |

`SHELLFRAME_MENUBAR_ACTIVE_COLOR` defaults to `SHELLFRAME_BOLD`. Callers override it to
make double borders visually distinct (brighter, different color) from surrounding content.
This is the hook point for a future global theme system.

---

## Bash 3.2 Compatibility

- No `{varname}` fd allocation — use explicit fd numbers
- No `read -t` with decimals — integer timeouts only
- No `<<<` herestrings where 3.2 behaviour differs
- Guard empty array expansions: `"${arr[@]+"${arr[@]}"}"` under `set -u`
- `$'\n'` not `"\n"` in comparisons
- `${!varname}` works for scalar indirect lookup in bash 3.2; do NOT use `${!varname[@]}`
  for indirect array expansion — that form is not available in 3.2
- Submenu array access uses `eval` with a sanitised name:
  ```bash
  # _sigil_name is validated against [A-Z0-9_]+ before this point
  eval "_sm_items=(\"\${SHELLFRAME_MENU_${_sigil_name}[@]}\")"
  ```

> **Security note:** `@VARNAME` values are validated against `^[A-Z0-9_]+$` before any
> `eval`. Only arrays in the `SHELLFRAME_MENU_*` namespace are ever expanded this way.

---

## Dependencies

| Module | Used for |
|---|---|
| `src/clip.sh` | Label clipping with `shellframe_str_clip_ellipsis` |
| `src/selection.sh` | Cursor tracking for dropdown and submenu (`shellframe_sel_*`) |
| `src/panel.sh` | Double-border panel frames for dropdown and submenu |
| `src/draw.sh` | Cursor positioning |
| `src/input.sh` | Key constants (`SHELLFRAME_KEY_*`) |

---

## Deliverables

| File | Description |
|---|---|
| `src/widgets/menu-bar.sh` | Widget implementation |
| `tests/unit/test-menu-bar.sh` | Unit tests (state machine, no PTY) |
| `tests/integration/test-menu-bar.sh` | PTY-driven integration tests |
| `examples/menu-bar.sh` | Standalone demo (3 menus, one submenu) |
| `docs/showcase.md` | New entry with ASCII art + code snippet |

---

## Test Plan

### Unit tests

- `init` — selection contexts created for bar, dropdown, submenu
- BAR: Left/Right wraps, Enter→DROPDOWN, Esc → rc=2 with empty RESULT
- DROPDOWN: Up/Down skip separators; Enter on leaf → RESULT set + rc=2
- DROPDOWN: Enter/Right on `▶` item → SUBMENU state
- DROPDOWN: Left/Right moves bar index, cursor resets to first selectable in new menu
- SUBMENU: Up/Down navigate; Enter → full path RESULT + rc=2
- SUBMENU: Left/Esc → DROPDOWN, dropdown cursor restored to `▶` item
- `on_focus 0` from any state → IDLE
- `shellframe_menubar_open "File"` → state=dropdown, bar_idx=0, focused=1
- `@VARNAME:Label` parsing — sigil detected, VARNAME extracted and validated
- Separator skipping — cursor never lands on `---` item
- rc=1 is only returned for unrecognised keys, never for state transitions

### Integration tests (PTY)

- Tab into bar → Enter opens dropdown → Down×2 → Enter → correct RESULT
- Navigate to submenu: Down to `▶` → Right → Down → Enter → `"File|Recent Files|demo.db"`
- Esc from submenu → dropdown; Esc again → bar; Esc again → rc=2 empty RESULT
- `shellframe_menubar_open "Edit"` → Edit dropdown opens directly
