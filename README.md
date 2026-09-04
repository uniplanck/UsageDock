<p align="center">
  <a href="README.md"><strong>English</strong></a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md">Español</a>
</p>

# UsageDock

UsageDock is a lightweight macOS edge rail for checking AI service usage and reset timing at a glance. It keeps quota state visible without forcing you into a full dashboard.

## Motion demo

<a href="https://drive.google.com/file/d/1hCO0oAMye-B4IhnjYHwatP7F_iUe9UIo/preview">
  <img src="docs/images/usagedock-rail.png" alt="Watch the UsageDock liquid drag motion demo" width="763">
</a>

**▶ [Watch the UsageDock motion demo](https://drive.google.com/file/d/1hCO0oAMye-B4IhnjYHwatP7F_iUe9UIo/preview)**

## Preview

### Edge rail

<img src="docs/images/usagedock-rail.png" alt="UsageDock edge rail showing live AI usage" width="763">

### Settings

<img src="docs/images/usagedock-settings.png" alt="UsageDock settings window" width="900">

## What it does

- Shows provider/account usage in a compact edge rail.
- Supports up to three selected display accounts with independent menu bar selection.
- Displays rings, percentages, reset timing, provider/account colors, and configurable quota sources.
- Includes left/right edge placement, layout controls, border controls, materials, droplets, and elastic liquid-style drag interaction.
- Provides a compact macOS menu bar status item and popover for selected accounts.
- Persists appearance, placement, display-account, and menu-bar preferences across restarts.

## Account policy

UsageDock is **login-only**.

- Claude, Codex, Antigravity, and Kimi can register through supported authenticated login/session flows.
- Cursor and Grok remain unavailable until UsageDock has a verified login and live-usage integration for those providers.
- Accounts that are not backed by a supported authenticated login are excluded from the active account set.

## Requirements

- macOS 14 or later
- Xcode 16+ recommended

## Build

Release:

```bash
xcodebuild \
  -project UsageDock.xcodeproj \
  -scheme UsageDock \
  -configuration Release \
  -derivedDataPath DerivedDataRelease \
  build
```

Debug:

```bash
xcodebuild \
  -project UsageDock.xcodeproj \
  -scheme UsageDock \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build
```

## Account registration

Open **Settings → Accounts** and use the provider login controls. UsageDock only registers supported authenticated login/session sources.

## Project structure

- `UsageDock/Domain` — usage models, aggregation, and rail motion runtime
- `UsageDock/Providers` — provider adapters and live usage integrations
- `UsageDock/Storage` — persistent settings/account state
- `UsageDock/UI` — rail and settings UI
- `UsageDock/Window` — AppKit panel/window integration
- `UsageDockTests` — focused unit and behavior tests

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for additional implementation notes.
