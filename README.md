# shellframe — Bash TUI Library

A composable, full-featured terminal UI library for bash. Designed to be
sourced by other tools — each widget gathers input from a human and returns
clean data to the caller.

**Requirements:** bash 3.2+ (macOS default), a VT100-compatible terminal.

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
- **Self-configuring** — on first load, shellframe detects the bash version and
  terminal capabilities, writes feature flags to `.toolrc.local`, and reads them
  back on subsequent runs so code paths are chosen once per machine.
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
| `src/screen.sh` | Alternate screen, cursor show/hide, raw mode, stty save/restore |
| `src/input.sh` | `shellframe_read_key`, `SHELLFRAME_KEY_*` constants (arrows, Tab, Shift-Tab, Ctrl combos, PgUp/Dn, Home, End, Delete) |
| `src/draw.sh` | `shellframe_pad_left`, color constants |
| `src/clip.sh` | `shellframe_str_clip`, `shellframe_str_clip_ellipsis`, `shellframe_str_pad`, `shellframe_str_len` — ANSI-aware string measurement and clipping |
| `src/selection.sh` | Cursor + multi-select state model for list widgets (`shellframe_sel_*`) |
| `src/keymap.sh` | Canonical key name lookup (`shellframe_keyname`), named action keymaps (`shellframe_keymap_bind/lookup`), default nav/edit keymaps |
| `src/cursor.sh` | Text cursor model for input fields — insert, delete, move, word-jump, kill ops (`shellframe_cur_*`) |
| `src/text.sh` | v2 text primitive — `shellframe_text_render`, align (left/center/right), word-wrap, `shellframe_text_size` |
| `src/scroll.sh` | V+H scroll state — `shellframe_scroll_move/resize/ensure_row/ensure_col`, multi-context |
| `src/panel.sh` | v2 bordered box — single/double/rounded/none styles, title alignment, focus highlight |
| `src/widgets/tab-bar.sh` | v2 horizontal tab bar — reverse-video active tab, left/right arrow nav |
| `src/widgets/input-field.sh` | v2 single-line text input — cursor.sh backed, all edit keys, placeholder, mask mode |
| `src/widgets/list.sh` | v2 scrollable selectable list — selection.sh + scroll.sh, optional multiselect |
| `src/widgets/action-list.sh` | v1 full-screen interactive action list |
| `src/widgets/table.sh` | v1 full-page navigable table with headers, page chrome, scroll, and optional below-area |
| `src/widgets/confirm.sh` | v1 modal yes/no dialog |
| `src/widgets/alert.sh` | v1 modal informational dismiss dialog |
| `src/app.sh` | `shellframe_app` — declarative multi-screen FSM runtime |

→ **[Full API reference](docs/api.md)**

---

## Going deeper

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
│   ├── screen.sh          # alternate screen, cursor, stty
│   ├── input.sh           # key reading + SHELLFRAME_KEY_* constants
│   ├── draw.sh            # shellframe_pad_left, color constants
│   ├── clip.sh            # ANSI-aware string measurement and clipping
│   ├── selection.sh       # cursor + multi-select state model (shellframe_sel_*)
│   ├── keymap.sh          # key name lookup + named action keymaps
│   ├── cursor.sh          # text cursor model for input fields (shellframe_cur_*)
│   ├── text.sh            # v2 text primitive — render, align, wrap (shellframe_text_*)
│   ├── scroll.sh          # v2 scroll state model — V+H, ensure_row/col (shellframe_scroll_*)
│   ├── panel.sh           # v2 bordered box — styles, title, focus (shellframe_panel_*)
│   ├── app.sh             # shellframe_app — declarative screen FSM runtime
│   └── widgets/
│       ├── tab-bar.sh     # v2 horizontal tab bar widget
│       ├── input-field.sh # v2 single-line text input widget
│       ├── list.sh        # v2 scrollable selectable list widget
│       ├── action-list.sh # v1 interactive action-list widget
│       ├── table.sh       # v1 full-page navigable table widget
│       ├── confirm.sh     # v1 modal yes/no confirmation dialog
│       └── alert.sh       # v1 modal informational dialog (dismiss-only)
├── docs/
│   ├── api.md             # full API reference
│   ├── skeletons.md       # copy-paste TUI skeletons
│   └── hard-won-lessons.md # bash TUI pitfalls
├── examples/
│   ├── list-select.sh     # single-select list demo
│   ├── action-list.sh     # action-list widget demo
│   ├── confirm.sh         # confirm modal demo
│   └── alert.sh           # alert modal demo
└── tests/
    ├── ptyunit/           # git submodule — test runner, assert.sh, pty_run.py
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
