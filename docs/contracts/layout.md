# Layout Contract

> Phase 1 spec — no deps. Defines how screen space is partitioned into
> regions and passed to v2 composable components. Read alongside
> `component.md` and `focus.md`.

---

## Core concept: the region

A **region** is a rectangle of terminal cells described by four integers:

```
(top, left, width, height)
```

All coordinates are 1-based (matching ANSI cursor positioning). A region
`(1, 1, 80, 24)` is the full 80×24 terminal. All component `render` calls
receive a region; all layout calculations produce regions.

The app shell computes the full region tree before calling any `render`
function, so every component knows its exact bounds.

---

## Layout primitives

The layout system provides four primitives. They are composed to produce any
screen structure.

### `fixed <n>`

Occupies exactly `n` rows (in a vstack) or `n` columns (in an hstack).
`n` must be ≥ 1.

Use for: page chrome rows (title bar, footer bar, separators), column
headers, tab bars, status lines.

### `fill`

Expands to fill all remaining space after fixed children have been
allocated. If multiple `fill` children share a parent, the remaining
space is divided equally (integer division; remainder goes to the last
`fill` child).

Use for: main content areas, scroll containers, data grids.

### `hstack <child> [<child> ...]`

Arranges children left-to-right within the parent region. Each child
receives the full parent height. Total widths of all children must equal
the parent width (the layout resolver enforces this).

Children are described as `fixed <n>` or `fill` in the width dimension.
A separator column (`fixed 1`) between two content panes is common.

### `vstack <child> [<child> ...]`

Arranges children top-to-bottom within the parent region. Each child
receives the full parent width. Total heights of all children must equal
the parent height.

Children are described as `fixed <n>` or `fill` in the height dimension.

### `overlay <base> <floating>`

Renders `<floating>` on top of `<base>`. `<floating>` declares its own
preferred size (via `shellframe_<name>_size`); the layout resolver centers
it within the parent region. `<base>` is still rendered and receives input
when `<floating>` is not present.

Use for: modal dialogs, tooltips, inline alerts.

---

## Composing primitives: layout trees

Layouts are described as a tree of primitives. The app shell resolves the
tree once per draw, walking it top-down to produce a flat list of
`(component_name, top, left, width, height)` tuples.

Example — standard page with chrome, side panel, and footer:

```
vstack
  fixed 1    → title bar component
  fixed 1    → h1 component
  fixed 1    → separator (drawn inline by app shell, not a component)
  fill       → hstack
                 fill     → list component (left pane)
                 fixed 1  → separator (│ column)
                 fill     → detail component (right pane)
  fixed 1    → separator
  fixed 1    → footer bar component
```

---

## Layout resolution algorithm

The app shell resolves a layout tree with these steps:

1. **Compute terminal size.** Read `(rows, cols)` via `stty size </dev/tty`.

2. **Assign root region.** `(top=1, left=1, width=cols, height=rows)`.

3. **Walk the tree top-down.** For each node:
   - If it is a component leaf, record `(name, top, left, width, height)`.
   - If it is a `vstack`, allocate rows to each child:
     1. Sum all `fixed` heights.
     2. Divide remaining rows equally among `fill` children.
     3. Assign each child's top/left/width from the parent; height from step 1/2.
   - If it is an `hstack`, same logic but for columns.
   - If it is an `overlay`, resolve `<base>` normally, then compute
     the floating child's position from its `size` output, centered in the
     parent region.

4. **Render.** Call each component's `render` function in tree order
   (base before overlay).

---

## Separator rendering

Separators are drawn by the app shell, not by components. A `fixed 1`
separator slot with no component name is filled with `─` (horizontal) or
`│` (vertical) characters by the app shell before calling component renders.

This keeps separator styling in one place.

---

## Minimum terminal size

Each layout declares a minimum terminal size. If the actual terminal is
smaller, the app shell displays an error overlay ("Terminal too small —
resize to at least W×H") and suspends normal rendering until the terminal
is large enough.

The minimum size is computed from the sum of all `fixed` children plus a
minimum for each `fill` child (default: 3 rows / 10 columns per `fill`).

---

## Globals

The layout system exposes no globals directly. Region values are passed as
positional arguments to `render` calls. The app shell may cache the resolved
region tree in internal `_SHELLFRAME_APP_LAYOUT_*` globals, but these are
private and must not be read by components.

---

## Layout and the existing v1 widgets

v1 standalone widgets (`action-list`, `table`, `confirm`, `alert`) do not
participate in the layout system. They continue to claim the full terminal.
The layout system is only used when `shellframe_app` drives a v2 component
tree.

When the app shell's `type` function returns a v2 component name (rather than
the v1 names `action-list` / `table` / `confirm` / `alert`), the app shell
uses the layout system to render it. v1 and v2 screens can coexist in the
same FSM.

---

## Checklist

Before implementing the app shell (issue #18), verify:

- [ ] Region coordinates match ANSI 1-based addressing throughout
- [ ] `fill` division handles odd remainders without gaps (last child gets +1)
- [ ] Overlay centering handles a floating child wider/taller than its parent
  (clamp to parent bounds)
- [ ] Minimum terminal size check fires before any render
- [ ] Separator slots are drawn by the app shell, not components
