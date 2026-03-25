# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
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

