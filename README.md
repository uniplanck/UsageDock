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

<a href="https://drive.google.com/file/d/1I1TLPKhvvgevAjZ8R0ceHMxTLhVdE_f0/preview">
  <img src="docs/images/usagedock-rail.png" alt="Watch the UsageDock liquid drag motion demo" width="763">
</a>

**▶ [Watch the UsageDock motion demo](https://drive.google.com/file/d/1I1TLPKhvvgevAjZ8R0ceHMxTLhVdE_f0/preview)**

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

- Claude, Codex, Antigravity, Kimi, and Grok can register through supported authenticated login/session flows.
- Cursor remains unavailable until UsageDock has a verified login and live-usage integration for that provider.
- Accounts that are not backed by a supported authenticated login are excluded from the active account set.

Grok uses the official Grok CLI login (`grok login` at auth.x.ai). Link an X subscription to that xAI account first if the allowance comes from X. UsageDock then reads the shared subscription pool from `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` and shows the used percentage, the reset time, and on-demand extra usage when that cap is present. The login token stays in the Grok CLI auth file. Product rows are shares of the same pool, so they are not separate limits. When `creditUsagePercent` is missing on a confirmed usage period and there is no positive monthly allowance, UsageDock shows 0%, which is what the Grok CLI shows: that field is a proto3 number and the API omits zero. The unformatted `/v1/billing` ledger is not a percentage when `monthlyLimit` is 0. The short grok.com query window is a separate browser-cookie surface and is not used.

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
