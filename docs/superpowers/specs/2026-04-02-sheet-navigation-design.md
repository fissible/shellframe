# Sheet Navigation Primitive — Design Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shell-integrated sheet navigation primitive to shellframe — a partial overlay that sits above the current screen, shows a frozen back strip of the content beneath, and supports internal screen transitions (wizard pattern).

**Architecture:** New `src/sheet.sh` module holds all sheet state and rendering. `src/shell.sh` gains two small delegation checks (draw cycle + key dispatch). Hook convention is identical to `shellframe_shell` screens. No stacking for v1 (deferred).

**Tech Stack:** bash 3.2+, shellframe framebuffer API (`shellframe_fb_*`, `shellframe_screen_flush`), existing shell.sh focus model.

---

## Overview

A **sheet** is a navigation layer that overlays the current shellframe_shell screen. It:

- Shows 1 frozen, dimmed row of the underlying screen at the top (the "back strip")
- Renders its own content from row 2 downward, with configurable height
- Shows frozen, dimmed underlying content below the sheet when height < full screen
- Supports internal screen transitions (e.g. wizard steps) with per-step height
- Dismisses on Esc, Up from topmost focusable region, or explicit `shellframe_sheet_pop`

Stacking (sheet-on-sheet) is deferred. v1 supports exactly one active sheet at a time.

---

## State globals (`src/sheet.sh`)

```bash
_SHELLFRAME_SHEET_ACTIVE=0          # 0|1 — whether a sheet is currently open
_SHELLFRAME_SHEET_PREFIX=""         # consumer prefix (e.g. "_myapp")
_SHELLFRAME_SHEET_SCREEN=""         # current screen within the sheet (e.g. "OPEN_DB")
_SHELLFRAME_SHEET_NEXT=""           # next screen name; "__POP__" to dismiss
_SHELLFRAME_SHEET_FROZEN_ROWS=()    # full-screen framebuffer snapshot taken at push time
SHELLFRAME_SHEET_HEIGHT=0           # consumer sets in render hook; 0 = fill to bottom
SHELLFRAME_SHEET_WIDTH=0            # set by sheet draw code before calling render hook; read-only for consumers
```

---

## Public API

```bash
# Push a sheet (call from a shellframe_shell event handler)
shellframe_sheet_push prefix screen
#   prefix  — hook prefix, e.g. "_myapp"
#   screen  — initial screen name, e.g. "OPEN_DB"

# Pop the sheet and return to parent shell (thin wrapper: sets _SHELLFRAME_SHEET_NEXT="__POP__")
shellframe_sheet_pop

# Query whether a sheet is active (returns 0=true, 1=false)
shellframe_sheet_active
```

---

## Hook convention

Sheet screens use the **identical hook convention** as `shellframe_shell` screens.
Consumers already know this pattern.

**Region coordinates are sheet-relative.** Row 1 = first row of sheet content (screen
row 2, immediately below the back strip). The sheet draw code offsets all region rows
by `_sheet_top - 1` before dispatching renders and key events. Consumers never need to
know the back strip height.

```bash
# Layout hook — called once per draw cycle
# Set SHELLFRAME_SHEET_HEIGHT here (optional). Register regions with shellframe_shell_region.
# Row coordinates are sheet-relative: row 1 = first content row of the sheet.
_myapp_OPEN_DB_render() {
    SHELLFRAME_SHEET_HEIGHT=7
    shellframe_shell_region body   1 1 "$SHELLFRAME_SHEET_WIDTH" 6
    shellframe_shell_region footer 7 1 "$SHELLFRAME_SHEET_WIDTH" 1 nofocus
}

# Region render/key hooks — same signature as shellframe_shell
_myapp_OPEN_DB_body_render()   { shellframe_form_render ...; }
_myapp_OPEN_DB_body_on_key()   { shellframe_form_on_key ...; }
_myapp_OPEN_DB_footer_render() { shellframe_fb_print ...; }

# Quit hook — called on Esc or back-strip dismissal
_myapp_OPEN_DB_quit() { shellframe_sheet_pop; }

# Internal transition to next step (wizard)
_myapp_OPEN_DB_body_action() { _SHELLFRAME_SHEET_NEXT="CONFIRM"; }
```

**Key difference from `shellframe_shell`:** Sheet event handlers set `_SHELLFRAME_SHEET_NEXT`
(not `_SHELLFRAME_SHELL_NEXT`) for internal transitions. This isolates sheet navigation
from the parent shell — an accidental write to `_SHELLFRAME_SHELL_NEXT` while a sheet
is open would otherwise navigate the parent screen.

---

## Render cycle

When `_SHELLFRAME_SHEET_ACTIVE=1`, `shellframe_sheet_draw` is called instead of the
normal shell draw cycle. It works as follows:

### At push time
Snapshot the full framebuffer into `_SHELLFRAME_SHEET_FROZEN_ROWS`:
```bash
for (( _r=1; _r<=_rows; _r++ )); do
    _SHELLFRAME_SHEET_FROZEN_ROWS[$_r]="${_SF_ROW_CURR[$_r]:-}"
done
```

### Each draw frame

1. `shellframe_fb_frame_start rows cols` — full screen (not just sheet rows)
2. Reset `SHELLFRAME_SHEET_HEIGHT=0`
3. Call `${_SHELLFRAME_SHEET_PREFIX}_${_SHELLFRAME_SHEET_SCREEN}_render` — consumer may set `SHELLFRAME_SHEET_HEIGHT` and registers regions
4. Resolve sheet bounds:
   - `_sheet_top=2`
   - `_sheet_h = SHELLFRAME_SHEET_HEIGHT > 0 ? SHELLFRAME_SHEET_HEIGHT : (rows - 1)`
   - `_sheet_bottom = 1 + _sheet_h`
