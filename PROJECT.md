# Project: ShellQL TUI Foundation
## Master Tracking Sheet

This document is the stateless source of truth for the ShellQL TUI build-out.
Start every new session by reading this file. Update task status here when work completes.

**Repos:**
- TUI library: `fissible/shellframe` (https://github.com/fissible/shellframe)
- App: `fissible/shellql` (local at `~/lib/fissible/shellql`, not yet on GitHub)

---

## Effort key

| Symbol | Size | Time estimate |
|--------|------|---------------|
| XS     | Tiny | < 1 hour      |
| S      | Small | 1–2 hours    |
| M      | Medium | ~half day   |
| L      | Large | ~1 day       |
| XL     | X-Large | 2–3 days  |

---

## Phase 1 — Core UI Contracts
> Define conventions before building anything. These are docs/interfaces, not code.

| # | Task                             | Effort | GH Issue | Status |
|---|----------------------------------|--------|----------|--------|
| 1 | Component contract (render, sizing, focus, input, state) | S | [#1](https://github.com/fissible/shellframe/issues/1) | closed |
| 2 | Layout contract (vstack, hstack, fixed, fill regions)    | S | [#2](https://github.com/fissible/shellframe/issues/2) | closed |
| 3 | Focus model (traversal, trapping, delegation)            | S | [#3](https://github.com/fissible/shellframe/issues/3) | closed |

---

## Phase 2 — Shared Behavior Modules
> Framework-level behavior. Must not be duplicated inside individual widgets.

| # | Task                             | Effort | GH Issue | Status |
|---|----------------------------------|--------|----------|--------|
| 4 | Keyboard input mapping module    | M | [#4](https://github.com/fissible/shellframe/issues/4) | closed |
| 5 | Selection model module           | S | [#5](https://github.com/fissible/shellframe/issues/5) | closed |
| 6 | Cursor model module              | M | [#6](https://github.com/fissible/shellframe/issues/6) | closed |
| 7 | Clipping and measurement helpers | S | [#7](https://github.com/fissible/shellframe/issues/7) | closed |

---

## Phase 3 — Foundation Primitives (shellframe)
> Build bottom-up. Each depends only on shared modules from Phase 2.

| # | Task                             | Effort | GH Issue | Status | Deps |
|---|----------------------------------|--------|----------|--------|------|
| 8  | Text primitive (render, clip, align, style) | M | [#8](https://github.com/fissible/shellframe/issues/8) | closed | 7 |
| 9  | Box/Panel (border, title, padding, focus state) | M | [#9](https://github.com/fissible/shellframe/issues/9) | closed | 7,8 |
| 10 | Scroll container (V+H scroll, clipping, pg/home/end) | L | [#10](https://github.com/fissible/shellframe/issues/10) | closed | 7 |
| 11 | Selectable list (items, selection, keyboard, scroll) | M | [#11](https://github.com/fissible/shellframe/issues/11) | closed | 5,10 |
| 12 | Input field (single-line, cursor, insert/delete, placeholder) | M | [#12](https://github.com/fissible/shellframe/issues/12) | closed | 6 |
| 13 | Tab bar (labels, active, overflow, keyboard) | S | [#13](https://github.com/fissible/shellframe/issues/13) | closed | 3,5 |
| 14 | Modal/dialog (overlay, focus trap, dismiss/confirm) | M | [#14](https://github.com/fissible/shellframe/issues/14) | closed | 3,9 |
| 15 | Tree view (expand/collapse, selection, keyboard, indent) | L | [#15](https://github.com/fissible/shellframe/issues/15) | closed | 5,10,11 |
| 16 | Text editor (multiline, cursor, scroll, submit hook) | L | [#16](https://github.com/fissible/shellframe/issues/16) | closed | 6,10,12 |
| 17 | Data grid (rows/cols, sticky header, H+V scroll, col width) | XL | [#17](https://github.com/fissible/shellframe/issues/17) | closed | 5,7,10 |

---

## Phase 4 — App Shell (shellframe)
> Generic shell usable by ShellQL and future shellframe apps.

| # | Task                             | Effort | GH Issue | Status | Deps |
|---|----------------------------------|--------|----------|--------|------|
| 18 | App shell (region layout, focus switching, screen routing, modal layer) | L | [#18](https://github.com/fissible/shellframe/issues/18) | closed | 1,2,3,9,14 |

---

## Phase 5 — Mock ShellQL Screens (shellql)
> Build against `SHQL_MOCK=1`. No sqlite3 calls. Validates the framework.

| # | Task                             | Effort | GH Issue | Status | Deps |
|---|----------------------------------|--------|----------|--------|------|
| 19 | Welcome screen (recent files list, open action, empty state) | M | [shellql#1](https://github.com/fissible/shellql/issues/1) | closed | 11,18 |
| 20 | Schema browser (sidebar tree + main pane detail)            | M | [shellql#2](https://github.com/fissible/shellql/issues/2) | closed | 15,18 |
| 21 | Table view (tab bar, data grid, structure tab)              | L | [shellql#3](https://github.com/fissible/shellql/issues/3) | closed | 13,17,18 |
| 22 | Query screen (editor + results grid + status area)          | M | [shellql#4](https://github.com/fissible/shellql/issues/4) | open | 16,17,18 |
| 23 | Record inspector (modal key/value scroll panel)             | S | [shellql#5](https://github.com/fissible/shellql/issues/5) | open | 14,18 |

---

## Phase 6 — SQLite Integration (shellql)
> Wire real sqlite3 behind the adapter seam.

| # | Task                             | Effort | GH Issue | Status | Deps |
|---|----------------------------------|--------|----------|--------|------|
| 24 | SQLite adapter: `src/db.sh` (list, describe, fetch, query) | L | shellql#TBD | open | - |
| 25 | Mock adapter: `src/db_mock.sh` (fixture data)              | S | shellql#TBD | open | - |
| 26 | CLI entry point: `bin/shql` (arg parse + mode dispatch)    | M | shellql#TBD | open | 24 |
| 27 | Discovery mode (recent/known databases)                    | S | shellql#TBD | open | 24,26 |
| 28 | Integration tests (real sqlite3, all CLI modes)            | M | shellql#TBD | open | 24,26 |

---

## Phase 7 — Platform Enhancements (shellframe)
> Keyboard hardening, diff rendering, and mouse support.
> Independent of ShellQL app phases — can be tackled in any order after Phase 4.
> Tasks A→C→D→E form one dependency chain (input → mouse parse → hit-test → routing).
> Tasks B→F form a second chain (dirty-region → framebuffer diff).

| # | Task | Effort | GH Issue | Status | Deps |
|---|------|--------|----------|--------|------|
| A | Input hardening: generic CSI drain path (prevents buffer leakage from unknown sequences), F1–F12 constants + recognition, modifier+arrow sequences (`\x1b[1;2A` etc.) — all changes in `src/input.sh` + `src/keymap.sh` | S | [#TBD](https://github.com/fissible/shellframe/issues) | open | 4 |
| B | Dirty-region rendering: widget dirty flags + conditional re-render in app loop; `shellframe_screen_clear` only called when full repaint is needed; render fns still write to `/dev/tty` — no API break | M | [#TBD](https://github.com/fissible/shellframe/issues) | open | 18 |
| C | Mouse: `shellframe_mouse_enter/exit` in `screen.sh`; SGR mouse sequence parsing in `shellframe_read_key`; `SHELLFRAME_MOUSE_COL/ROW/BUTTON/ACTION` output vars | S | [#TBD](https://github.com/fissible/shellframe/issues) | open | A |
| D | Widget hit-test registry: `shellframe_widget_register name top left width height` + `shellframe_widget_at row col`; new module `src/hitbox.sh` | M | [#TBD](https://github.com/fissible/shellframe/issues) | open | 9, 18 |
| E | Mouse routing in app shell + `on_mouse` handler per widget (click-to-focus, click-to-select in lists, scroll-wheel in scroll views) | M | [#TBD](https://github.com/fissible/shellframe/issues) | open | C, D |
| F | Framebuffer diff rendering: `_SF_FRAME_CURR/PREV[row*COLS+col]` flat indexed arrays; all render fns write to framebuffer instead of `/dev/tty`; `shellframe_screen_flush` diffs and emits only changed cells. See migration note in `src/screen.sh`. | XL | [#TBD](https://github.com/fissible/shellframe/issues) | open | B |

---

## Milestones

| Milestone | Condition | Status |
|-----------|-----------|--------|
| **M1: Shellframe ready** | Phase 1–4 all closed | open |
| **M2: Mock app complete** | Phase 5 all closed, mock screens working | in progress (3/5 screens done) |
| **M3: ShellQL v0.1** | Phase 6 all closed, integration tests passing | open |
| **M4: Platform enhancements** | Phase 7 all closed; mouse, diff rendering, full F-key support | open |

---

## Dependency graph

```
Phase 1 (contracts)
    │
    ├── Phase 2 (shared modules)
    │       │
    │       └── Phase 3 (primitives)
    │               │
    │               └── Phase 4 (app shell) ──→ Phase 5 (mock screens)
    │               │                                  │
    │               │                           Phase 6 (sqlite)
    │               │                                  │
    │               │                           shql v0.1 alpha
    │               │
    │               └── Phase 7 (platform enhancements) — parallel track
    │                       A (input hardening)
    │                       ├── C (mouse parse) → D (hit-test) → E (routing)
    │                       └── B (dirty-region) → F (framebuffer diff)
    └── (focus model feeds Phase 4 directly)
```

---

## Refactor-avoidance checklist
Before adding any new widget or screen:
- [ ] Is this a reusable primitive or a one-off?
- [ ] Is scrolling handled by the shared scroll container?
- [ ] Is focus handled by the framework focus model?
- [ ] Is text editing logic duplicated anywhere?
- [ ] Is layout logic embedded in a screen instead of layout primitives?
- [ ] Is selection behavior duplicated?
- [ ] Is this ShellQL-specific when it should live in shellframe?

---

## Session handoff notes
> Update this section at the end of each session.

_Last updated: 2026-03-16 (session 5)_
- shellql repo stubbed and pushed to GitHub (https://github.com/fissible/shellql)
- All 28 GitHub issues created: shellframe #1–18, shellql #1–9
- PROJECT.md is the master tracking sheet; shellql/PLAN.md cross-references shellframe issues
- Existing shellframe widgets (table, action-list, confirm, alert) are complete and tested
- Phase 1 complete: #1 component contract, #2 layout contract, #3 focus model written to `docs/contracts/`
- Phase 2 complete: #5 selection model, #7 clipping helpers, #4 keyboard input mapping, #6 cursor model (259/259 assertions)
  - `src/input.sh` extended: 14 key constants and 4-byte ESC sequence support in `shellframe_read_key`
  - `src/keymap.sh`: `shellframe_keyname`, `shellframe_keymap_bind/lookup`, `shellframe_keymap_default_nav/edit`
  - `src/cursor.sh`: full text cursor model — init, move, insert, backspace, delete, kill ops
- Phase 3 complete: #8 text, #9 panel, #10 scroll, #11 list, #12 input-field, #13 tab-bar (330/330 assertions across 11 test files)
  - All are v2 composable components (render/on_key/on_focus/size contract)
  - `src/text.sh`: `_shellframe_text_align`, `_shellframe_text_wrap_words`, `shellframe_text_render`, `shellframe_text_size`
  - `src/scroll.sh`: context-keyed V+H scroll state, `shellframe_scroll_move/ensure_row/ensure_col/resize`
  - `src/panel.sh`: single/double/rounded/none borders, title alignment, focus highlight
  - `src/widgets/tab-bar.sh`: horizontal tabs with reverse-video active highlight, left/right nav
  - `src/widgets/input-field.sh`: single-line edit using cursor.sh, all standard edit keys, mask mode
  - `src/widgets/list.sh`: scrollable list using selection.sh + scroll.sh, optional multiselect
  - Key decisions: `shellframe_sel_move ctx down` always moves 1 step (page_size only applies to page_up/page_down); field scroll is computed at render time from cursor position
- **ptyunit migration complete** (2026-03-16): shellframe now uses ptyunit as a git submodule (`tests/ptyunit/`); `tests/assert.sh`, `tests/run.sh`, `tests/pty_run.py` removed; all test files updated to `ptyunit_test_begin`/`ptyunit_test_summary`; Docker matrix updated. 352/352 assertions pass (330 unit + 22 integration). Run with `bash tests/ptyunit/run.sh`.
- **Phase 3 #14 Modal/dialog complete** (2026-03-16): `src/widgets/modal.sh` — centered panel overlay, message body, optional input field, button row (Left/Right/Tab cycle, Enter confirms, Esc dismisses). SHELLFRAME_MODAL_RESULT set on rc=2. 29/29 assertions.
- **Phase 4 #18 App shell complete** (2026-03-16): `src/shell.sh` — `shellframe_shell` v2 composable runtime. `shellframe_shell_region` registers named regions; `shellframe_shell_focus_set` queues focus by name; Tab/Shift-Tab traversal; key dispatch + screen routing via `PREFIX_SCREEN_<region>_on_key/action/quit` callbacks. 30/30 assertions. **M1 milestone: Phases 1–4 all closed.**
- **Phase 3 #15 Tree view complete** (2026-03-15): `src/widgets/tree.sh` — scrollable tree with expand/collapse, keyboard navigation, indent rendering. Parallel arrays (ITEMS/DEPTHS/HASCHILDREN) in pre-order. Space/Right expand, Left collapses or jumps to parent. SHELLFRAME_TREE_RESULT set on rc=2. 46/46 assertions. 457/457 total.
- **Phase 3 #16 Text editor complete** (2026-03-16): `src/widgets/editor.sh` — multiline editor rewritten to support soft word wrap (default) and no-wrap modes. Wrap mode: vmap (`_SHELLFRAME_ED_${ctx}_VMAP`) maps content rows to visual rows via `_shellframe_ed_line_segments` (soft wrap at last space ≤ width, hard wrap fallback); up/down move by visual row preserving vis_col. No-wrap mode: shared HSCROLL per context, lazy cursor-anchored scroll (only moves when cursor leaves viewport). 119/119 assertions. 576/576 total.
- **Editor polish (2026-03-16)**:
  - Bracketed paste (`\033[?2004h`): `shellframe_raw_enter/exit` enable/disable bracketed paste mode; `shellframe_read_key` rewritten to loop until CSI final byte (handles 6-byte `\033[200~`/`\033[201~`); editor `on_key` handler batches the entire paste via `_shellframe_ed_insert_text` — one vmap rebuild regardless of paste size. 588/588 assertions.
  - Render flicker fix: `shellframe_editor_render` now accumulates entire frame into a string and writes once (`printf '%s' "$_buf" >/dev/tty`); per-character cursor-row padding loop replaced with `printf '%*s'`; `_shellframe_ed_vrow_count` gained output-var form to eliminate `$()` subshell in page navigation.
  - Footer/doc labels: Ctrl-K/U/W changed from "kill" to "clear" (plain English).
  - Wrap cursor boundary fix: vrow movement functions previously clamped `new_col` to `seg_start + seg_len` (exclusive end), which equals the start of the next segment; `cursor_to_vrow`'s "last matching segment wins" rule then resolved the position to the wrong visual row, causing cursor jumps and invisible-character artifacts. Fixed by clamping intermediate segments to `seg_start + seg_len - 1` and last segments to `line_len`. 592/592 assertions.
- **Editor goal column (2026-03-16)**: `_SHELLFRAME_ED_${ctx}_GOAL_COL` added to `shellframe_editor_init`. All four vertical movement functions (move_up, move_down, page_up, page_down) store vis_col on first move and reuse it on subsequent vertical moves, so the cursor no longer snaps to col 0 after passing through blank or shorter lines. Non-vertical keys reset GOAL_COL to -1. 610/610 assertions (+18 new goal-col tests).
- **Phase 3 #17 Data grid complete** (2026-03-16): `src/widgets/grid.sh` — v2 composable data grid. Flat 1D `SHELLFRAME_GRID_DATA[row*COLS+col]` array. Sticky header (bold/white labels, only drawn when height ≥ 3 and headers set). `│` column separators between every pair of adjacent visible columns; `SHELLFRAME_GRID_PK_COLS` (int, default 0): separator after column PK_COLS-1 becomes `┃` (data rows) / `╋` (header junction) to visually mark the PK boundary. Header `─` separator row uses `┼`/`╋` junctions at separator x-positions. V scroll via selection.sh + scroll.sh row axis; H scroll via scroll.sh column axis (Left/Right pan 1 column). Conservative `vcols=1` init; `shellframe_scroll_resize` in render updates actual visible-column count. Cursor row: reverse video. Optional multiselect (Space). 52/52 assertions. 640/640 total.
- **M1 milestone achieved**: Phase 3 fully complete (#8–#17 all closed). Phase 4 (#18 app shell) was already closed. All of Phases 1–4 are done.
- **Widget showcase added (2026-03-16)**: `docs/showcase.md` — visual gallery with ASCII art + code for every widget (confirm, alert, action-list, list single/multi-select, modal prompt, editor, shellframe_app multi-screen, shellframe_shell composable pane layout). Linked from README "Going deeper". 662/662 assertions still pass.
- **Phase 5 progress (2026-03-16)**: shellql#1 welcome, shellql#2 schema browser, shellql#3 table view all closed. App navigates welcome → schema → table → schema.
  - Grid widget polished: H-scroll `_trailing_vis_cols` fix, 1-char left cell padding, right end-of-data `│`/`┘` border, cursor highlight suppressed when unfocused.
  - Tab bar: inactive=reverse video (persistent white bar), active=bold+clear bg, fill=reverse video.
  - Table screen: gap row below tab bar; ↓ from tab bar focuses body; ↑ at top of body returns focus to tab bar; `[`/`]` switch tabs from anywhere.
  - All shellframe widget changes committed in shellframe repo.
- **Next task: Phase 5.5 — Record inspector** ([shellql#5](https://github.com/fissible/shellql/issues/5)): modal or side panel, key/value layout from selected grid row, scroll for long values. `_shql_TABLE_body_action` hook already in place (Enter on data row triggers it).
