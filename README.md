# News Scanner — iOS

A native iOS port of the News Scanner browser extension. It periodically queries
**Google News RSS** for your topics, dedupes results, and notifies you when a
genuinely new article appears. It also shows the **current temperature and
weather** for your location and **flags extreme temperatures**, and can scan
**local news** for where you are at any of four geographic levels.

This is the **opportunistic on-device** model from
[`APPLE_APP_PORT.md`](../APPLE_APP_PORT.md) §2: no backend, no database, no server.
All data lives on the device.

## Requirements

- **Xcode 16 or later** (the project uses the modern file-system-synchronized
  project format, `objectVersion = 77`).
- iOS **17.0+** deployment target.
- An Apple Developer account is **not** required for the Simulator. To run on a
  physical device, set your signing team (see below).

## Open & run

```sh
open NewsScanner.xcodeproj
```

1. Select the **NewsScanner** scheme and an iOS 17+ Simulator (e.g. iPhone 15).
2. Press **⌘R**.

To run on a real iPhone: select the target → **Signing & Capabilities** → set
**Team** to your Apple ID. Bundle id is `com.newsscanner.app` (change it if it
collides). Allow notifications when prompted.

### Using an older Xcode (15 or earlier)?

The project format needs Xcode 16. If you're on 15, create a fresh app and drop
the code in:

1. Xcode → **New → Project → iOS App** (SwiftUI, name it `NewsScanner`).
2. Delete the generated `ContentView.swift` / `*App.swift`.
3. Drag everything inside the **`NewsScanner/`** folder into the project
   ("Copy items if needed", add to the app target).
4. In target settings, set the **Info.plist** to `NewsScanner-Info.plist`, or add
   these keys to the generated Info.plist: `UIBackgroundModes = [fetch]`,
   `BGTaskSchedulerPermittedIdentifiers = [com.newsscanner.app.refresh]`, and
   `NSLocationWhenInUseUsageDescription` (any descriptive string).

## How it works

| Concern | Implementation |
|--------|----------------|
| Storage | `Store` → `Codable` snapshot saved to a JSON file in **Application Support**. No database. |
| Feed URL | `FeedURLBuilder` → `https://news.google.com/rss/search?q=…&hl=en-US&gl=US&ceid=US:en` |
| Fetch | `URLSession` async/await |
| Parse | `XMLParser` (`RSSParser`) |
| Dedupe | seen-set keyed by a **URL-normalized** link (`LinkKey`, strips `utm_*`/`oc`/`hl`/… and case/slash), capped at 500 (`Caps.seen`) |
| Silent first scan | a new topic's first scan records its backlog as "seen" without notifying |
| Sort | newest-published first, undated last |
| Recent list | capped at 30 (`Caps.recent`) |
| Notifications | `UNUserNotificationCenter`; tap → in-app `SFSafariViewController` |
| Foreground timer | `ContentView` auto-scan loop at the chosen interval |
| Background scan | `BGAppRefreshTask` (`BackgroundScanner`) — **opportunistic** |
| Location | one shared `LocationService` (coalesces + caches a single fix + geocode for weather *and* local news) over `LocationProvider` |
| Local news | `LocalNewsManager` reverse-geocodes the fix → scans per enabled scope (`LocationScope`) |
| Weather | `WeatherService` → **Open-Meteo** (`api.open-meteo.com`), keyless, no account |
| Extreme flag | heat ≥ 35°C; cold is **graduated** into 5 bands (`ColdLevel`), coldest wins |
| Units | locale-aware °C/°F (`TempFormat`) — Fahrenheit in US locales |

## Weather & extreme-temperature alerts

On launch (and on manual/pull-to-refresh) the app requests a one-shot location
fix, reverse-geocodes it to a place name, and fetches current conditions from
**Open-Meteo** — a free, **keyless** API, so nothing about the on-device,
no-backend model changes. Results are held in memory only; nothing is persisted.

When a reading crosses a threshold, the Weather section shows a colored banner and
the app posts a one-off local notification. The **Flag extreme temperatures**
toggle (persisted in `AppSettings`) controls both.

Heat is a single band (≥ 35°C). **Cold is graduated** into five severity bands
(`WeatherService.ColdLevel`), with thresholds and frostbite guidance following
Environment Canada wind-chill risk levels — so a −7°C morning and a −50°C
Prairie cold snap surface very differently (color ramps blue → near-black, and a
`LEVEL n/5` gauge shows where the reading sits):

| Band | Triggers at | Guidance |
|------|-------------|----------|
| Cold | ≤ −6°C (21°F) | Dress warmly |
| Very cold | ≤ −18°C (0°F) | Cover exposed skin; frostbite in ~30 min |
| Extreme cold | ≤ −30°C (−22°F) | Frostbite in 10–30 min |
| Severe cold | ≤ −40°C (−40°F) | Frostbite in 5–10 min |
| Life-threatening | ≤ −48°C (−54°F) | Frostbite in under 5 min |

The notification is de-duped until conditions normalize, but an **escalating band**
(e.g. very cold → severe cold) re-alerts.

Requires the `NSLocationWhenInUseUsageDescription` key (already in
`NewsScanner-Info.plist`). In the Simulator, set a location via **Features →
Location**, or from the CLI:

```sh
xcrun simctl location booted set 29.3759,47.9774     # Kuwait City — triggers the heat flag
xcrun simctl location booted set -78.4645,106.8339   # Vostok, Antarctica — life-threatening cold (winter)
```

## Local news

