# ADR 0001: v1 full-screen widgets and the v2 region runtime — coexistence plan

Status: Accepted (2026-08-25) — PM decision: preserve v1 APIs; migrate internals opportunistically.

## Context

shellframe has two widget architectures:

- **v1 full-screen widgets** (`confirm`, `alert`, `action-list`, `table`):
  standalone, one-shot, own their terminal lifecycle, return clean data via
  exit codes and work inside `$()`. They are the library's adoption showcase
  and drive `shellframe_app`.
- **v2 region/framebuffer runtime** (`shellframe_shell` + composable
  widgets): multi-pane apps, diff-flush rendering, mouse routing, sheets,
  hitboxes — everything Phase 7 built.

Both are used. The question posed in #55 was whether v1 earns its keep.

## Decision

**Keep both APIs. Migrate v1 internals onto shared primitives
opportunistically. Freeze new v1-exclusive features.**

Rationale: v1's benefit is not its rendering (that is inferior to v2's
framebuffer) — it is *zero-runtime standalone use*: one source line, no
screen declarations, works under `$()`. That is the first-run experience for
every new adopter and the reason the library is approachable. Removing it to
simplify maintenance would trade the on-ramp for internal tidiness.

Concretely:

1. **API freeze**: v1 widget signatures and exit-code contracts are stable.
   No new v1 widgets.
2. **Internal convergence where free**: v1 may adopt v2-era primitives
   (e.g. `_shellframe_pick_save_fd`, sanitizer, clip helpers) but must not
   grow dependencies on the v2 runtime loop.
3. **New interactive surfaces go to v2**: any widget needing regions, mouse,
   or composition (grid, tree, form, editor lineage) is v2-only. The #52
   feedback widgets (spinner/progress/status) target standalone scripts and
   are the sanctioned exception.
4. **Migration trigger**: if a v1 widget needs a fix that effectively means
   reimplementing v2 machinery, that is the moment to port it onto v2
   internals behind the same API — decided per case, not by blanket rewrite.

## Consequences

- Theming (#53) applies uniformly: both architectures read the same
  `SHELLFRAME_*` constants at render time.
- Docs must keep presenting both levels (README already does).
- Contributors should default to v2 for new work; v1 changes are bug-fix-only.
