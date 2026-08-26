# shellframe — Bash TUI Library

A composable, full-featured terminal UI library for bash. Designed to be
sourced by other tools — each widget gathers input from a human and returns
clean data to the caller.

**Requirements:** bash 3.2+ (macOS default), a VT100-compatible terminal,
and a POSIX environment (macOS/Linux/WSL — native Windows is not supported).

> **Windows users:** Git-Bash/msys/cygwin cannot provide the PTY semantics
> shellframe depends on; run under WSL instead. The loader warns if it
> detects a Windows-native environment.

> **Already using file descriptor 3?** shellframe opens a persistent tty
> fd (default 3) for rendering. If your script owns fd 3, set
> `SHELLFRAME_TTY_FD` to a free number **before sourcing** — e.g.
> `SHELLFRAME_TTY_FD=7 source ./shellframe.sh`.

> **Character-width limitation:** layout assumes single-column characters.
> Wide characters (CJK, emoji) render in two terminal columns and combining
> marks add none, but `shellframe_str_len` and every aligned surface (panel
> borders, table/grid columns, diff panes) count code points — so such text
> will misalign borders. ASCII and most Latin text is unaffected; a
> width-aware `shellframe_str_width` is tracked in #54.

---

## Design goals

- **LEGO composability** — small, single-purpose components that snap together.
  Source only what you need; widgets never implicitly depend on each other.
- **Full UI lifecycle** — covers input gathering, selection, feedback, and output
  formatting. Every widget maps to a clear data shape (string, index, flag set).
- **Two abstraction levels** — use widgets directly for simple one-off
  interactions (`shellframe_confirm`, `shellframe_alert`), or declare a multi-screen
  application with `shellframe_app`: define screens as function triples and let the
  runtime own the session loop, widget dispatch, and transitions.
- **Two audiences** — human-friendly keyboard behavior with discoverable footer
  hints; developer-friendly exit codes, namespaced globals, and stdout/tty split
  so widgets work correctly inside `$()` command substitution.
- **Runtime capability checks** — code paths select themselves per call site
  (`BASH_VERSINFO` guards for `read -t` precision and fd-allocation syntax,
  raw ANSI sequences instead of `tput` for screen control), so there is no
  config file to go stale. (An earlier design cached detection results in a
  `.toolrc.local`; it was never implemented and the docs now say so.)
- **Cross-version tested** — a Docker-based test matrix runs the suite against
  bash 3.2, 4.4, and 5.x to catch portability regressions before they ship.

---

## Quick start

**Single widget** — call a widget directly and read its exit code:

```bash
source /path/to/shellframe/shellframe.sh

shellframe_confirm "Deploy to production?" "  api-server  restart" "  cache       flush"
(( $? == 0 )) && deploy || echo "Cancelled."
```

**Multi-screen application** — declare screens as function triples, let
`shellframe_app` drive the loop:

```bash
source /path/to/shellframe/shellframe.sh

_app_ROOT_type()    { printf 'confirm'; }
_app_ROOT_render()  { _SHELLFRAME_APP_QUESTION="Continue?"; }
_app_ROOT_yes()     { _SHELLFRAME_APP_NEXT="DONE"; }
_app_ROOT_no()      { _SHELLFRAME_APP_NEXT="__QUIT__"; }

_app_DONE_type()    { printf 'alert'; }
_app_DONE_render()  { _SHELLFRAME_APP_TITLE="All done."; }
_app_DONE_dismiss() { _SHELLFRAME_APP_NEXT="__QUIT__"; }

shellframe_app "_app" "ROOT"
```

See [`examples/list-select.sh`](examples/list-select.sh) for a complete
working interactive list selector.

---

## API

