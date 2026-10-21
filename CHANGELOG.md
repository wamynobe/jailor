# Changelog

All notable changes to Jailor are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.0.1] — 2026-10-21

Initial public alpha.

### Added

- Native macOS workspace manager built with SwiftUI and AppKit.
- Editable layouts and normalized frame system with presets.
- Label/tag classification, per-frame preferred labels, and per-app label memory.
- Drag-and-drop assignment from the sidebar.
- Quick-assign palette with label switching and keyboard frame selection.
- Global hotkeys: `⌃⌥Space`, `⌃⌥1…9`, and `⌃⌥R`.
- Real window tiling through the macOS Accessibility API.
- Workspace reveal with exact-window focus, Dock/Cmd+Tab activation handling, and
  menu bar / Dock menu access.
- Auto restore on launch with optional relaunch of closed applications.
- Fill-empty-frames action.
- **Universal binary (arm64 + x86_64)**, buildable from either Intel or Apple Silicon with Xcode.
- English and Vietnamese UI with English as the default language.
- Live language selector in **Settings → Interface → Language**; no restart required.
- Local JSON persistence under `~/Library/Application Support/Jailor/state.json`.
- English code comments and English source UI strings.
- Bundle identifier `vn.quadbit.jailor`.

### Fixed

- Global hotkeys remain active while the dashboard is hidden by disabling
  automatic/sudden termination, holding a background activity assertion, using
  the Carbon event dispatcher target, and adding a global event-monitor fallback.
- Opening the palette/dashboard/settings no longer triggers an activation reveal
  that could immediately close the UI.
- Multiple windows of the same app no longer steal each other's frames: Jailor
  stores a stable CGWindowID and focuses the exact assigned window.
- Ambiguous legacy assignments now report as missing instead of selecting an
  arbitrary window from the same application.
- Settings label rows no longer render the TextField's "Label name" title as a
  separate label column; names are single-line fields in a fixed 30 pt row.
- Label filter rows and palette chips now use fixed heights and vertical
  centering, so Vietnamese diacritics and mixed label lengths stay aligned.
- The dashboard layout canvas now fills the remaining height and centers the
  screen instead of sitting at the bottom of the window.
- Frame focus/remove buttons have larger hit targets and no longer conflict
  with the card's tap gestures, so the X removes the window assignment.
- Language switching no longer recreates the whole window/settings form; only
  localized views update, so switching is fast and preserves scroll/state.
- The Settings language menu is right-aligned and compact.
- Quick-assign shortcut hints use separate keycaps rather than a single squeezed
  string.
