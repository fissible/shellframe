# shellframe — Development Guidelines

## Design philosophy

shellframe operates at two levels: a **widget library** for individual TUI interactions,
and an **application runtime** (`shellframe_app`) for multi-screen declarative apps.
New work should consider both levels — widgets are the building blocks; `shellframe_app`
is the engine that drives them.

### 1. LEGO composability

shellframe components are small, single-purpose, and composable — like LEGO bricks.
Each source file in `src/` provides one concern (screen, input, draw, widgets).
Widgets are built from primitives, not monoliths.

**Rules:**
- Every widget must work standalone when given only the primitives it depends on.
- Widgets must not call other widgets (no implicit coupling between peers).
- New components go in `src/widgets/` if they are interactive, `src/` if primitive.
- Document every public function's inputs, outputs, and globals in the source file.

### 2. Full-featured UI library, not just primitives

shellframe should cover the full lifecycle of gathering and using input from humans:

- **Input gathering**: prompts, free-text fields, password fields, confirmations
- **Selection**: single-select lists, multi-select lists, action-lists, navigable tables
- **Feedback**: progress bars, spinners, status lines, banners
- **Navigation**: paged lists, tabbed views, modal dialogs
- **Output**: formatted tables with page chrome (header bar, h1, footer bar), colored text, column layout

Every widget maps directly to a data shape: a list widget yields an array index,
a prompt yields a string, a multi-select yields a set of flags. The caller gets
clean data, not screen output.

### 3. Two audiences, one library

**Human users** (people running tools built with shellframe):
- Keyboard behavior must be predictable and documented in every widget's footer.
- Arrow keys, Enter, Space, Tab, `q` must work as expected everywhere.
- No surprise terminal state left behind on exit or Ctrl-C.

**Developer users** (bash tools that `source` shellframe):
- Every widget returns a predictable exit code (0 = confirmed, 1 = cancelled).
- Return values go to stdout; UI rendering goes to `/dev/tty`.
- Globals follow the `SHELLFRAME_<WIDGET>_*` naming convention so they namespace cleanly.
- The library must be sourceable with no side effects until a function is called.
- `shellframe_app` event handlers are called directly (not in subshells) — they can
  freely mutate application globals. See the subshell trap in Hard-won lessons.

### 4. Self-configuration and portability

shellframe auto-detects the runtime environment on first load and writes a local
config file (`.toolrc.local` in the project root, gitignored) so settings are
computed once and reused.

**On load, shellframe detects and persists:**
- Bash version (affects `read -t` precision, fd allocation syntax, `printf` behavior)
- Whether `{var}` fd allocation is available (bash 4.1+; macOS has 3.2)
- Whether `read -t` accepts decimals (bash 4+; 3.2 requires integers)
- Terminal capabilities (`tput` availability, `$TERM` value)

**Feature flags written to `.toolrc.local`:**
```bash
SHELLFRAME_BASH_VERSION=3      # major version
SHELLFRAME_FD_ALLOC=0          # 1 if {varname}>&1 syntax works
SHELLFRAME_READ_DECIMAL_T=0    # 1 if read -t 0.1 works
SHELLFRAME_TPUT_OK=1           # 1 if tput is functional
```

These flags are sourced by `shellframe.sh` at load time. Individual functions check
them to select the right code path rather than duplicating version detection.

### 5. Docker-based cross-version test suite

To ensure portability across bash versions, shellframe includes a Docker-based driver
suite that runs the test suite against multiple bash versions:

```
tests/
└── docker/
    ├── run-matrix.sh        # runs tests against all image tags
    ├── Dockerfile.bash3     # FROM bash:3.2 (simulates macOS)
    ├── Dockerfile.bash4     # FROM bash:4.4
    └── Dockerfile.bash5     # FROM bash:5.2
```

Run with: `bash tests/docker/run-matrix.sh`

Each container mounts the repo and runs `tests/run.sh`. A failure in any
version is a bug. The matrix must pass before merging changes to `src/`.

## Coding conventions

- All public symbols are prefixed `shellframe_` (functions) or `SHELLFRAME_` (globals/constants).
- Internal helpers are prefixed `_shellframe_` and must not be called by consumers.
- `shellframe_app` context globals are prefixed `_SHELLFRAME_APP_` and are reset before each
  screen render. Application state belongs in caller-defined globals, not here.
- Table widget globals are prefixed `SHELLFRAME_TBL_`. `SHELLFRAME_TBL_SCROLL` is the only
  table global intentionally NOT reset by `shellframe_app` — reset it in your render hook
  when loading new data so the list starts at the top.
- Use `local` for all function-scoped variables. Never pollute the caller's scope.
- Use `printf` for all output; never bare `echo` (behavior varies across systems).
- For bash 3.2 compatibility:
  - Use `$'\n'` not `"\n"` in comparisons.
  - Use integer `-t` values with `read`.
  - Use explicit fd numbers (3, 4…), not `{varname}` fd allocation.
  - Use `$(...)` not `<<<` when bash 3.2 `herestring` behavior matters.
  - Guard array expansions: `"${arr[@]+"${arr[@]}"}"` to avoid unbound variable
    errors on empty arrays under `set -u`.
- Always restore terminal state (`stty`, cursor, alternate screen) in an EXIT trap.

## Critical pitfalls

### Event handlers must not run in subshells

`shellframe_app` calls event handlers directly — never via `$()`. If an event handler
runs in a subshell, any globals it sets (including `_SHELLFRAME_APP_NEXT`) are lost when
the subshell exits. The app will loop forever or crash.

**Correct:**
```bash
_app_ROOT_confirm() { _SHELLFRAME_APP_NEXT="CONFIRM"; }
```

**Wrong:**
```bash
_app_ROOT_confirm() { printf 'CONFIRM'; }   # ← only works if called in $()
```

`_shellframe_app_event` (the rc→event-name mapper) runs in `$()` and is intentionally
pure. Event handlers (`confirm`, `quit`, `yes`, `no`, `dismiss`) are always
called directly.

### Empty array expansion under `set -u`

bash 3.2 treats `${arr[@]}` as unbound when the array is empty and `set -u` is
active. Always use the guard form when the array may be empty:
```bash
"${arr[@]+"${arr[@]}"}"
```

## Gitignore

`.toolrc.local` must be gitignored — it is per-machine, not per-repo.
