# Focus Model

> Phase 1 spec — no deps. Defines which component receives keystrokes,
> how focus moves between components, and how modals trap focus.
> Read alongside `component.md` and `layout.md`.

---

## What focus means

**Focus** is the property of being the component that receives the next
keypress. At any moment, at most one component has focus.

The app shell maintains a **focus owner** — the name of the currently focused
component. Every keypress is delivered to the focus owner's `on_key` handler
first. If `on_key` returns `1` (not handled), the app shell may bubble the
key up to a parent handler or discard it.

---

## Focusable vs non-focusable components

Every v2 component declares its focusability by setting a global at source
time:

```bash
SHELLFRAME_<NAME>_FOCUSABLE=1   # receives Tab traversal (default)
SHELLFRAME_<NAME>_FOCUSABLE=0   # display-only; skipped by Tab
```

Non-focusable components (e.g. text labels, separators, title bars) are never
made the focus owner by Tab traversal, but they still receive `on_focus 0`
notifications if they were previously focused by other means.

---

## Focus traversal

`Tab` and `Shift-Tab` move focus among the focusable components in the
**current focus group** (see Focus groups below) in layout order (top-to-left,
top-to-bottom within the group).

The app shell intercepts `Tab` / `Shift-Tab` before delivering keys to the
focused component. A component cannot consume these keys.

```
Tab         — move focus to the next focusable component (wraps at end)
Shift-Tab   — move focus to the previous focusable component (wraps at start)
```

When focus moves:
1. Call `on_focus 0` on the old focus owner.
2. Update the focus owner to the new component.
3. Call `on_focus 1` on the new focus owner.
4. Redraw both components.

---

## Focus groups

A **focus group** is a set of focusable components among which Tab traversal
is confined. The app shell defines one root focus group containing all
focusable components in the current screen layout.

When a modal is opened, a new focus group is pushed onto the **focus stack**
(see below). Tab traversal is then confined to the modal's components until
the modal is dismissed.

---

## Focus stack

The focus stack is a LIFO stack of focus groups. It supports modal dialogs
that trap focus.

```
_SHELLFRAME_APP_FOCUS_STACK   # array of focus group names (internal)
_SHELLFRAME_APP_FOCUS_OWNER   # name of the currently focused component
```

**Push (modal open):**
1. Save the current focus owner.
2. Push a new focus group containing the modal's components.
3. Set focus owner to the first focusable component in the modal.

**Pop (modal dismiss):**
1. Pop the current focus group from the stack.
2. Restore the focus owner to the saved value from before the push.
3. Call `on_focus 1` on the restored focus owner.

This ensures that closing a modal returns focus exactly where it was.

---

## Focus delegation

A **container** component (e.g. a scroll container wrapping a list)
may **delegate** focus to its active child by forwarding `on_key` calls.

When the scroll container has focus and receives a keypress, it first
offers the key to its child's `on_key`. If the child returns `1`
(not handled), the scroll container handles the key itself (e.g. scroll
by page with `PgUp`/`PgDn`).

**Rules for delegation:**
- The container is the registered focus owner. The child is never directly
  in the focus list — it is internal to the container.
- The container calls `on_focus 1` on the child when the container gains
  focus; `on_focus 0` when it loses focus.
- The container is responsible for redrawing the child as part of its own
  `render` call.

---

## Key routing flow

For every keypress `k` from the input loop:

```
1. If k == Tab:         advance focus (see traversal above); redraw; continue
2. If k == Shift-Tab:   retreat focus; redraw; continue
3. Deliver k to focus_owner.on_key(k):
   - rc == 0: key handled — redraw focus owner; continue
   - rc == 1: key not handled — bubble to app shell default handler
   - rc == 2: quit/dismiss — fire the appropriate FSM event
4. App shell default handler:
   - q / Q / Esc: fire quit event for the current screen
   - other: discard
```

---

## Focus initialization

When a new screen is rendered:

1. The app shell builds the component list in layout order.
2. It selects the first focusable component as the initial focus owner.
3. It calls `on_focus 1` on that component.

If no focusable component exists in the layout, the focus owner is `""` and
all keypresses fall through to the app shell default handler.

---

## Component requirements

A component that participates in focus must:

- Set `SHELLFRAME_<NAME>_FOCUSABLE=1` at source time (or `=0` to opt out).
- Implement `shellframe_<name>_on_focus focused` to show/hide a focus
  indicator (e.g. a highlighted border, a blinking cursor, a bold title).
- Render the focus indicator from `render` based on a flag global
  (`SHELLFRAME_<NAME>_FOCUSED=1`), not from within `on_focus` itself — this
  keeps rendering idempotent.

Suggested pattern:

```bash
SHELLFRAME_LIST_FOCUSABLE=1
SHELLFRAME_LIST_FOCUSED=0

shellframe_list_on_focus() {
    local _focused="$1"
    SHELLFRAME_LIST_FOCUSED=$_focused
    # app shell calls render after this; nothing to draw here
}

shellframe_list_render() {
    local _top="$1" _left="$2" _width="$3" _height="$4"
    local _border_color
    (( SHELLFRAME_LIST_FOCUSED )) && _border_color="$SHELLFRAME_BOLD" || _border_color="$SHELLFRAME_GRAY"
    # ... render using _border_color for the border
}
```

---

## Globals (app shell internal)

These globals are managed by the app shell and must not be read or written
by components:

| Global | Description |
|--------|-------------|
| `_SHELLFRAME_APP_FOCUS_OWNER` | Name of the currently focused component |
| `_SHELLFRAME_APP_FOCUS_STACK` | Array of saved focus owners (pushed by modals) |
| `_SHELLFRAME_APP_FOCUS_GROUP` | Ordered array of focusable component names in the current group |
