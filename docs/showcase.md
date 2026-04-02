# shellframe — Widget Showcase

A visual gallery of every built-in widget: what it looks like, the code that
produces it, and what you get back.

---

## Confirm dialog

Ask a yes/no question with optional detail lines summarising what will happen.

```
+--------------------------------------------+
|                                            |
|  api-server    restart                     |
|  cache         flush                       |
|  workers       stop                        |
|                                            |
|       Deploy to production?                |
|                                            |
|           [ Yes ]      [ No  ]             |
|                                            |
+--------------------------------------------+
       ←/→ select   y/n quick   Enter confirm
```

```bash
source shellframe.sh

shellframe_confirm "Deploy to production?" \
    "  api-server    restart" \
    "  cache         flush" \
    "  workers       stop"

(( $? == 0 )) && deploy || echo "Cancelled."
```

**Returns:** `0` = Yes, `1` = No / Esc / `q`

---

## Alert dialog

Show a non-blocking message the user must dismiss — handy after a long
background operation finishes.

```
+--------------------------------------------+
|                                            |
|  api-server    v2.4.1  done                |
|  cache         cleared                     |
|  workers       3 restarted                 |
|                                            |
|          Deployment complete.              |
|                                            |
|              [ OK — any key ]              |
|                                            |
+--------------------------------------------+
              any key to dismiss
```

```bash
source shellframe.sh

shellframe_alert "Deployment complete." \
    "  api-server    v2.4.1  done" \
    "  cache         cleared" \
    "  workers       3 restarted"
```

**Returns:** always `0` after the user dismisses.

---

## Action list

Each item has a set of named actions; the user cycles through them with
Space / `→` and confirms the whole list with Enter. Great for "what do you
want to do with each of these?" workflows.

```
  Deploy to Production
  ────────────────────────────────────────────────────────
  api-server     [ restart  ]
  database       [ -------- ]
> cache          [  flush   ]
  workers        [ restart  ]
  cdn            [ -------- ]
  ────────────────────────────────────────────────────────
  ↑/↓ move  Space/→ cycle action  Enter confirm  q quit
```

```bash
source shellframe.sh

SHELLFRAME_AL_LABELS=("api-server" "database" "cache" "workers" "cdn")
SHELLFRAME_AL_ACTIONS=(
    "nothing restart"
    "nothing"
    "nothing flush"
    "nothing restart"
    "nothing"
)
SHELLFRAME_AL_IDX=(0 0 0 0 0)
SHELLFRAME_AL_META=("" "" "" "" "")

_draw_row() {
    local i="$1" label="$2" acts_str="$3" aidx="$4" meta="$5"
    local cursor="  "
    (( i == SHELLFRAME_AL_SELECTED )) && cursor="> "
    local -a acts; IFS=' ' read -r -a acts <<< "$acts_str"
    local action="${acts[$aidx]}"
    printf "%b%-14s  [ %-8s]\n" "$cursor" "$label" "$action"
}

shellframe_action_list "_draw_row" "" \
    "↑/↓ move  Space/→ cycle  Enter confirm  q quit"

if (( $? == 0 )); then
    for i in "${!SHELLFRAME_AL_LABELS[@]}"; do
        IFS=' ' read -r -a acts <<< "${SHELLFRAME_AL_ACTIONS[$i]}"
        action="${acts[${SHELLFRAME_AL_IDX[$i]}]}"
        [[ "$action" != "nothing" ]] && \
            printf "%s → %s\n" "${SHELLFRAME_AL_LABELS[$i]}" "$action"
    done
fi
```

**Returns:** `0` = confirmed, `1` = quit / Esc. Per-row action indices are in
`SHELLFRAME_AL_IDX[@]`.

---

## Scrollable list (single-select)

A cursor-driven list that fits any region. Cursor highlights with
reverse-video; scroll state is maintained automatically.

```
  ┌─────────────────────────────┐
  │ bash-completion             │
  │ curl                        │
  │ git                  ← here │
  │ jq                          │
  │ ripgrep                     │
  │ tmux                        │
  └─────────────────────────────┘
  ↑/↓ move  Enter select  q quit
```

