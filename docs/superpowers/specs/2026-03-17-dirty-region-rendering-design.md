# Dirty-Region Rendering — Stage 1 Design

**Date:** 2026-03-17
**Status:** Approved
**Roadmap ref:** `src/screen.sh` — Stage 1 (Phase 7 task B)

---

## Problem

Every handled keypress triggers `shellframe_screen_clear` followed by a full redraw of
the entire terminal. On cursor movement (the most common interaction), this causes visible
flicker: the screen blanks to black for a frame before content is repainted.

---

## Goal

Eliminate flicker on cursor movement and button toggling. Preserve the full-redraw path
for cases that genuinely need it (first draw, resize, data change). No API break: render
functions continue to write to `/dev/tty`; callers see no change.

---

## Scope

### In scope

| Widget | Reason |
|---|---|
| `src/widgets/action-list.sh` | Cursor movement is the hot path; full clear on every ↑/↓ |
| `src/widgets/table.sh` | Same; page chrome + optional panel make each redraw expensive |
| `src/widgets/confirm.sh` | Redraw loop for yes↔no button toggle |

### Out of scope

| Widget | Reason |
|---|---|
| `src/widgets/alert.sh` | Renders once, no redraw loop — nothing to optimize |
| `src/widgets/list.sh`, `src/widgets/modal.sh` | v2 composable; don't own the terminal or call `screen_clear`; dirty tracking belongs in their parent container |
| `src/widgets/input-field.sh`, `src/widgets/editor.sh`, `src/widgets/grid.sh`, `src/widgets/tab-bar.sh` | Composable/primitive; no screen lifecycle |
| Stage 2 (framebuffer diff) | Separate ticket; this work is its prerequisite |

---

## Architecture

### Dirty integer

Each in-scope widget's event loop gains a `local` integer `_dirty`. It is never
exported as a global and is not visible to callers.

| Level | Name | Meaning | Action |
|---|---|---|---|
| `2` | FULL | Full repaint required | `shellframe_screen_clear` + redraw everything |
| `1` | PARTIAL | Only changed region needs repainting | Skip `screen_clear`; overwrite changed region in-place using absolute ANSI positioning + `\033[K` |
| `0` | NONE | Nothing changed | Skip draw entirely |

### How `_dirty` is set

| Event | Level |
|---|---|
| First draw on screen entry | `2` |
| Terminal resize detected | `2` |
| Data change (scroll page, new items) | `2` |
| Extra key handler returned "handled" (`_xrc == 0`) | `2` (conservative; unknown what changed) |
| Cursor up / down | `1` |
| Button toggle (confirm yes↔no) | `1` |
| Unrecognized key | `0` |

### Resize detection

At the top of each draw call, read current terminal dimensions via `stty size` and
compare to `_prev_rows` / `_prev_cols` locals (initialized to `0 0`). If either
dimension changed, force `_dirty=2` before branching.

### The core win

Flicker originates from `screen_clear` blanking the terminal to black between writes.
Level `1` skips `screen_clear` entirely and overwrites old content with new content
using `\033[row;colH` absolute cursor positioning. The terminal never goes dark; the
user sees an instant in-place update.

---

## Widget-by-widget partial update strategy

### `action-list.sh`

Track `_prev_sel` (value of `SHELLFRAME_AL_SELECTED` before key handling).

On `_dirty=1`:
1. Move cursor to `_prev_sel` row; call row renderer for that row (renders without highlight).
2. Move cursor to `SHELLFRAME_AL_SELECTED` row; call row renderer for that row (renders with highlight).
3. Footer is static during navigation — skip it.

The existing row renderer (`_al_default_draw_row` or the caller-supplied `_draw_row_fn`)
is reused for both full and partial draws; no new rendering function is needed.

### `table.sh`

Two sub-cases, both still using `_dirty=1`:

**No panel** (`SHELLFRAME_TBL_PANEL_FN` empty):
- Same as action-list: redraw old and new cursor rows only.
- Page chrome (header bar, h1, column headers, footer bar, separators) is static during
  navigation; skip it entirely.

**With panel** (`SHELLFRAME_TBL_PANEL_FN` set):
- Cursor movement changes both the cursor rows AND the panel content.
- Still `_dirty=1` (skip `screen_clear`); overwrite the two cursor rows AND the full
  panel region in-place.
- Chrome is still static; still skipped.
- Result: no screen blank, panel repaints instantly, chrome never flickers.

### `confirm.sh`

On button toggle (left/right arrow):
- Only the button row changes. Set `_dirty=1`.
- Redraw just the button row at its absolute terminal position.
- Question text and detail lines are static; skip them.

---

## API contract

- No new public functions.
- No new exported globals.
- Render functions continue to write directly to `/dev/tty`.
- Return codes and all `SHELLFRAME_*` input/output globals are unchanged.
- Callers of `shellframe_action_list`, `shellframe_table`, `shellframe_confirm` require
  no modification.

---

## Testing

| Test | Method |
|---|---|
| No flicker on cursor movement | PTY test: send ↑/↓ keys, assert `\033[H\033[2J` does NOT appear between keystrokes |
| Full redraw on entry | Assert `\033[H\033[2J` IS emitted on first draw |
| Full redraw on resize | Change stty dimensions mid-session; assert `\033[H\033[2J` fires |
| Partial update targets correct rows | Assert `\033[N;1H` sequences target the expected row numbers after cursor movement |
| Regression: existing PTY tests pass | Run full `tests/ptyunit/run.sh` suite without modification |
| Cross-version portability | Docker matrix (`bash 3.2`, `4.4`, `5.2`) passes; dirty logic uses only integer comparisons and `local` variables |
