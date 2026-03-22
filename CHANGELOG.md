# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
## [Unreleased]

### Added
- Dirty-region rendering — skip screen_clear on cursor movement
- Dirty-region rendering — skip screen_clear on cursor movement
- Dirty-region rendering — skip screen_clear on button toggle
- Add SHELLFRAME_PANEL_MODE=windowed inner-bounds support
- Render windowed title bar row in shellframe_panel_render
- Save/restore PANEL_MODE globals; adjust dims and inner bounds for windowed mode

### Fixed
- Remove extra border char from windowed title bar; clarify modal pass-through

### Tab-bar
- Add SHELLFRAME_TABBAR_BG override for inactive tab and fill background
## [0.0.1] - 2026-03-15