```bash
source shellframe.sh

SHELLFRAME_LIST_ITEMS=("bash-completion" "curl" "git" "jq" "ripgrep" "tmux")
SHELLFRAME_LIST_CTX="pkgs"
shellframe_list_init "pkgs" 10   # ctx, visible-row count

shellframe_screen_enter
shellframe_raw_enter
shellframe_cursor_hide
trap 'shellframe_raw_exit; shellframe_cursor_show; shellframe_screen_exit' EXIT

while true; do
    shellframe_list_render 1 1 32 8
    shellframe_read_key key
    shellframe_list_on_key "$key"
    rc=$?
    (( rc == 2 )) && break   # Enter
    [[ "$key" == q ]] && { rc=1; break; }
done

if (( rc == 2 )); then
    idx=$(shellframe_sel_cursor "pkgs")
    printf "Selected: %s\n" "${SHELLFRAME_LIST_ITEMS[$idx]}"
fi
```

**Returns:** cursor position via `shellframe_sel_cursor`; exit code `0` =
confirmed, `1` = cancelled.

---

## Multi-select list

Same widget, `SHELLFRAME_LIST_MULTISELECT=1` turns Space into a toggle.
Selected rows get a `[✓]` prefix by convention (rendered by your draw logic
or the default renderer).

```
  ┌─────────────────────────────┐
  │ [✓] bash-completion         │
  │ [ ] curl                    │
  │ [✓] git                     │
  │ [ ] jq                      │
  │ [✓] ripgrep          ← here │
  │ [ ] tmux                    │
  └─────────────────────────────┘
  ↑/↓ move  Space toggle  Enter confirm
```

```bash
source shellframe.sh

SHELLFRAME_LIST_ITEMS=("bash-completion" "curl" "git" "jq" "ripgrep" "tmux")
SHELLFRAME_LIST_CTX="pkgs"
SHELLFRAME_LIST_MULTISELECT=1
shellframe_list_init "pkgs" 10   # ctx, visible-row count

# ... same render loop as single-select above ...

selected=$(shellframe_sel_selected "pkgs")   # space-separated indices
for i in $selected; do
    printf "Install: %s\n" "${SHELLFRAME_LIST_ITEMS[$i]}"
done
```

**Returns:** selected indices via `shellframe_sel_selected "ctx"` (space-separated).

---

## Modal prompt (with input)

A centered overlay with a message, an embedded text field, and labelled
buttons. Good for rename, add-item, and any short-answer prompts.

```
  ┌── Rename ───────────────────────────────────┐
  │                                             │
  │  New name for "report.csv":                 │
  │                                             │
  │  ┌───────────────────────────────────────┐  │
  │  │ Q4_report_final▌                      │  │
  │  └───────────────────────────────────────┘  │
  │                                             │
  │                [ OK ]  [ Cancel ]           │
  └─────────────────────────────────────────────┘
```

```bash
source shellframe.sh

SHELLFRAME_MODAL_TITLE="Rename"
SHELLFRAME_MODAL_MESSAGE='New name for "report.csv":'
SHELLFRAME_MODAL_BUTTONS=("OK" "Cancel")
SHELLFRAME_MODAL_INPUT=1
SHELLFRAME_MODAL_FOCUSED=1
shellframe_modal_init

shellframe_screen_enter
shellframe_raw_enter
shellframe_cursor_hide
trap 'shellframe_raw_exit; shellframe_cursor_show; shellframe_screen_exit' EXIT

cols=$(tput cols); rows=$(tput lines)
while true; do
    shellframe_modal_render 1 1 "$cols" "$rows"
    shellframe_read_key key
    shellframe_modal_on_key "$key"
    (( $? == 2 )) && break
done

if (( SHELLFRAME_MODAL_RESULT == 0 )); then
    name=$(shellframe_cur_text "${SHELLFRAME_MODAL_INPUT_CTX}")
    printf "Rename to: %s\n" "$name"
fi
```

**Returns:** `SHELLFRAME_MODAL_RESULT` — button index on Enter (`0` = first
button), `-1` on Esc / cancel. Input text via `shellframe_cur_text`.

---

## Multi-line editor

A full-region text editor with soft word-wrap and standard editing keys.
Useful for commit messages, notes, or any multi-line free-text field.

```
  ┌─ Notes ──────────────────────────────────────────────────┐
  │ Deploy the api-server first, then flush the cache.       │
  │ Workers can be restarted in parallel.                    │
  │                                                          │
  │ Do NOT restart the database during business hours.▌      │
  │                                                          │
  │                                                          │
  └──────────────────────────────────────────────────────────┘
  Ctrl-D submit  Ctrl-C cancel  Ctrl-K kill line
```

