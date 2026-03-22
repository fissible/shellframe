# Coverage Improvement Plan — Design Spec

**Date:** 2026-03-22
**Project:** fissible/shellframe
**Baseline:** 44% line coverage (1,798 / 4,117 lines) via ptyunit PS4 trace
**Target:** ~70% line coverage
**Risk ordering:** consumer exposure (weighted highest) × uncovered lines × dependency depth

---

## Context

shellframe is a bash TUI library. Coverage is measured using `bash tests/ptyunit/coverage.sh --src=src`.
Three legacy monolithic widgets (confirm, alert, action-list) show 0% in the PS4 report not because they
lack PTY integration tests — they have them — but because PS4 tracing cannot follow code running inside
a `pty_run.py` subprocess. Raising their coverage requires extracting unit-testable internals.

---

## Phase 1 — Legacy widget refactor + unit tests

### Scope
Refactor `widgets/confirm.sh`, `widgets/action-list.sh`, and `widgets/alert.sh` from monolithic
functions into v2-style composable internals, then add unit tests.

### v2 refactor pattern (per widget)
Each widget gets:
- `_shellframe_<widget>_render()` — pure render function, no event loop, no I/O beyond `/dev/tty`
- `_shellframe_<widget>_on_key()` — pure key handler, accepts key name, returns action string
- `shellframe_<widget>()` — existing public wrapper, rewritten to drive the event loop using the two
  internal functions. **External interface unchanged — fully backward-compatible.**

**Exception — `alert`:** alert has no selection state; `_on_key` is a trivial single-path
"dismiss on any key" handler with no test value. For `alert`, extract `_render()` only.
`_on_focus` is not part of the pattern for any of these three widgets — they are full-screen
overlays, not composable into a `shellframe_shell` layout.

Unit tests cover:
- State → render output (assert rendered content given known state)
- Key → action mapping (assert `_on_key` returns correct action for each key; not applicable to alert)

After each widget: verify existing PTY integration tests still pass.

### Order (risk-first)
1. `confirm` — highest consumer exposure; used for destructive action confirmation
2. `action-list` — primary menu/selection workflow
3. `alert` — simplest, lowest risk

### Commit discipline
Each widget is one self-contained commit: refactor → unit tests → PTY green → commit.

---

## Phase 2 — New tests for zero-coverage files

Files with no tests at all, ordered by risk:

### `widgets/diff-view.sh` (highest priority in Phase 2)
- Prioritized first because it has zero test coverage with no implicit coverage path — any regression
  is completely invisible. Note: `shellframe_diff_view_render` contains significant pre-render geometry
  logic (footer detection, pane bounds, sync-scroll coordination) that is not terminal-sequence code;
  this is reachable by the integration test and does not require a separate unit test.
- Unit tests: `shellframe_diff_view_init`, `shellframe_diff_view_on_key`, `shellframe_diff_view_on_focus`
- Integration test: fixture script + `pty_run.py` to cover the render path (including pre-render logic)

### `app.sh` (`shellframe_app`, issue #21)
- Unit tests covering event loop behavior: screen routing, event dispatch, `_SHELLFRAME_APP_NEXT` transitions
- Callbacks can be bash functions defined inline in the test; no PTY required
- **Important:** `shellframe_app` directly calls `shellframe_action_list`, `shellframe_table`,
  `shellframe_confirm`, and `shellframe_alert`. These must be mocked via `ptyunit_mock` before
  calling `shellframe_app` — see `tests/ptyunit/mock.sh`.

### `screen.sh` (terminal control wrappers)
- Single integration test: source shellframe, enter raw mode, exit raw mode, assert clean terminal state
- Covers the lines without over-engineering thin wrappers

### `widgets/table.sh` (legacy monolithic widget)
- PTY integration test for basic rendering and key behavior
- No v2 refactor in this phase — ShellQL uses the v2 grid, not this widget, so risk is lower

### Order
diff-view → app.sh → screen.sh → table

---

## Phase 3 — Branch coverage for low-coverage files

Files with unit tests but large untested sections. Approach: read source, identify uncovered
lines via HTML report, add targeted test cases for missing branches. No structural changes.

| File | Baseline | Primary gap |
|------|---------|-------------|
| `panel.sh` | 17% | `shellframe_panel_render` — render path entirely untested |
| `widgets/modal.sh` | 23% | `shellframe_modal_init`, `shellframe_modal_render` |
| `shell.sh` | 28% | Focus-change logic in `_shellframe_shell_focus_next/prev` (unit tests); render path in `_shellframe_shell_draw` (PTY integration test) |
| `widgets/grid.sh` | 30% | render path, H-scroll edge cases |
| `widgets/tab-bar.sh` | 29% | render path |
| `text.sh` | 34% | `shellframe_text_render`, wrap edge cases |

For `_render` functions (panel, modal, grid, tab-bar): PTY integration tests.
For logic branches (init options, scroll edge cases, routing): unit tests.

### Order
panel → modal → shell → grid → tab-bar → text

---

## Success criteria

- All 775 existing assertions continue to pass throughout
- Each phase produces a clean, reviewable commit per widget/file
- `bash tests/ptyunit/coverage.sh --src=src` reaches ≥70% total after Phase 3
- No external interface changes (backward-compatible throughout)

---

## Out of scope

- `widgets/table.sh` v2 refactor (low risk, not used by ShellQL)
- `input.sh` / `shellframe_read_key` (requires PTY by nature; covered implicitly by integration tests)
- `screen.sh` full unit coverage (terminal control wrappers are inherently PTY-dependent)
