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
| 4 | Keyboard input mapping module    | M | [#4](https://github.com/fissible/shellframe/issues/4) | open |
| 5 | Selection model module           | S | [#5](https://github.com/fissible/shellframe/issues/5) | closed |
| 6 | Cursor model module              | M | [#6](https://github.com/fissible/shellframe/issues/6) | open |
| 7 | Clipping and measurement helpers | S | [#7](https://github.com/fissible/shellframe/issues/7) | closed |

---

## Phase 3 — Foundation Primitives (shellframe)
> Build bottom-up. Each depends only on shared modules from Phase 2.

| # | Task                             | Effort | GH Issue | Status | Deps |
|---|----------------------------------|--------|----------|--------|------|
| 8  | Text primitive (render, clip, align, style) | M | [#8](https://github.com/fissible/shellframe/issues/8) | open | 7 |
| 9  | Box/Panel (border, title, padding, focus state) | M | [#9](https://github.com/fissible/shellframe/issues/9) | open | 7,8 |
| 10 | Scroll container (V+H scroll, clipping, pg/home/end) | L | [#10](https://github.com/fissible/shellframe/issues/10) | open | 7 |
| 11 | Selectable list (items, selection, keyboard, scroll) | M | [#11](https://github.com/fissible/shellframe/issues/11) | open | 5,10 |
| 12 | Input field (single-line, cursor, insert/delete, placeholder) | M | [#12](https://github.com/fissible/shellframe/issues/12) | open | 6 |
| 13 | Tab bar (labels, active, overflow, keyboard) | S | [#13](https://github.com/fissible/shellframe/issues/13) | open | 3,5 |
| 14 | Modal/dialog (overlay, focus trap, dismiss/confirm) | M | [#14](https://github.com/fissible/shellframe/issues/14) | open | 3,9 |
| 15 | Tree view (expand/collapse, selection, keyboard, indent) | L | [#15](https://github.com/fissible/shellframe/issues/15) | open | 5,10,11 |
| 16 | Text editor (multiline, cursor, scroll, submit hook) | L | [#16](https://github.com/fissible/shellframe/issues/16) | open | 6,10,12 |
| 17 | Data grid (rows/cols, sticky header, H+V scroll, col width) | XL | [#17](https://github.com/fissible/shellframe/issues/17) | open | 5,7,10 |

---

## Phase 4 — App Shell (shellframe)
> Generic shell usable by ShellQL and future shellframe apps.

| # | Task                             | Effort | GH Issue | Status | Deps |
|---|----------------------------------|--------|----------|--------|------|
| 18 | App shell (region layout, focus switching, screen routing, modal layer) | L | [#18](https://github.com/fissible/shellframe/issues/18) | open | 1,2,3,9,14 |

---

## Phase 5 — Mock ShellQL Screens (shellql)
> Build against `SHQL_MOCK=1`. No sqlite3 calls. Validates the framework.

| # | Task                             | Effort | GH Issue | Status | Deps |
|---|----------------------------------|--------|----------|--------|------|
| 19 | Welcome screen (recent files list, open action, empty state) | M | shellql#TBD | open | 11,18 |
| 20 | Schema browser (sidebar tree + main pane detail)            | M | shellql#TBD | open | 15,18 |
| 21 | Table view (tab bar, data grid, structure tab)              | L | shellql#TBD | open | 13,17,18 |
| 22 | Query screen (editor + results grid + status area)          | M | shellql#TBD | open | 16,17,18 |
| 23 | Record inspector (modal key/value scroll panel)             | S | shellql#TBD | open | 14,18 |

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

## Milestones

| Milestone | Condition | Status |
|-----------|-----------|--------|
| **M1: Shellframe ready** | Phase 1–4 all closed | open |
| **M2: Mock app complete** | Phase 5 all closed, mock screens working | open |
| **M3: ShellQL v0.1** | Phase 6 all closed, integration tests passing | open |

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
    │                                                  │
    │                                           Phase 6 (sqlite)
    │                                                  │
    │                                           shql v0.1 alpha
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

_Last updated: 2026-03-15_
- shellql repo stubbed and pushed to GitHub (https://github.com/fissible/shellql)
- All 28 GitHub issues created: shellframe #1–18, shellql #1–9
- PROJECT.md is the master tracking sheet; shellql/PLAN.md cross-references shellframe issues
- Existing shellframe widgets (table, action-list, confirm, alert) are complete and tested
- Phase 1 complete: #1 component contract, #2 layout contract, #3 focus model written to `docs/contracts/`
- Phase 2 partial: #5 selection model (`src/selection.sh`) and #7 clipping helpers (`src/clip.sh`) complete and tested (70/70 assertions)
- run.sh bug fixed: `local f` was outside a function (renamed to `local_f`)
- **Next session: remaining Phase 2 — #4 keyboard input mapping module (M effort) and #6 cursor model (M effort). Both are code. Start with #4 as it builds on the existing `src/input.sh`.**
