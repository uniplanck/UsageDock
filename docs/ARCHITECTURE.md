# UsageDock Architecture

## Product goal

UsageDock is a native macOS edge rail for live AI-product quota visibility. It is intentionally lightweight, non-activating, and glanceable: the rail stays at the left or right edge without stealing focus, while provider details appear only on hover or explicit account/settings actions.

## Provider model

The canonical hierarchy remains:

`Provider -> Account -> UsageBucket`

Current providers:

- Claude: live current-session and credential-file usage.
- Codex / OpenAI: live current-session and credential-file usage.
- Kimi: Kimi Code OAuth current-session and credential-file usage.
- Gemini: branded UI/provider slot exists; live quota acquisition is not connected yet.

A `UsageBucket` represents one independently enforced quota window or pool, for example:

- 5 hour rolling window
- weekly / 7-day window
- model-specific quota such as Fable
- extra usage / credits
- provider-defined custom windows

The UI never collapses unlike windows into one mathematically meaningless percentage. The compact rail shows the highest observed pressure for a provider; the hover detail panel shows the individual quota rows.

## Aggregation contract

UsageDock distinguishes three aggregation states:

1. `exact`: every participating bucket has compatible absolute `used`, `limit`, and unit. Aggregate = `sum(used) / sum(limit)`.
2. `unweightedAverage`: exact capacity weighting is impossible but percentages exist. This fallback is explicitly labeled and is never represented as an exact total capacity percentage.
3. `unavailable`: compatible information is insufficient.

Aggregation is scoped to the same quota identity/window. 5h, weekly, Fable/model-specific, credits, and unrelated custom windows remain independent.

## Edge rail interaction

The main rail is rendered by SwiftUI inside a borderless AppKit `NSPanel`.

Required window behavior:

- `.borderless` + `.nonactivatingPanel`
- `.floating` level
- joins all Spaces
- `.fullScreenAuxiliary`
- does not become main/key window
- persisted left/right placement
- repositions on display parameter changes

The rail is a dark glass surface with provider-branded vector icons, gradient pressure rings, hover glow, subtle material/border/shadow treatment, and compact percentage chips.

### Placement context rule

The context menu never shows a no-op placement choice:

- while docked right, only `Move to Left` is shown;
- while docked left, only `Move to Right` is shown.

The same inverse-only rule is used in the menu-bar menu.

## Hover detail panel

Hovering a provider row opens a second borderless, non-activating `NSPanel` rather than a normal activating popover.

The detail panel:

- never steals focus;
- ignores mouse events so the source rail owns hover lifetime;
- opens inward from the screen edge: left of a right rail, right of a left rail;
- aligns vertically to the hovered row and clamps to the visible screen;
- shows provider name/icon, live status, provider pressure, account count, reset countdowns, and up to six aggregated quota rows;
- renders dynamic labels such as `5h`, `1w`, Fable/model-specific labels, and provider custom/extra pools.

Because detail rows are driven by `UsageAggregate`, Claude Fable and future provider/model windows appear without hard-coding them into the rail UI.

## Context menu, Settings, and account management

Right-clicking the rail exposes:

- `Settings…`
- `Accounts` submenu
  - `Add Current Login` when a supported local provider login is discoverable
  - provider profile login where supported
  - account `Edit…`
  - account `Delete`
- inverse-only edge movement
- `Refresh Now`

Settings is owned by a retained AppKit `SettingsWindowController`; the app no longer depends on a selector being routed into SwiftUI's implicit Settings scene. Both the rail context menu and menu-bar Settings action call the same controller, which activates the app and makes the concrete settings window visible/frontmost.

`Edit…` opens that settings window, where account name, enabled state, multiplier controls, display overrides, ordering, and delete remain available.

## Brand asset boundary

Provider marks are bundled in `Assets.xcassets` as vector SVG image sets:

- Claude
- OpenAI for Codex
- Google Gemini
- Kimi

`ProviderBrand` owns asset lookup plus provider accent gradient/glow presentation. Business/domain code does not depend on visual asset names.

## Persistence and credential boundary

`PlacementStore` persists the edge in `UserDefaults`.

`UsageStore` persists only non-secret account metadata such as:

