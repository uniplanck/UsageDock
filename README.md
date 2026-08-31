# UsageDock

UsageDock is a lightweight macOS edge rail for viewing AI service usage and reset timing at a glance. It supports provider/account-level quota presentation, customizable rail layout and styling, and an elastic liquid-style drag interaction for moving the rail between screen edges.

## Public account policy

The supported public distribution is the **Release** build. Account registration is login-only:

- Claude, Codex, Antigravity, and Kimi can register through supported authenticated login/session flows.
- Synthetic, mock, manual, and credential-file account registration is disabled in public Release builds.
- Existing development-only account records are not deleted by a Release build, but they are excluded from public UI, aggregation, and refresh paths.
- Cursor and Grok account registration remains unavailable until UsageDock has a verified login and live-usage integration for those providers.

Development builds may retain internal test tooling, but that tooling is not part of the supported public distribution.

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

Open **Settings → Accounts** and use the provider login controls. Public Release builds do not expose synthetic or manual account creation controls.

## Project structure

- `UsageDock/Domain` — usage models, aggregation, and rail motion runtime
- `UsageDock/Providers` — provider adapters and live usage integrations
- `UsageDock/Storage` — persistent settings/account state
- `UsageDock/UI` — rail and settings UI
- `UsageDock/Window` — AppKit panel/window integration
- `UsageDockTests` — focused unit and behavior tests

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for additional implementation notes.
