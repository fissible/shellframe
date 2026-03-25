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
| 22 | Query screen (editor + results grid + status area)          | M | [shellql#4](https://github.com/fissible/shellql/issues/4) | closed | 16,17,18 |
| 23 | Record inspector (modal key/value scroll panel)             | S | [shellql#5](https://github.com/fissible/shellql/issues/5) | closed | 14,18 |

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

## Phase 3.5 — New Widgets (shellframe)
> Additional interactive widgets that build on the Phase 1–3 primitives.
> All dependencies are already shipped — pure widget work.

| # | Task | Effort | GH Issue | Status | Deps |
|---|------|--------|----------|--------|------|
| 22 | Menu bar: horizontal bar + dropdown panel + submenu nesting; v2 contract (`init/render/on_key/on_focus/size`); bash 3.2-compatible label→variable naming; unit + integration tests + showcase entry | L | [#22](https://github.com/fissible/shellframe/issues/22) | closed | 4, 5, 7, 9 |

---

## Phase 7 — Platform Enhancements (shellframe)
> Keyboard hardening, diff rendering, and mouse support.
> Independent of ShellQL app phases — can be tackled in any order after Phase 4.
> Tasks A→C→D→E form one dependency chain (input → mouse parse → hit-test → routing).
> Tasks B→F form a second chain (dirty-region → framebuffer diff).

| # | Task | Effort | GH Issue | Status | Deps |
|---|------|--------|----------|--------|------|
| A | Input hardening: generic CSI drain path (prevents buffer leakage from unknown sequences), F1–F12 constants + recognition, modifier+arrow sequences (`\x1b[1;2A` etc.) — all changes in `src/input.sh` + `src/keymap.sh` | S | [#29](https://github.com/fissible/shellframe/issues/29) | closed | 4 |
| B | Dirty-region rendering: widget dirty flags + conditional re-render in app loop; `shellframe_screen_clear` only called when full repaint is needed; render fns still write to `/dev/tty` — no API break | M | [#30](https://github.com/fissible/shellframe/issues/30) | closed | 18 |
| C | Mouse: `shellframe_mouse_enter/exit` in `screen.sh`; SGR mouse sequence parsing in `shellframe_read_key`; `SHELLFRAME_MOUSE_COL/ROW/BUTTON/ACTION` output vars | S | [#32](https://github.com/fissible/shellframe/issues/32) | open | A |
| D | Widget hit-test registry: `shellframe_widget_register name top left width height` + `shellframe_widget_at row col`; new module `src/hitbox.sh` | M | [#31](https://github.com/fissible/shellframe/issues/31) | closed | 9, 18 |
| E | Mouse routing in app shell + `on_mouse` handler per widget (click-to-focus, click-to-select in lists, scroll-wheel in scroll views) | M | [#34](https://github.com/fissible/shellframe/issues/34) | open | C, D |
| F | Framebuffer diff rendering: `_SF_FRAME_CURR/PREV[row*COLS+col]` flat indexed arrays; all render fns write to framebuffer instead of `/dev/tty`; `shellframe_screen_flush` diffs and emits only changed cells. See migration note in `src/screen.sh`. | XL | [#33](https://github.com/fissible/shellframe/issues/33) | open | B |

---

## Milestones

| Milestone | Condition | Status |
|-----------|-----------|--------|
| **M1: Shellframe ready** | Phase 1–4 all closed | open |
| **M2: Mock app complete** | Phase 5 all closed, mock screens working | closed (5/5 screens done) |
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
- **showcase.md corrections (2026-03-16)**: Fixed two bugs — `if (( rc == 0 ))` → `if (( rc == 2 ))` in list example (Enter returns 2), `shellframe_editor_text` → `shellframe_editor_get_text`. Added `meta="$5"` to action-list `_draw_row` signature; inline comment on `shellframe_list_init` second arg.
- **Test coverage audit (2026-03-17)**:
  - `shellframe_app` has zero coverage — backlogged as [shellframe#21](https://github.com/fissible/shellframe/issues/21) (effort S)
  - Added `examples/modal.sh` + `tests/integration/test-modal.sh` (6 assertions) and `tests/integration/test-editor.sh` (6 assertions)
  - Added `assert_not_contains` to ptyunit submodule
  - Tab-bar and shell (unit-tested only, no integration example yet) remain a known gap
  - Confirm/alert/action-list have integration tests but no unit tests; recommended path is refactor to expose v2 internals (`_render` + `_on_key`) and keep monolithic wrappers — unit-testable state machine, backwards-compatible callers, aligns with LEGO philosophy
  - 674/674 assertions pass
- **Phase 3.5 #22 Menu bar backlogged (2026-03-17)**: [shellframe#22](https://github.com/fissible/shellframe/issues/22) — horizontal menu bar + dropdown + submenu. Deps: panel.sh, clip.sh, selection.sh, input/keymap (all shipped). Bash 3.2 label→variable naming convention (`SHELLFRAME_MENU_FILE=(...)`). Result path in `SHELLFRAME_MENU_RESULT` (e.g. `"File|Open Recent|file1.db"`). Effort L. Deliverables: `src/widgets/menu-bar.sh`, unit tests, example, integration tests, showcase entry.
- **Phase 5.5 Record inspector closed (shellql#5)**: `src/screens/inspector.sh` — two-column key/value overlay, `ceil(N/2)` scroll model; Enter on data row triggers it via `_shql_TABLE_body_action`.
- **Phase 5.4 Query screen closed (shellql#4)** (2026-03-17): `src/screens/query.sh` — editor 30% / `─` divider / results grid split; Ctrl-D runs query, auto-focuses results; Tab: editor→results→stop; Shift-Tab: results→editor→tabbar→stop; auto-focuses editor on Query tab entry. 19 unit assertions.
- **shellframe change (2026-03-17)**: `src/shell.sh` — Tab/Shift-Tab now offered to focused region's `on_key` before cycling focus; returning 0 consumes the key and suppresses the default advance/retreat. Backward-compatible: existing handlers that return 1 continue to get default behaviour.
- **M2 milestone achieved**: All Phase 5 mock screens complete (shellql#1–5 all closed).
- **Next task: Phase 6 — SQLite integration** (shellql#6–8): mock adapter cleanup, `src/db.sh` real adapter, CLI argument parsing (`bin/shql`).
- **MCP intrusion remediated (2026-03-22)**: A third-party `dual-graph` MCP server overwrote `CLAUDE.md` in both shellframe and shellql repos with its own "Dual-Graph Context Policy", and added `.dual-graph/` to both `.gitignore` files. A prior session reverted the CLAUDE.md replacements and pushed. This session removed `.dual-graph/` directories and `.claude/settings.local.json` hook configs from both repos. All 775 assertions still pass.
- **Coverage improvement branch `feature/coverage-improvement` (2026-03-22)** [shellframe#21 + plan `docs/superpowers/plans/2026-03-22-coverage-improvement.md`]:
  - All 3 phases complete: Phase 1 (refactor confirm/action-list/alert to extract `_on_key`/`_render` + unit tests), Phase 2 (new tests for diff-view, app.sh, screen.sh, table), Phase 3 (branch coverage for panel, modal, shell, grid, tab-bar, text).
  - 917/917 assertions pass on bash 3.2 (local) and bash 5.x (Docker).
  - Coverage: **58%** (2398/4145 code lines) measured via `bash tests/ptyunit/coverage.sh --src=src` under Docker bash 5. Baseline was 44% on bash 3.2. On bash 3.2, LINENO is dropped at nesting depth ≥3 in PS4 traces, so widget coverage shows 0% locally — always use Docker bash 5 for accurate numbers.
  - The 70% target in the plan was aspirational; monolithic keyboard event loops in confirm/action-list/table/diff-view (~700 lines) require PTY input and cannot be traced by the coverage tool. Effective coverage of unit-testable code is ~71%.
  - Both branches fully merged to `main` (PR #25 coverage improvement, PR #26 ptyunit Homebrew migration).
  - shellframe#21 can be closed.
- **ptyunit Homebrew migration complete (2026-03-23)**:
  - `feature/ptyunit-homebrew` merged as PR #26. Removes `tests/ptyunit/` git submodule; adds `bootstrap.sh` + `tests/run.sh`; all test files updated to `source "$PTYUNIT_HOME/assert.sh"`. Docker matrix mounts host ptyunit via `-v`. CI uses `bootstrap-command: bash bootstrap.sh`.
  - Worktrees `feature/coverage-improvement` and `feature/ptyunit-homebrew` removed; local branches deleted.
  - Run tests: `bash tests/run.sh --unit` (no submodule init needed; requires `bash bootstrap.sh` on first use).
- **diff-view render coverage added (2026-03-23)**:
  - 23 new assertions in `tests/unit/test-diff-view.sh` covering `_shellframe_dv_clip_ansi`, `_shellframe_dv_render_pane` (all 7 row types + HIDE_FILE_HDR path), `shellframe_diff_view_render` (with/without footer), `shellframe_diff_view_render_side`. `widgets/diff-view.sh`: **11% → 76%**. Total unit assertions: **880/880**. Overall coverage: **64%** (up from 58%).
  - HTML report: `coverage/2026_03_23_05_19_32.html` (linked from `coverage/index.html`).
- **`main` is clean**: 880/880 assertions, no dirty worktrees, no stale branches. Next: shellql Phase 6 (SQLite integration, shellql#6–8).
- **table widget unit coverage (2026-03-22)**: Extracted `_shellframe_table_on_key` and `_shellframe_table_scroll_check` from monolithic `shellframe_table` (same pattern as action-list). Added `tests/unit/test-table.sh` — 27 new assertions covering navigation, action cycling, confirm/quit, unhandled keys, and scroll boundary logic. Total: 907/907 assertions pass. `.DS_Store` added to `.gitignore`.
- **editor + shell coverage increase (2026-03-23)**: Added 28 new unit assertions (921 → 949). `test-editor.sh`: 20 assertions — `get_text` out_var form, `_shellframe_ed_is_printable` (3 cases), `_shellframe_ed_insert_string` empty no-op, `_shellframe_ed_line_segments` width=0, `_shellframe_ed_vrow_count` out_var form, `right` at EOL of last line, `ctrl-k` at EOL of last line (no-op), no-wrap `move_up`/`move_down` goal-col preservation, no-wrap `page_down`/`page_up`. `test-shell.sh`: 8 assertions — `_shellframe_shell_draw` coverage: re-registers regions, calls region render fns, dispatches `on_focus 1/0`, and applies `FOCUS_REQUEST` from old ring before firing on_focus. 949/949 assertions pass.
- **confirm + diff-view coverage increase (2026-03-23)**: Added 14 new unit assertions (907 → 921). `test-confirm.sh`: 4 new assertions for uppercase aliases `H` (Yes), `L` (No), `C` (confirm) — branches in `_shellframe_confirm_on_key` that were present but untested. `test-diff-view.sh`: 10 new assertions covering HL_ENABLED ctx path (left + right), hdr row status variants (`deleted`/`added` label on left/right pane — 4 cases), `render_side` right pane with footer, `shellframe_diff_view_render` with RIGHT_FOOTER and LEFT_DATE. 921/921 assertions pass.
- **ptyunit upgraded to v1.1.0 (2026-03-23)**: ptyunit cut a new release (v1.1.0) containing `fix(coverage): skip function declaration lines; add version + file links to HTML report`. Updated Homebrew formula (`/opt/homebrew/Library/Taps/fissible/homebrew-tap/Formula/ptyunit.rb`) to new tarball URL + sha256. `brew upgrade fissible/tap/ptyunit` applied cleanly. 949/949 assertions pass.
- **ptyunit v1.1.1 + coverage report (2026-03-23)**: Discovered Python 3.14 argparse incompatibility in `coverage_report.py` — `%` in `--min` help string raised `ValueError: badly formed help string`. Fixed by escaping as `%%`. Cut ptyunit v1.1.1, updated homebrew-tap formula, pushed. Coverage run produced `coverage/2026_03_23_00_08_12.html` (linked as default in `index.html`). Result: **70% total coverage** (2770/3957 lines), up from 64%. Highlights: diff-view 81%, editor 82%, grid 94%, modal 91%. Low floors (confirm 11%, action-list 18%, table 17%) are keyboard event loops requiring PTY — cannot be unit-traced.
- **Phase 3.5 #22 Menu bar complete (2026-03-23)**: `src/widgets/menu-bar.sh` — v2 composable widget. Horizontal bar + double-border dropdown + one-level submenu. Data model: SHELLFRAME_MENU_NAMES + SHELLFRAME_MENU_<NAME> arrays + @VARNAME:Label sigil for submenus. State machine: idle/bar/dropdown/submenu. shellframe_menubar_open for hotkey plug-in seam. SHELLFRAME_MENUBAR_RESULT on rc=2 (empty=dismiss, non-empty=selection path). Unit + integration tests + example + showcase entry. UX fix: spatial navigation model — Up from BAR releases focus upward (rc=2 empty); Up at first dropdown item closes to bar. 58 unit assertions, 7 integration tests. #22 closed. All tests pass (1007/1007 unit).
- **`main` is clean (2026-03-23)**: 1007/1007 unit assertions, no dirty worktrees, no stale branches. 17 commits ahead of origin (unpushed).
- **Next**: PM decision — Phase 7 platform enhancements or other prioritised work.
- **ptyunit upgraded to v1.3.0 (2026-03-24)**: Updated `homebrew-tap` formula from v1.0.0 → v1.3.0 (also picked up the `VERSION` file install added in v1.1.1). Resolved rebase conflict with upstream v1.1.1 commit, pushed to GitHub. `brew upgrade fissible/tap/ptyunit` applied cleanly (1.1.1 → 1.3.0). 1009/1009 unit assertions pass.
- **Coverage restored + improved to 70% (2026-03-25)**:
  - **Root cause of regression**: ptyunit v1.3.0 switched coverage tracing from `BASH_XTRACEFD=2` to `BASH_XTRACEFD=3`. Widget test files that do `exec 3>/dev/null` (to discard TUI render output) were silently killing the trace for their entire file. Previous 70% reading was measured with an older ptyunit version; v1.3.0 baseline measured 56.6%.
  - **Fix — fd dup technique**: Added to 8 affected test files (`test-menu-bar.sh`, `test-diff-view.sh`, `test-grid.sh`, `test-modal.sh`, `test-panel.sh`, `test-tab-bar.sh`, `test-table.sh`, `test-confirm.sh`):
    ```bash
    exec 4>&3 2>/dev/null || true   # dup trace fd; no-op outside coverage mode
    exec 3>/dev/null                 # discard widget render output
    BASH_XTRACEFD=4                  # keep trace on fd 4, safe from >&3 redirects
    ```
  - **New test file**: `tests/unit/test-screen.sh` — 8 assertions covering `shellframe_screen_clear`, `cursor_hide/show`, `raw_save`, `raw_enter`, `raw_exit`, `screen_exit`. `screen.sh`: **0% → 77%**.
  - **Extracted draw-row helpers to module level** (enables direct unit testing without PTY):
    - `_shellframe_al_default_draw_row` from `action-list.sh` — 5 new assertions in `test-action-list.sh`
    - `_shellframe_confirm_draw_buttons` from `confirm.sh` — 6 new assertions in `test-confirm.sh`
    - `_shellframe_tbl_default_draw_row` from `table.sh` — 5 new assertions in `test-table.sh`
  - **Result**: **70% total coverage** (3058/4356 lines), **1033/1033 assertions pass**. HTML report: `coverage/2026_03_25_07_21_10.html`.
  - Highlights after fix: menu-bar.sh 51% (from ~1%), grid 89%, modal 92%, tab-bar 92%, panel 84%.
  - Remaining low floors: action-list 24%, confirm 22%, table 20% — keyboard event loops requiring PTY input; not unit-traceable.
- **Coverage pass #2 — render tests (2026-03-25)**:
  - Added fd dup setup + render tests to `test-alert.sh` (was missing fd dup; render tests existed), `test-list.sh` (new `shellframe_list_render` tests), `test-input-field.sh` (new `shellframe_field_render` + `_shellframe_field_is_printable` tests).
  - **Result**: **84% total coverage** (3658/4356 lines), **1052/1052 assertions pass**.
  - Highlights: alert.sh 55%→89%, list.sh →98%, input-field.sh 54%→85%, screen.sh →100%.
- **Phase 7B dirty-region rendering complete (2026-03-25)**: [shellframe#30](https://github.com/fissible/shellframe/issues/30) closed.
  - `src/shell.sh`: `_SHELLFRAME_SHELL_DIRTY` flag, `shellframe_shell_mark_dirty()`, `_shellframe_shell_draw_if_dirty()`. Event loop skips `_shellframe_shell_draw` unless widget marks dirty. Tab/Shift-Tab always mark dirty (focus change always visible).
  - All 7 V2 composable widgets call `shellframe_shell_mark_dirty` before rc=0/2: list, input-field, editor, tab-bar, tree, grid, menu-bar.
  - Dirty integration tests added to all 7 widget test files + test-shell.sh. 1075/1075 assertions pass.
  - Docker matrix blocked by Docker Desktop file-sharing config (`/opt/homebrew/opt/ptyunit/libexec` not shared) — pre-existing infra issue, not a code regression.
  - Merged `feature/phase-7b-dirty-region` → `main`.
- **Phase 7A input hardening complete (2026-03-25)**: [shellframe#29](https://github.com/fissible/shellframe/issues/29) closed. F1–F12 constants (SS3 + CSI variants), 12 modifier+arrow constants (Shift/Alt/Ctrl × Up/Down/Left/Right), `shellframe_keyname` entries for all new sequences, CSI drain path documented. 61 new assertions. Cherry-picked from worktree agent onto main.
- **Phase 7D hitbox registry complete (2026-03-25)**: [shellframe#31](https://github.com/fissible/shellframe/issues/31) closed. New `src/hitbox.sh`: parallel-array bounding-box registry, last-registered-wins overlap, out_var form for `shellframe_widget_at`, selective `shellframe_widget_clear`. 15 unit assertions. 1151/1151 total assertions pass.
- **Phase 7 status**: A ✓, B ✓, D ✓ — C (#32, mouse) now unblocked (deps A done); F (#33, framebuffer diff) now unblocked (deps B done); E (#34, mouse routing) waits for C+D (both done when C ships).
- **Next**: Task C (#32, mouse: `shellframe_mouse_enter/exit` + SGR parsing + `SHELLFRAME_MOUSE_COL/ROW/BUTTON/ACTION`) — then F (#33) in parallel after C is started.