5. Write frozen rows into framebuffer:
   - Row 1 (back strip): `_SHELLFRAME_SHEET_FROZEN_ROWS[1]` wrapped in `\033[2m…\033[22m`
   - Rows `_sheet_bottom+1` to `rows`: corresponding frozen rows, also dimmed
6. Render sheet regions (rows 2 to `_sheet_bottom`) via the normal `shellframe_shell_region` dispatch
7. `shellframe_screen_flush` — diffs full screen including frozen rows; handles sheet shrink automatically

### Why frozen rows go into the framebuffer (not direct to terminal)

Writing frozen rows into `_SF_ROW_CURR` ensures the dirty-diff in `shellframe_screen_flush`
patches uncovered rows correctly when the sheet shrinks. If step 1 is 8 rows tall and
step 2 is 6 rows, rows 7–8 transition from sheet content to frozen parent content.
The diff detects the change and emits the correct terminal update without any special
erasure logic.

---

## Internal screen transitions

```bash
# From a region action handler — advance to next wizard step
_myapp_STEP1_next_action() {
    _SHELLFRAME_SHEET_NEXT="STEP2"
}

_myapp_STEP2_render() {
    SHELLFRAME_SHEET_HEIGHT=8    # one row taller than step 1
    shellframe_shell_region body   1 1 "$_sheet_w" 7
    shellframe_shell_region footer 8 1 "$_sheet_w" 1 nofocus
}

_myapp_STEP2_quit() { shellframe_sheet_pop; }
```

When `_SHELLFRAME_SHEET_NEXT` is set (and not `"__POP__"`), the sheet draw cycle:
1. Updates `_SHELLFRAME_SHEET_SCREEN` to the new screen name
2. Clears `_SHELLFRAME_SHEET_NEXT`
3. Resets the focus ring (calls `_shellframe_shell_focus_init`)
4. Re-renders with the new screen's hooks

Height changes take effect immediately. Newly uncovered rows get the frozen parent
content via the snapshot mechanism described above.

---

## Dismissal

Three paths to pop the sheet:

| Trigger | Mechanism |
|---------|-----------|
| `Esc` | `shellframe_sheet_on_key` intercepts `$'\033'` before region dispatch, calls quit hook |
| Up from topmost region | Sheet key handler dispatches Up to the focused region first; if the region returns 1 (unhandled) AND focus is at ring index 0, sheet calls quit hook |
| Explicit `shellframe_sheet_pop` | Consumer calls from any action handler |

`shellframe_sheet_pop` sets `_SHELLFRAME_SHEET_NEXT="__POP__"`. On the next draw cycle
the sheet module clears all state, restores the full framebuffer from
`_SHELLFRAME_SHEET_FROZEN_ROWS`, and returns control to the parent shell loop.

---

## shell.sh integration (minimal changes)

Two additions to `src/shell.sh`, both guarded by `_SHELLFRAME_SHEET_ACTIVE`:

```bash
# In _shellframe_shell_draw_if_dirty (draw path):
if (( _SHELLFRAME_SHEET_ACTIVE )); then
    shellframe_sheet_draw "$_rows" "$_cols"
    return
fi
# ... existing draw logic ...

# In the key dispatch loop (key path):
if (( _SHELLFRAME_SHEET_ACTIVE )); then
    shellframe_sheet_on_key "$_key"
    continue
fi
# ... existing key dispatch ...
```

No other changes to shell.sh.

---

## Files

| File | Change |
|------|--------|
| `src/sheet.sh` | New — all sheet state, push/pop/draw/key |
| `src/shell.sh` | Modify — two delegation checks (draw + key) |
| `shellframe.sh` | Modify — source sheet.sh after shell.sh |
| `tests/unit/test-sheet.sh` | New — unit tests (no PTY) |
| `tests/integration/test-sheet.sh` | New — PTY-driven tests |
| `examples/sheet.sh` | New — two-step wizard example |
| `docs/showcase.md` | Modify — add sheet section |

---

## Tests

### Unit (`tests/unit/test-sheet.sh`)

- `shellframe_sheet_push` sets `_SHELLFRAME_SHEET_ACTIVE=1`, captures frozen rows, sets prefix/screen
- `shellframe_sheet_pop` clears all state, sets `_SHELLFRAME_SHEET_ACTIVE=0`
- `shellframe_sheet_active` returns correct exit code
- Height 0 resolves to `rows - 1`; explicit value is respected
- `_SHELLFRAME_SHEET_NEXT="STEP2"` updates screen, resets focus
- `_SHELLFRAME_SHEET_NEXT="__POP__"` triggers pop
- Frozen rows written into framebuffer at row 1 and below sheet boundary
- Sheet shrink: rows newly below sheet boundary get frozen content, not stale sheet content

### Integration (`tests/integration/test-sheet.sh`)

- Push sheet from parent shell screen — sheet border visible, back strip shows dimmed parent
- Type in a form field — value updates correctly
- Internal transition (`_SHELLFRAME_SHEET_NEXT="STEP2"`) — new screen renders, height change visible, uncovered rows show frozen parent
- Esc dismisses — full parent screen restored
- Up from topmost field dismisses — same result

### Example (`examples/sheet.sh`)

Two-step wizard:
- Step 1: Name + Email fields + `[Next →]` button (height = 6)
- Step 2: Address + City + State + Zip fields + `[Submit]` / `[← Back]` buttons (height = 8)
- Demonstrates: height change on transition, back navigation via Back button, Esc dismissal
