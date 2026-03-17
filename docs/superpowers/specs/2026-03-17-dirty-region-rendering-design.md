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
| `src/widgets/confirm.sh` | Redraw loop for yes↔no button toggle (left/right arrow) |

### Out of scope

| Widget | Reason |
|---|---|
| `src/widgets/alert.sh` | Renders once, no redraw loop — nothing to optimize |
| `src/widgets/list.sh`, `src/widgets/modal.sh` | v2 composable; don't own the terminal or call `screen_clear`; dirty tracking belongs in their parent container |
| `src/widgets/tree.sh` | v2 composable; same reason as list/modal |
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
| Cursor movement causes `SHELLFRAME_TBL_SCROLL` to change (table) | `2` — the entire viewport shifts; a full redraw is required |
| Extra key handler returned "handled" (`_xrc == 0`) | `2` (conservative — caller may have launched a sub-TUI and called `shellframe_screen_enter` to re-enter; a full clear is required on re-entry) |
| Cursor up / down (no scroll offset change) | `1` |
| Right / Space (action-list / table: cycle action index on current row) | `1` (only the current row's display changed) |
| Button toggle — left/right arrow (confirm) | `1` |
| y / Y / n / N quick-select (confirm) | n/a — these break immediately without redraw |
| Unrecognized key | `0` |

### Resize detection

**`table.sh`:** already calls `stty size` on every draw; continue using that. Compare
against `_prev_rows`/`_prev_cols` locals (initialized to `0 0`); if either dimension
changed, force `_dirty=2`.

**`action-list.sh`:** add a `stty size` call at the start of `_al_draw`. Compare against
`_prev_rows`/`_prev_cols`. Resize is uncommon; the process substitution cost is
negligible compared to a terminal I/O frame.

**`confirm.sh`:** confirm does not resize-respond today (`_r0` is computed once before
the event loop and reused). Resize detection is out of scope for `confirm.sh` in Stage 1
— if the terminal resizes mid-confirm, the next full-redraw widget will recover. The
spec only requires confirm's partial path to reuse the pre-computed `_r0` and button-row
offset, which are already locals in scope throughout the event loop.

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

Row-to-terminal mapping: action-list has no scroll offset, so terminal row = item index + 1
(items start at row 1).

For Right/Space (action cycle), `_prev_sel == SHELLFRAME_AL_SELECTED`; only step 2 is
needed (the row re-renders with its new action label).

The existing row renderer (`_al_default_draw_row` or the caller-supplied `_draw_row_fn`)
is reused for both full and partial draws; no new rendering function is needed.

### `table.sh`

Two sub-cases, both still using `_dirty=1`:

**No panel** (`SHELLFRAME_TBL_PANEL_FN` empty):
- Same as action-list: redraw old and new cursor rows only.
- Terminal row = `_content_top + (item_index - SHELLFRAME_TBL_SCROLL)`.
- Page chrome (header bar, h1, column headers, footer bar, separators) is static during
  navigation; skip it entirely.
- `SHELLFRAME_TBL_BELOW_FN` region (if present) is also static during cursor movement;
  skip it on `_dirty=1`.
- If cursor movement causes `SHELLFRAME_TBL_SCROLL` to change, escalate to `_dirty=2`
  before drawing — the entire viewport has shifted.

**With panel** (`SHELLFRAME_TBL_PANEL_FN` set):
- Cursor movement changes both the cursor rows AND the panel content.
- Still `_dirty=1` (skip `screen_clear`); overwrite the two cursor rows AND the full
  panel region in-place.
- Chrome and the `SHELLFRAME_TBL_BELOW_FN` region are static; skip both.
- Result: no screen blank, panel repaints instantly, chrome never flickers.

### `confirm.sh`

Layout locals (`_r0`, button row offset) are computed once before the event loop and
remain in scope throughout — no need to requery terminal dimensions on partial draws.

Before entering the event loop, compute `_btn_row` as:

```
_btn_row = _r0 + 4 + _n_details + (1 if _n_details > 0 else 0)
```

(Derivation from the `_cf_draw` row sequence: top border (+0), blank (+1), `_n_details`
detail lines, blank separator when details present (+1), question (+1), blank (+1),
buttons → constant is `4`, not `5`. The conditional `+1` adds the separator row only
when detail lines are present.)

On left/right button toggle:
- Set `_dirty=1`.
- Move cursor to `_btn_row`; redraw just the button row at that absolute position.
- Question text and detail lines are static; skip them.

y/Y and n/N quick-select bindings exit via `break` immediately — they never reach the
draw branch and are unaffected by dirty levels.

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

The full `shellframe_screen_clear` sequence is `\033[H\033[3J\033[2J` (three parts;
`\033[3J` erases scrollback). All test assertions below use the complete sequence.

| Test | Method |
|---|---|
| No flicker on cursor movement | PTY test: send ↑/↓ keys, assert `\033[H\033[3J\033[2J` does NOT appear between keystrokes |
| Full redraw on entry | Assert `\033[H\033[3J\033[2J` IS emitted on first draw |
| Full redraw on resize | Change stty dimensions mid-session (action-list / table); assert `\033[H\033[3J\033[2J` fires |
| Partial update targets correct rows | Assert `\033[N;1H` sequences target the expected row numbers after cursor movement |
| Action cycle partial update | Send Right/Space; assert only current row is redrawn, no screen_clear |
| Confirm button toggle partial update | Send ←/→; assert only button row is redrawn, no screen_clear |
| Regression: existing PTY tests pass | Run full `tests/ptyunit/run.sh` suite without modification |
| Cross-version portability | Docker matrix (`bash 3.2`, `4.4`, `5.2`) passes; dirty logic uses only integer comparisons and `local` variables |
