# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
## [0.5.1] - 2026-04-04

### Fixed
- Hide grid cursor highlight when unfocused (#40)
## [0.5.0] - 2026-04-03

### Added
- Intercept Ctrl+Q globally before focus dispatch

### Fixed
- Don't apply stripe background to empty rows below data
- Disable XON/XOFF flow control in raw mode (-ixon)
## [0.4.0] - 2026-04-03

### Added
- Add SHELLFRAME_PANEL_CELL_ATTRS for per-cell border background
- Mouse-driven screen transitions + modifier key decoding
- Add mouse support for button clicks
- Add shellframe_toast_show/tick/render widget (shellframe#37)
- Add multi-field form widget with Tab traversal and scroll (shellframe#36)
- Add module with attach/detach and prefix extraction (shellframe#38)
- Add provider invocation and popup activation (shellframe#38)
- Add on_key with accept/dismiss/navigate/filter (shellframe#38)
- Add render with cursor-anchored popup positioning (shellframe#38)
- Add example and integration tests (shellframe#38)
- Module scaffold — state globals + push/pop/active API
- Module scaffold — state globals + push/pop/active API
- Shellframe_sheet_draw — registry swap + frozen rows + region dispatch
- Shellframe_sheet_on_key — Esc/Up dismiss, Tab focus cycle, action dispatch
- Wire shell.sh draw + key delegation; source sheet.sh
- Two-step wizard example + integration tests
- Merge feat/sheet — sheet navigation primitive (shellframe#27)

### Changed
- Row-based framebuffer — O(1) writes, O(rows) flush (shellframe#39)
- Migrate to row-based framebuffer API

### Fixed
- Defer fd3 write past screen_flush to prevent FB erasure
- Release events no longer dismiss context menu
- Wire tick into draw loop; add theme-overridable toast colors
- Fire on_focus after focus_init so newly-focusable regions get correct state
- Reset ANSI attributes after border/separator chars to prevent style bleed
- Use case statement for word-char matching; add @ boundary test
- Add framebuffer lifecycle to example for integration tests
- Correct editor-mode line var name; add missing tests
- Reset shell-side globals and _SF_ROW_OFFSET in _reset_sheet test helper
- Save FOCUS_REQUEST in Esc/Tab/Shift-Tab early-return swap-outs; document Tab-reserved
- Correct test-3 assertion (Step 2 not Step 1); document submit dirty-state pattern
## [0.3.0] - 2026-03-26

### Added
- Framebuffer diff rendering — Phase 7F (#33) (#35)
## [0.2.0] - 2026-03-26

### Added
- Add dirty-region conditional re-render (#30)
- Dirty-region conditional re-render — Phase 7B (#30)
- Add F1–F12, modifier+arrow constants and CSI drain documentation
- Add widget bounding-box registry (#31)
- Add SGR mouse parsing and mouse enable/disable (#32)
- SGR mouse parsing + mouse enable/disable — Phase 7C (#32)
- Mouse routing — click-to-focus, click-to-select, scroll-wheel (#34)
- Mouse routing — click-to-focus, click-to-select, scroll-wheel — Phase 7E (#34)
## [0.1.0] - 2026-03-25

### Added
- Dirty-region rendering — skip screen_clear on cursor movement
- Dirty-region rendering — skip screen_clear on cursor movement
- Dirty-region rendering — skip screen_clear on button toggle
- Add SHELLFRAME_PANEL_MODE=windowed inner-bounds support
- Render windowed title bar row in shellframe_panel_render
- Save/restore PANEL_MODE globals; adjust dims and inner bounds for windowed mode
- Add Worker role section to CLAUDE.md
- Widget skeleton with globals and stubs
- Skeleton + sigil parsing + separator detection
- Implement menubar_init with context-keyed state
- On_focus, size, on_key BAR state
- On_key DROPDOWN state
- On_key SUBMENU state + menubar_open
- Implement shellframe_menubar_render
- Wire into shellframe.sh + add demo example
- Up from BAR releases focus; Up at top of dropdown closes to bar
- Add SHELLFRAME_DIM color constant
- Per-column alignment + inline cell render (no subshell forks)
- Add SHELLFRAME_GRID_STRIPE_BG and CURSOR_STYLE globals
- Add SHELLFRAME_GRID_BG for base row background color
- Add SHELLFRAME_GRID_HEADER_STYLE for custom header colors
- Add SHELLFRAME_LIST_BG for custom list background color
- Add SHELLFRAME_EDITOR_BG; reduce Esc timeout to 50ms
- Add SHELLFRAME_GRID_HEADER_BG for header row background

### Fixed
- Remove extra border char from windowed title bar; clarify modal pass-through
- Add permissions: contents: write to release workflow caller
- Bind height param, validate menu names, guard empty array, dedup open_dropdown
- Handle missing brew in bootstrap and auto-detect sibling ptyunit (#28)
- Preserve GRID_BG through separator resets; add LIST_CURSOR_STYLE
- Use per-row bg reset on striped rows
- Fill cursor row with cursor bg to eliminate cell gaps
- Header ellipsis inherits header color style

### Tab-bar
- Add SHELLFRAME_TABBAR_BG override for inactive tab and fill background
## [0.0.1] - 2026-03-15

