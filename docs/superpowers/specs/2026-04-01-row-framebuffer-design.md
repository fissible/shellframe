# Row-Based Framebuffer Design

**Issue:** [shellframe#39](https://github.com/fissible/shellframe/issues/39)
**Date:** 2026-04-01
**Effort:** L (estimated)

## Problem

The framebuffer stores one cell per array slot (`_SF_FRAME_CURR[row*COLS+col]`).
`shellframe_fb_print` decomposes strings character-by-character — one bash substring
op, one arithmetic expansion, one array write, and one dirty-list append per character.
`shellframe_fb_fill` has the same structure. `shellframe_screen_flush` emits one
cursor-position `printf` per changed cell.

For a 50-row × 10-column × ~15-char grid: ~13,500 bash iterations on write +
up to ~7,500 `write()` syscalls on flush. On macOS bash 5 this is 50-200 ms/frame,
making grid scrolling feel laggy at typical key-repeat rates.

## Solution: Positioned Fragment Accumulation

Replace per-cell storage with per-row string accumulation. Each `fb_*` call appends
a positioned ANSI fragment (cursor-position escape + prefix + content) to the row
string. Flush compares whole row strings and emits one `printf` per changed row.

### Data Model

Replaces `_SF_FRAME_CURR`, `_SF_FRAME_PREV`, `_SF_FRAME_DIRTY`:

```bash
_SF_ROW_CURR=()          # _SF_ROW_CURR[$row] = accumulated positioned fragments
_SF_ROW_PREV=()          # _SF_ROW_PREV[$row] = last emitted row string
_SF_DIRTY_ROWS=()        # _SF_DIRTY_ROWS[$row]=1 for rows written this frame
_SF_FRAME_ROWS=24
_SF_FRAME_COLS=80
```

### Write API

All functions retain the same public signature. Implementations become O(1):

```bash
shellframe_fb_frame_start() {   # rows cols
    _SF_FRAME_ROWS="${1:-24}"; _SF_FRAME_COLS="${2:-80}"
    _SF_ROW_CURR=(); _SF_DIRTY_ROWS=()
}

shellframe_fb_put() {           # row col cell
    local _frag; printf -v _frag '\033[%d;%dH%s' "$1" "$2" "$3"
    _SF_ROW_CURR[$1]+="$_frag"; _SF_DIRTY_ROWS[$1]=1
}

shellframe_fb_print() {         # row col str [prefix]
    local _frag; printf -v _frag '\033[%d;%dH%s%s' "$1" "$2" "${4:-}" "$3"
    _SF_ROW_CURR[$1]+="$_frag"; _SF_DIRTY_ROWS[$1]=1
}

shellframe_fb_fill() {          # row col n [char] [prefix]
    local _fill; printf -v _fill '%*s' "$3" ''
    [[ "${4:- }" != " " ]] && _fill="${_fill// /${4}}"
    local _frag; printf -v _frag '\033[%d;%dH%s%s' "$1" "$2" "${5:-}" "$_fill"
    _SF_ROW_CURR[$1]+="$_frag"; _SF_DIRTY_ROWS[$1]=1
}

shellframe_fb_print_ansi() {    # row col rendered_str
    local _frag; printf -v _frag '\033[%d;%dH%s' "$1" "$2" "$3"
    _SF_ROW_CURR[$1]+="$_frag"; _SF_DIRTY_ROWS[$1]=1
}
```

### Flush

```bash
shellframe_screen_flush() {
    local _row

    # Erasure: rows in PREV but not written this frame
    for _row in "${!_SF_ROW_PREV[@]}"; do
        [[ -z "${_SF_ROW_CURR[$_row]+x}" ]] && _SF_DIRTY_ROWS[$_row]=1
    done

    for _row in "${!_SF_DIRTY_ROWS[@]}"; do
        local _curr="${_SF_ROW_CURR[$_row]:-}"
        local _prev="${_SF_ROW_PREV[$_row]:-}"
        if [[ "$_curr" != "$_prev" ]]; then
            if [[ -z "$_curr" ]]; then
                printf '\033[%d;1H\033[0m%*s' "$_row" "$_SF_FRAME_COLS" '' >&3
                unset '_SF_ROW_PREV[$_row]'
            else
                printf '\033[0m%s' "$_curr" >&3
                _SF_ROW_PREV[$_row]="$_curr"
            fi
        fi
    done
    _SF_DIRTY_ROWS=()
}
```

Properties:
- O(dirty_rows) string comparisons, one `printf` per changed row
- Erasure: rows in PREV but absent from CURR are cleared and unset
- `\033[0m` prefix resets attributes to prevent bleed from prior row
- Fragments self-position via embedded cursor escapes

### screen_clear

```bash
shellframe_screen_clear() {
    printf '\033[H\033[3J\033[2J' >&3
    _SF_ROW_CURR=(); _SF_ROW_PREV=(); _SF_DIRTY_ROWS=()
}
```

## Editor Integration

The editor's deferred-write mechanism (`_SHELLFRAME_EDITOR_DEFERRED_BUF`) exists
because the cell-level framebuffer's erasure pass overwrote editor content that was
written directly to fd 3. With row-level storage, the editor writes per-row
positioned fragments to `_SF_ROW_CURR` like every other widget. The erasure problem
disappears because the row string comparison detects content correctly.

Changes:
- **Framebuffer path**: Instead of accumulating `_buf` and deferring, write each
  row's content as framebuffer calls during the per-row loop. Each iteration:
  `shellframe_fb_fill` for background clear, then build the row's positioned ANSI
  content string (cursor highlight, text, padding) and append it directly to
  `_SF_ROW_CURR[$screen_row]` with `_SF_DIRTY_ROWS[$screen_row]=1`. This is a
  raw append — the editor's content is already cursor-positioned, so it does not
  go through `fb_print_ansi` (which would add redundant positioning).
- **DIRECT_RENDER path**: Unchanged — still builds `_buf` and writes to fd 3.
- **Remove**: `_SHELLFRAME_EDITOR_DEFERRED_BUF` global, its init in
  `shellframe_fb_frame_start`, and the deferred-write block in
  `_shellframe_shell_draw` (shell.sh).

## Files Changed

| File | Change |
|------|--------|
| `src/screen.sh` | Replace cell arrays with row arrays; rewrite `fb_*` functions + `screen_flush` + `screen_clear` + `fb_frame_start`; remove deferred buf init |
| `src/widgets/editor.sh` | Framebuffer path writes per-row fragments; remove deferred buf accumulation |
| `src/shell.sh` | Remove deferred-write block after `screen_flush` |
| `tests/unit/test-screen.sh` | Rewrite framebuffer assertions for row model |
| Other test files | Update assertions that inspect `_SF_FRAME_CURR`/`_SF_FRAME_PREV` |

No changes to: widget render functions (same API), standalone TUIs (alert, confirm,
action-list, table), input.sh, hitbox.sh, or other non-framebuffer code.

## Performance

For a 50×10 grid with ~15 chars/cell:

| Metric | Before | After |
|--------|--------|-------|
| Write-side bash iterations | ~13,500 (per char) | ~500 (per fb_* call) |
| Flush printf syscalls | ~7,500 (per cell) | ~50 (per row) |

## Trade-offs

- Row string comparison is byte-for-byte on potentially long strings — but bash
  string comparison is a C-level `memcmp`, negligible cost.
- If widget render order changes between frames without visual change, row strings
  differ and cause a false re-emit. In practice, render order is deterministic.
- Slightly more terminal bytes per row (cursor positioning per fragment) but far
  fewer syscalls. Terminal I/O throughput easily absorbs the extra bytes.
- A row with one changed cell rewrites the full row — but one 200-byte `write()`
  is far cheaper than 200 individual cursor-position writes.