- account UUID/provider/name
- enabled state
- authenticated account source (`currentSession` or `profile`)
- profile metadata paths created by UsageDock's authenticated profile-login flow
- per-account plan multiplier and manual/automatic mode
- per-provider Fusion-mode preference
- last cached non-secret quota buckets

UsageDock does **not** copy provider access tokens or refresh tokens into its preferences and does not own refresh-token rotation.

A discovered local provider credential is **not** automatically registered as a UsageDock account. `Add Current Login` is an explicit user action. Additional profiles are created only through the supported provider login flow. Unsupported legacy account-source values are discarded during migration while valid login-backed records are preserved.

## Plan multiplier contract

Claude and Codex accounts may carry a numeric plan multiplier from ×1 through ×999.

- Manual mode: the user types the multiplier directly in Settings.
- Auto mode: UsageDock inspects only non-secret plan/tier metadata already encoded in provider-owned credential metadata. It accepts a numeric multiplier only when metadata explicitly encodes a value such as ×5 or ×20.
- Ambiguous plan names are never guessed into numeric multipliers. For example, a Codex plan label such as `prolite` can be reported but is not silently mapped to ×5/×20.

The compact provider ring displays the resolved multiplier in a bottom-right `×N` badge. In normal mode the provider badge uses the largest enabled account multiplier. In Fusion mode enabled account multipliers are summed, so two enabled ×20 accounts render ×40.

## Live provider adapters

All acquisition conforms to `UsageProviderAdapter` and returns domain `UsageAccount` values.

### Claude

The Claude adapter resolves the official local Claude OAuth credential, queries the usage endpoint, and parses both legacy named windows and newer `limits` rows. Supported result shapes include 5h, weekly, model-scoped/Fable, and future dynamically identified windows.

### Codex / OpenAI

The Codex adapter resolves the official ChatGPT/Codex auth state and queries the Codex usage endpoint. Primary/secondary/additional model rate-limit windows are converted dynamically into domain buckets rather than assuming every account has one fixed 5h + 1w pair.

### Kimi

The Kimi adapter integrates with Kimi Code credentials without taking ownership of them.

Current-session resolution:

1. read `~/.kimi-code/config.toml`;
2. resolve the managed Kimi provider base URL and OAuth credential key;
3. read the referenced credential JSON from `~/.kimi-code/credentials/`;
4. use its access token only in memory for the request;
5. never persist or rotate that token inside UsageDock.

The adapter targets the managed Kimi coding usage surface and parses:

- weekly/top-level usage summary;
- provider `limits` rows including rolling 5h windows;
- reset times;
- optional extra-usage/credit limits.

The parser accepts provider numeric fields encoded as either JSON numbers or strings and derives window labels from duration + time unit.

A direct token-bearing Kimi live probe is intentionally not part of automated verification in this environment. The local credential structure is inspected without exposing token values, while usage parsing is covered by a non-secret fixture test.

### Gemini

Gemini is present in the domain and branded UI, but live quota acquisition remains intentionally unimplemented until a stable supported account-level quota source is selected.

## Refresh and failure semantics

`UsageStore` refreshes only explicitly registered login-backed accounts (`currentSession` or `profile`) for providers with a live usage adapter. Unsupported providers remain idle.

Provider state can be:

- idle
- refreshing
- live
- partial
- failed

Authentication/credential failures clear stale live buckets where appropriate. Transient HTTP or response failures do not silently replace usage with zero, and UsageDock never fabricates provider-authenticated utilization.

## Verification contract

F12 acceptance requires:

- XcodeGen project generation succeeds;
- asset catalog compiles and links;
- all app Swift sources compile for arm64 macOS;
- app and XCTest bundle link;
- unit tests pass for aggregation, placement persistence, login-backed account persistence/migration, multiplier normal/Fusion semantics, Claude parser, Codex dynamic windows, and Kimi weekly/5h/extra usage parsing;
- a focused AppKit regression test proves `SettingsWindowController.show()` makes the concrete settings window visible;
- source inspection confirms main and hover panels remain non-activating;
- source inspection confirms context placement is inverse-only;
- `git diff --check` and scoped whitespace checks pass;
- the latest built app launches successfully and persisted F12 account migration can be inspected without exposing credential values.

Automated pixel-level native visual QA is a separate environment capability and is not required to claim source/build/test acceptance.
