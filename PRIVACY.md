# Privacy Policy — News Scanner

**Last updated: June 10, 2026**

News Scanner ("the app") is an independent, personal-use iOS app. It is designed
to keep your data **on your device**. The developer does **not** operate a server,
does **not** have user accounts, and does **not** collect, store, sell, or share
your personal information. There is no analytics SDK, no advertising, and no
cross-app tracking.

## What stays on your device

The following are stored only in the app's private storage on your iPhone and are
never transmitted to the developer:

- Your **topics** (search keywords) and per-topic settings (recency filters, etc.).
- The **matches** (article titles, links, sources, dates) the app has surfaced.
- App **settings** (scan schedule, results-per-section, local-news scopes,
  extreme-temperature flag).
- Your **location is not stored**; it is used transiently to fetch weather and
  local news, then discarded.

## What leaves your device, and to whom

To do its job, the app makes network requests directly from your device to the
following third parties. The developer never sees these requests.

| Data sent | Sent to | Purpose |
|-----------|---------|---------|
| Your topic keywords (and, for local news, your area's place name) | **Google News** (`news.google.com` RSS) | Fetch matching news headlines/links |
| Your approximate coordinates | **Open-Meteo** (`open-meteo.com`) | Fetch current weather for your location |
| Your coordinates | **Apple** (via the operating system's geocoder) | Convert your location into a place name (city/region/country) |

The app shows article **headlines and links** and opens the full article on the
**publisher's own website** in an in-app browser; it does not republish full
article text.

These third parties have their own privacy policies:

- Google: <https://policies.google.com/privacy>
- Open-Meteo: <https://open-meteo.com/en/terms>
- Apple: <https://www.apple.com/legal/privacy/>

## Location

The app requests **"When In Use"** location access only to show your local
temperature/weather and to scan local news for your area. You can decline, and the
app continues to work without those features. Location is used transiently and is
not stored or sent to the developer.

## Notifications

Notifications about new articles or extreme temperatures are generated **locally on
your device**. No push server is involved.

## Children

The app is not directed to children and does not knowingly collect any information
from anyone, including children under 13.

## Changes

This policy may be updated; the "Last updated" date above will change accordingly.

## Contact

Questions or concerns: please open an issue at
<https://github.com/kievG/NewsScanner/issues>.