```bash
source shellframe.sh

SHELLFRAME_EDITOR_CTX="notes"
SHELLFRAME_EDITOR_WRAP=1          # soft word-wrap (0 = horizontal scroll)
shellframe_editor_init "notes"

shellframe_screen_enter
shellframe_raw_enter
shellframe_cursor_show
trap 'shellframe_raw_exit; shellframe_cursor_show; shellframe_screen_exit' EXIT

cols=$(tput cols); rows=$(tput lines)
while true; do
    shellframe_editor_render 2 2 $(( cols - 2 )) $(( rows - 3 ))
    shellframe_read_key key
    shellframe_editor_on_key "$key"
    rc=$?
    (( rc == 2 )) && break   # Ctrl-D
    [[ "$key" == $'\003' ]] && { rc=1; break; }   # Ctrl-C
done

(( rc == 0 )) && printf "Text:\n%s\n" "$(shellframe_editor_get_text "notes")"
```

**Returns:** full text via `shellframe_editor_get_text "ctx"`.

---

## Multi-screen app (`shellframe_app`)

For flows with multiple screens, declare each screen as a function triple
and let `shellframe_app` drive the loop. No render loop or key dispatch to
write yourself.

```
Screen 1 — confirm                Screen 2 — alert (after Yes)
+----------------------------------+  +----------------------------------+
|                                  |  |                                  |
|    Flush the Redis cache?        |  |       Cache flushed.             |
|                                  |  |                                  |
|       [ Yes ]      [ No  ]       |  |        [ OK — any key ]          |
|                                  |  |                                  |
+----------------------------------+  +----------------------------------+
```

```bash
source shellframe.sh

# Screen 1: confirm
_app_CONFIRM_type()   { printf 'confirm'; }
_app_CONFIRM_render() {
    _SHELLFRAME_APP_QUESTION="Flush the Redis cache?"
}
_app_CONFIRM_yes()    { _SHELLFRAME_APP_NEXT="DONE"; }
_app_CONFIRM_no()     { _SHELLFRAME_APP_NEXT="__QUIT__"; }

# Screen 2: alert
_app_DONE_type()      { printf 'alert'; }
_app_DONE_render()    {
    _SHELLFRAME_APP_TITLE="Cache flushed."
    flush_cache    # run your real work here
}
_app_DONE_dismiss()   { _SHELLFRAME_APP_NEXT="__QUIT__"; }

shellframe_app "_app" "CONFIRM"
```

**How it works:** `shellframe_app` calls `_app_SCREEN_render()` to populate
globals, renders the widget declared by `_app_SCREEN_type()`, maps the
keypress to an event name, and calls `_app_SCREEN_<event>()` to set
`_SHELLFRAME_APP_NEXT`. Screens transition without any loop boilerplate.

---

## Tab bar

A horizontal row of labelled tabs. Left/Right arrow keys cycle focus; the
active tab is rendered in reverse-video.

```
  ┌─────────────────────────────────────────────────────────┐
  │  Overview  │  Deployments  │  Logs  │  Settings         │
  ├─────────────────────────────────────────────────────────┤
  │                                                         │
  │  (content area for the active tab)                      │
  │                                                         │
  └─────────────────────────────────────────────────────────┘
```

```bash
source shellframe.sh

SHELLFRAME_TABBAR_TABS=("Overview" "Deployments" "Logs" "Settings")
SHELLFRAME_TABBAR_ACTIVE=0
SHELLFRAME_TABBAR_FOCUSED=1

# In your render loop:
shellframe_tabbar_render 1 1 "$cols" 1

# In your key handler:
shellframe_tabbar_on_key "$key"
active=$SHELLFRAME_TABBAR_ACTIVE
```

**Returns:** active tab index in `SHELLFRAME_TABBAR_ACTIVE` (0-based).

---

## Putting it together — composable multi-pane app

The v2 runtime (`shellframe_shell`) lets you declare named regions, assign
widgets to them, and handle focus traversal with Tab. Each region gets its
own render and key-handler callbacks.