| Module | Provides |
|---|---|
| `src/screen.sh` | Alternate screen, cursor, raw mode, stty, framebuffer (`shellframe_fb_*`, `shellframe_screen_flush`) |
| `src/input.sh` | `shellframe_read_key`, `SHELLFRAME_KEY_*` constants (arrows, Tab, Shift-Tab, Ctrl, F1–F12, modifier+arrow, mouse SGR) |
| `src/draw.sh` | `shellframe_pad_left`, color constants |
| `src/clip.sh` | `shellframe_str_clip`, `shellframe_str_clip_ellipsis`, `shellframe_str_pad`, `shellframe_str_len` — ANSI-aware |
| `src/selection.sh` | Cursor + multi-select state model (`shellframe_sel_*`) |
| `src/keymap.sh` | Key name lookup (`shellframe_keyname`), named action keymaps (`shellframe_keymap_bind/lookup`) |
| `src/cursor.sh` | Text cursor model — insert, delete, move, word-jump, kill ops (`shellframe_cur_*`) |
| `src/text.sh` | v2 text primitive — render, align (left/center/right), word-wrap, size |
| `src/scroll.sh` | V+H scroll state — move, resize, ensure_row/col, multi-context |
| `src/panel.sh` | v2 bordered box — single/double/rounded/none styles, title, focus highlight |
| `src/split.sh` | v2 horizontal/vertical split container — fixed or proportional panes |
| `src/hitbox.sh` | Widget hit-test registry — `shellframe_widget_register/at/clear` for mouse routing |
| `src/diff.sh` | Diff parsing — unified diff → structured line objects |
| `src/shell.sh` | `shellframe_shell` — v2 composable multi-pane runtime (region layout, Tab focus, key/mouse dispatch) |
| `src/sheet.sh` | Sheet navigation primitive — partial overlay with frozen back-strip, wizard transitions, `shellframe_sheet_push/pop` |
| `src/app.sh` | `shellframe_app` — declarative multi-screen FSM runtime (v1 widgets) |
| `src/widgets/tab-bar.sh` | v2 horizontal tab bar — reverse-video active tab, left/right arrow nav |
| `src/widgets/input-field.sh` | v2 single-line text input — cursor.sh backed, all edit keys, placeholder, mask mode |
| `src/widgets/list.sh` | v2 scrollable selectable list — selection.sh + scroll.sh, optional multiselect |
| `src/widgets/modal.sh` | v2 modal/dialog overlay — centered panel, message, optional input field, button row |
| `src/widgets/tree.sh` | v2 scrollable tree — expand/collapse, keyboard navigation, pre-order parallel arrays |
| `src/widgets/editor.sh` | v2 multiline text editor — soft word-wrap, no-wrap mode, bracketed paste, click-to-position |
| `src/widgets/grid.sh` | v2 data grid — sticky header, column separators, PK boundary marker, V+H scroll |
| `src/widgets/menu-bar.sh` | v2 horizontal menu bar — dropdown + submenu, `SHELLFRAME_MENUBAR_RESULT` |
| `src/widgets/form.sh` | v2 multi-field form — Tab traversal, scroll, `shellframe_form_render/on_key/values` |
| `src/widgets/toast.sh` | Flash/toast overlay — TTL-based auto-dismiss, theme-overridable colors |
| `src/widgets/autocomplete.sh` | Autocomplete overlay for input-field and editor — provider callback, auto/tab trigger |
| `src/widgets/scrollbar.sh` | Proportional scrollbar — auto-hide when content fits, `░`/`█` track |
| `src/widgets/context-menu.sh` | Floating context menu — border, keyboard nav, scroll, auto-positioning |
| `src/widgets/diff-view.sh` | Side-by-side diff viewer — unified diff input, syntax highlighting, line-level navigation |
| `src/widgets/action-list.sh` | v1 full-screen interactive action list |
| `src/widgets/table.sh` | v1 full-page navigable table with headers, page chrome, scroll |
| `src/widgets/confirm.sh` | v1 modal yes/no dialog |
| `src/widgets/alert.sh` | v1 modal informational dismiss dialog |

→ **[Full API reference](docs/api.md)**

---

## Going deeper

- [**Widget showcase**](docs/showcase.md) — visual gallery: ASCII art + code for every widget
- [**API reference**](docs/api.md) — every function, global, and callback signature
- [**TUI skeletons**](docs/skeletons.md) — copy-paste starting points for apps and custom widgets
- [**Hard-won lessons**](docs/hard-won-lessons.md) — 9 bash TUI pitfalls and how to avoid them
- [**CLAUDE.md**](CLAUDE.md) — development guidelines and coding conventions