The **Local news** section scans Google News for wherever the device is, at any of
four geographic levels you toggle on (`WeatherService`/`LocalNews.swift`,
`LocationScope`):

| Scope | Resolved from `CLPlacemark` | Example (Sibagat, PH) |
|-------|-----------------------------|------------------------|
| Community | `subLocality` | Tag-uyango |
| City / Municipality | `locality` (or `subAdministrativeArea`) | Sibagat |
| Region / Province | `administrativeArea` | Caraga |
| Country | `country` | Philippines |

Each enabled scope becomes an **auto-managed topic** (`Topic.scope`), qualified
with the next-broader name to reduce ambiguity (e.g. community → `"Tag-uyango,
Sibagat"`). `LocalNewsManager` reconciles these against the enabled scopes and the
current place — turning a scope off, or moving to a new place, removes the stale
managed topics and adds the new ones. They ride the **same scan/seed/dedupe
pipeline** as user topics, so local matches appear in Recent matches; they're
hidden from the manual Topics list (`Store.userTopics`). Enabled scopes persist in
`AppSettings.localScopes`.

> Note: each topic and each local-news scope keeps its **own** recent-matches cap
> (`Caps.recent`, 30, applied per query in `enforceCapsAndSave`), so topics never
> starve each other. Each appears as its own results section, capped inline to the
> user's **Results shown** preference (`AppSettings.resultsPerSection`, 1–3, set
> from the schedule dropdown) with the rest behind "View all".

## Important: background timing on iOS

iOS does **not** allow fixed-interval polling in the background. Your chosen
frequency (1 min / 5 min / hourly / daily / custom) is honored **exactly only
while the app is open**. In the background, `BGAppRefreshTask` is *opportunistic*:
the system decides when to run it, often only every few hours, and never
guarantees it. For time-sensitive alerts you'd need the server + APNs model
(`APPLE_APP_PORT.md` §2, option 1) — not built here.

### Testing background refresh

Background refresh rarely fires on demand. To force it in the debugger, pause and
run in the LLDB console:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.newsscanner.app.refresh"]
```

## Project layout

```
NewsScannerApp/
├─ NewsScanner.xcodeproj/
├─ NewsScanner-Info.plist          # background mode + BG task id + location usage
├─ README.md
└─ NewsScanner/                    # all Swift source (auto-synced into the target)
   ├─ NewsScannerApp.swift         # @main, BG task registration, scene phase
   ├─ DataModels.swift             # Codable models + on-device Store
   ├─ AppSettings.swift            # schedule presets (UserDefaults) + AppRouter
   ├─ FeedService.swift            # URL builder + XMLParser RSS parser
   ├─ ScanService.swift            # scan loop: fetch/dedupe/sort/seed/notify
   ├─ NotificationManager.swift    # UNUserNotificationCenter + tap routing
   ├─ BackgroundScanner.swift      # BGAppRefreshTask scheduling
   ├─ LocationProvider.swift       # async one-shot CoreLocation wrapper
   ├─ LocationService.swift        # shared, coalesced location+geocode for all features
   ├─ LinkKey.swift                # URL normalization for dedupe keys
   ├─ WeatherService.swift         # Open-Meteo fetch + WMO mapping + thresholds
   ├─ WeatherManager.swift         # location → geocode → weather + extreme alerts
   ├─ WeatherView.swift            # Weather section + extreme banner + toggle
   ├─ LocalNews.swift              # LocationScope + PlaceContext + LocalNewsManager
   ├─ LocalNewsView.swift          # Local news section (per-scope toggles)
   ├─ ContentView.swift            # main screen + foreground scan loop
   ├─ ScheduleView.swift           # frequency picker
   ├─ RecentMatchesView.swift      # results list + share/export/clear
   ├─ SafariView.swift             # SFSafariViewController wrapper
   └─ Assets.xcassets/

NewsScannerTests/                 # unit tests (logic: LinkKey, RecencyWindow, RSSParser, …)
```

## Tests

Unit tests cover the pure, bug-prone logic — dedupe-key normalization (`LinkKey`),
the recency window, RSS parsing, the graduated cold bands, and match sorting:

```sh
xcodebuild test -project NewsScanner.xcodeproj -scheme NewsScanner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

> `ScanService` (seeding/dedupe orchestration) isn't unit-tested yet — it reaches
> `Store.shared` directly, so testing it cleanly needs dependency injection. The
> `LinkKey` tests cover the dedupe *key* logic that change relies on.

## Not included (future parity)

- Server + APNs push for reliable background alerts.
- iCloud/CloudKit sync of topics across devices.
- Per-topic keyword excludes, badge counts.

## Disclaimer & personal use

This app is an independent, **personal-use** news reader. It is **not affiliated
with, endorsed by, or sponsored by Google**. It reads the public **Google News RSS**
feed on-device for the user's own personal, non-commercial use, and links out to
the original publisher's site for each article (it does not republish full article
text). Each user's device fetches its own feed — there is no server that collects
or redistributes content.

Use of Google News is subject to Google's
[Terms of Use](https://www.google.com/intl/en_us/terms_google_news.html), which
permit **personal, non-commercial use**. You are responsible for your own
compliance. Do not use this project to build a commercial or ad-supported service,
to run a central backend that redistributes Google News content, or with Google's
trademarks/logos.

## Attribution

- **Weather data** by [Open-Meteo](https://open-meteo.com/), licensed under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- **News** via the public Google News RSS feed (see Disclaimer above).

## License

[MIT](LICENSE) — see the `LICENSE` file. Replace the copyright holder with your
own name before publishing if you wish.