```
  ┌─ shellframe demo ──────────────────────────────────────────┐
  │  Overview  │  Deployments  │  Logs  │  Settings            │
  ├────────────────────────────────────────────────────────────┤
  │ ┌─ Services ──────────────┐  ┌─ Details ────────────────┐  │
  │ │   api-server            │  │  Service:   api-server   │  │
  │ │ > worker          ←     │  │  Version:   v2.4.0       │  │
  │ │   cache                 │  │  Status:    live         │  │
  │ │   cdn                   │  │  Deployed:  1 day ago    │  │
  │ └─────────────────────────┘  └──────────────────────────┘  │
  └────────────────────────────────────────────────────────────┘
  Tab next pane  ↑/↓ move  Enter select  q quit
```

```bash
source shellframe.sh

# Declare regions: name top left width height [nofocus]
shellframe_shell_region "tabs"    1  1  "$cols"  1  nofocus
shellframe_shell_region "list"    3  1  30       20
shellframe_shell_region "detail"  3  32 0        20   # 0 = fill remaining

# Render callbacks — called on every draw cycle
_demo_ROOT_tabs_render()   { shellframe_tabbar_render   "$@"; }
_demo_ROOT_list_render()   { shellframe_list_render     "$@"; }
_demo_ROOT_detail_render() { shellframe_panel_render    "$@"; }

# Key callbacks — return 0 (handled), 1 (pass on), 2 (submit/quit)
_demo_ROOT_list_on_key() {
    shellframe_list_on_key "$1"
    local rc=$?
    (( rc == 2 )) && _SHELLFRAME_APP_NEXT="DETAIL"
    return $rc
}

shellframe_shell "_demo" "ROOT"
```

See [`docs/skeletons.md`](skeletons.md) for copy-paste starting points for
each of the patterns above.

## Menu bar

Horizontal menu bar with dropdowns and one level of submenu nesting.

```
 File  Edit  View
╔══════════════════╗
║ Open             ║
║ Save             ║
║ ════════════════ ║
║ Recent Files    ▶║╔══════════════╗
║ ════════════════ ║║ demo.db      ║
║ Quit             ║║ work.db      ║
╚══════════════════╝║ archive.db   ║
                    ╚══════════════╝
```

```bash
source shellframe.sh

SHELLFRAME_MENU_NAMES=("File" "Edit" "View")
SHELLFRAME_MENU_FILE=("Open" "Save" "---" "@RECENT:Recent Files" "---" "Quit")
SHELLFRAME_MENU_RECENT=("demo.db" "work.db" "archive.db")

SHELLFRAME_MENUBAR_CTX="demo"
shellframe_menubar_init "demo"
shellframe_menubar_on_focus 1

exec 3>/dev/tty
while true; do
    shellframe_menubar_render 1 1 "$cols" "$rows"
    shellframe_read_key key
    shellframe_menubar_on_key "$key"
    (( $? == 2 )) && break
done

printf 'Selected: %s\n' "$SHELLFRAME_MENUBAR_RESULT"
```

**Data model:** `SHELLFRAME_MENU_<NAME>` arrays hold items. `---` = separator.
`@VARNAME:Label` declares a submenu backed by `SHELLFRAME_MENU_VARNAME`.
Result path in `SHELLFRAME_MENUBAR_RESULT` (e.g. `File|Recent Files|demo.db`).
Empty result = dismissed with Esc.

---

## Autocomplete

Layers a filtered suggestion popup on any input field or editor.
Consumer provides a callback; shellframe handles the UI.

```
┌──────────────────────────────────────┐
│ Table name: us█                      │
│              ┌──────────────┐        │
│              │ users        │        │
│              │ user_roles   │        │
│              └──────────────┘        │
│                                      │
│  Tab: complete  Esc: dismiss         │
└──────────────────────────────────────┘
```

```bash
# Provider: return matches for prefix
_my_provider() {
    local _prefix="$1" _out="$2"
    local _items=("users" "user_roles" "products")
    local _matches=()
    local _i
    for _i in "${_items[@]}"; do
        case "$_i" in "${_prefix}"*) _matches+=("$_i") ;; esac
    done
    eval "$_out=(\"\${_matches[@]+\"\${_matches[@]}\"}\")"
}

# Attach to an input field
shellframe_field_init "myfield"
SHELLFRAME_AC_PROVIDER="_my_provider"
SHELLFRAME_AC_TRIGGER="tab"
shellframe_ac_attach "myfield" "field"

# In your on_key handler:
shellframe_ac_on_key "$key" && return 0
# ... field processes key ...
shellframe_ac_on_key_after   # re-filter in auto mode
```