---

## File layout

```
shellframe/
├── shellframe.sh          # entry point — source this
├── src/
│   ├── screen.sh          # alternate screen, cursor, stty, framebuffer
│   ├── input.sh           # key reading + SHELLFRAME_KEY_* constants + mouse SGR
│   ├── draw.sh            # shellframe_pad_left, color constants
│   ├── clip.sh            # ANSI-aware string measurement and clipping
│   ├── selection.sh       # cursor + multi-select state model (shellframe_sel_*)
│   ├── keymap.sh          # key name lookup + named action keymaps
│   ├── cursor.sh          # text cursor model for input fields (shellframe_cur_*)
│   ├── text.sh            # v2 text primitive — render, align, wrap
│   ├── scroll.sh          # v2 scroll state — V+H, ensure_row/col
│   ├── panel.sh           # v2 bordered box — styles, title, focus
│   ├── split.sh           # v2 split container — horizontal/vertical panes
│   ├── hitbox.sh          # widget hit-test registry for mouse routing
│   ├── diff.sh            # unified diff parser
│   ├── shell.sh           # shellframe_shell — v2 composable multi-pane runtime
│   ├── sheet.sh           # sheet navigation — partial overlay, wizard transitions
│   ├── app.sh             # shellframe_app — declarative screen FSM runtime (v1)
│   └── widgets/
│       ├── tab-bar.sh     # v2 horizontal tab bar
│       ├── input-field.sh # v2 single-line text input
│       ├── list.sh        # v2 scrollable selectable list
│       ├── modal.sh       # v2 modal/dialog overlay
│       ├── tree.sh        # v2 scrollable tree with expand/collapse
│       ├── editor.sh      # v2 multiline text editor (wrap + no-wrap)
│       ├── grid.sh        # v2 data grid with sticky header + V/H scroll
│       ├── menu-bar.sh    # v2 horizontal menu bar + dropdown + submenu
│       ├── form.sh        # v2 multi-field form with Tab traversal
│       ├── toast.sh       # flash/toast overlay with TTL auto-dismiss
│       ├── autocomplete.sh # autocomplete overlay for input-field + editor
│       ├── scrollbar.sh   # proportional scrollbar widget
│       ├── context-menu.sh # floating context menu with auto-positioning
│       ├── diff-view.sh   # side-by-side diff viewer
│       ├── action-list.sh # v1 interactive action-list widget
│       ├── table.sh       # v1 full-page navigable table widget
│       ├── confirm.sh     # v1 modal yes/no confirmation dialog
│       └── alert.sh       # v1 modal informational dialog (dismiss-only)
├── docs/
│   ├── api.md             # API reference
│   ├── showcase.md        # visual gallery: ASCII art + code for every widget
│   ├── skeletons.md       # copy-paste TUI skeletons
│   └── hard-won-lessons.md # bash TUI pitfalls
├── examples/
│   ├── list-select.sh     # single-select list demo
│   ├── action-list.sh     # action-list widget demo
│   ├── confirm.sh         # confirm modal demo
│   ├── alert.sh           # alert modal demo
│   ├── modal.sh           # modal prompt demo
│   ├── autocomplete.sh    # autocomplete overlay demo
│   └── sheet.sh           # two-step wizard using sheet navigation
└── tests/
    ├── docker/            # cross-version portability matrix (bash 3.2, 4.4, 5.x)
    ├── unit/
    └── integration/
```

---

## Portability

The key known portability difference is bash 3.2 (macOS default): no decimal
`-t` timeouts, no `{varname}` fd allocation, and subtly different `read`
behavior. See [Hard-won lessons](docs/hard-won-lessons.md) for details.

To test against multiple bash versions locally:

```bash
bash tests/docker/run-matrix.sh             # bash 3.2, 4.4, 5.x
bash tests/docker/run-matrix.sh --no-cache  # force clean rebuild
```
