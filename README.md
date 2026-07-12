# PulseGlass

A native iOS 26 client for **PostHog Web Analytics** — a Liquid Glass dashboard app plus a Home Screen / Lock Screen widget that answers *"How many visitors in the last 7 days, and where are they from?"*

Read-only by design: PulseGlass never captures events or writes anything to your PostHog project.

| | |
|---|---|
| Platforms | iOS 26.0+ (Liquid Glass baseline) |
| Stack | Swift 6, SwiftUI, WidgetKit, Swift Charts, MapKit, App Intents |
| Backend | PostHog Cloud US/EU or self-hosted, via the documented REST API (`weekly_digest` + HogQL `/query`) |

## What's in the box

```
PulseGlass/
├── project.yml               # XcodeGen manifest (source of truth for the project)
├── PulseGlass.xcodeproj      # Generated Xcode project — just open this
├── AnalyticsKit/             # Shared Swift package: client, models, caching, stores
│   ├── Sources/AnalyticsKit/
│   └── Tests/AnalyticsKitTests/   # 65 unit tests
├── App/                      # The app target (Dashboard · Regions · Settings + onboarding)
└── Widget/                   # WidgetKit extension (6 families, AppIntent configuration)
```

- **App** — overview tiles (visitors, pageviews, sessions, bounce rate, avg session duration with period-over-period deltas), a visitors/pageviews trend chart with scrubbing, top pages & sources, and a Regions view (world map + country/city breakdowns with device splits and an "unknown locations" reconciliation row, in an inline expandable panel so the tab bar stays visible). The Liquid Glass tab bar is persistent on every tab.
- **Widget** — `systemSmall/Medium/Large` + `accessoryCircular/Rectangular/Inline`: 7-day visitor count, delta, sparkline, top cities/countries with device splits. Configurable per instance (profile + locations shown) via long-press → Edit Widget.
- **AnalyticsKit** — one shared data layer for both processes: an `actor` HTTP client with single-flight coalescing and retry/backoff, defensive DTO decoding, HogQL query builders, a server-cache-aware refetch gate, Keychain credential custody, and App Group snapshot storage.

## Requirements

- **Xcode 26** or newer (the app uses iOS 26 Liquid Glass APIs: `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`).
- An **iOS 26 simulator** (installed with Xcode) or an iOS 26 device.
- Nothing else — the Xcode project is checked in. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is only needed if you change `project.yml` (then run `xcodegen generate`).

## Run it in Xcode

1. Open `PulseGlass.xcodeproj`.
2. Select the **PulseGlass** scheme and an iPhone simulator running **iOS 26** (e.g. *iPhone 17 Pro*).
3. Press **⌘R**.

The simulator needs no code-signing setup. To run on a **physical device**, select your development team in *Signing & Capabilities* for both the `PulseGlass` and `PulseGlassWidgetExtension` targets, and change the bundle identifiers, App Group (`group.com.example.pulseglass`), and keychain access group (`com.example.pulseglass.shared`) to values available to your team (they appear in `project.yml` and the two `.entitlements` files).

### Trying it without a PostHog account

On first launch you'll see the **Connect PostHog** sheet. Tap **"Explore with sample data"** at the bottom — the app switches to an in-memory demo profile with bundled sample data so you can tour the Dashboard, Regions, and Settings. *Sign out* in Settings exits demo mode.

(For UI automation the same thing is available as launch arguments: `-pulseglass-demo`, and `-pulseglass-url "pulseglass://regions"` to deep-link at launch.)

### Connecting a real PostHog project

1. In PostHog, create a **personal API key**: *Settings → Personal API keys → Create key*. Follow least privilege and scope it to **`web_analytics:read`** and **`query:read`**. Optional extras: `project:read` + `organization:read` enable the in-app project picker (otherwise you type the project ID manually), and `user:read` lets the app show which account the key belongs to. The app works fine without the optional scopes — a 403 from the identity endpoint during validation is treated as "valid but tightly scoped", not an error.
2. In PulseGlass, pick your host — **PostHog Cloud US** (`us.posthog.com`), **PostHog Cloud EU** (`eu.posthog.com`), or your self-hosted HTTPS URL. Private API keys are region-bound: a US key won't work against the EU host.
3. Paste the key and tap **Connect**. The app validates it (`GET /api/users/@me/`), then lets you pick a project — or type the numeric project ID manually if the key can't list projects.
4. A smoke test (one `weekly_digest` call + one 1-row HogQL query) runs, and you land on the live dashboard.

The key is stored in the **Keychain only** (shared access group so the widget can read it); snapshots cached in the App Group container contain aggregates only.

### Switching or adding connections

PulseGlass supports multiple connections (host + key + project). To point the app at a different PostHog project or dashboard:

- Tap the **person icon** in the Dashboard's top-right toolbar → pick a connection, or **Add connection…** to run the connect flow again; or
- Go to **Settings → Connections**: tap a connection to make it active, **Test** to validate it, swipe to delete, or **Add connection**.

A newly added connection becomes active immediately, and switching clears the previous project's data before loading the new one. Each widget instance picks its own connection independently (long-press → Edit Widget → Profile).

### Adding the widget

1. Run the app once and connect a profile (the widget reads credentials from the shared Keychain group).
2. Long-press the Home Screen → **Edit** → **Add Widget** → search *PulseGlass*.
3. Pick a family. Long-press the widget → **Edit Widget** to choose the **Profile** and **Locations shown** (Cities / Countries / Mixed).
4. Lock Screen: long-press the Lock Screen → **Customize** → add the circular, rectangular, or inline accessory widget.

The widget refreshes on a ~2-hour cadence (well inside the WidgetKit budget), falls back to the last-good snapshot when offline or rate-limited (dimmed, with a stale badge), and reloads immediately after the app itself fetches fresh data.

## Tests

65 unit tests cover DTO decoding against captured fixtures (including partial payloads and unknown enum values), byte-for-byte HogQL snapshot tests (PostHog's query cache keys on exact SQL text), the client's error matrix (401/403/429/400/offline) and single-flight coalescing via a mock transport, city/country folding, the cache-refetch gate, widget timeline planning, formatting, and deep-link allowlisting.

Run them any of these ways:

```sh
# fastest (macOS host, no simulator)
cd AnalyticsKit && swift test

# on the iOS simulator
cd AnalyticsKit && xcodebuild test -scheme AnalyticsKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0'
```

or in Xcode: open the project, select the **AnalyticsKit** scheme, and press **⌘U**.

## Design notes

- **API surface**: only documented PostHog endpoints — `web_analytics/weekly_digest/` for the overview tiles/top lists (deltas computed server-side) and `POST /query` with `HogQLQuery` for trend/geo/device breakdowns. Internal query kinds (`WebOverviewQuery`, …) are deliberately not used.
- **Rate-limit citizenship**: server `cache_target_age` is honored per query, a 5-minute client TTL floors refetches, identical concurrent requests are coalesced, 429s are never retried in-session (cached data + a banner instead). Worst case is well under 100 requests/day/device against a 2,400/hour team budget.
- **Liquid Glass discipline**: glass is reserved for functional chrome (range picker, chart scrub readout, floating refresh, the Regions mode switcher, onboarding CTA); stat cards, charts, lists, and the map are content on standard materials. One `GlassEffectContainer` per screen.
- **Error handling**: invalid key / missing scope / wrong region / rate limit / HogQL error / GeoIP-disabled / offline each have a distinct, non-fatal UX in both app and widget (see `AppModel.handle(error:endpoint:)` and the Regions empty state).
