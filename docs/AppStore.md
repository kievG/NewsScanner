# App Store submission guide

Everything needed to publish **News Scanner** free on the App Store. The build is
already pre-flighted (Release builds clean for device; export-compliance is set in
`Info.plist`). The steps below are the ones only **you** can do (they need your
Apple ID / payment / identity).

---

## 0. One-time prerequisites

- [ ] Enroll in the **Apple Developer Program** ($99/yr) — https://developer.apple.com/programs/
- [ ] Enroll in the **Small Business Program** (15% commission) if you ever monetize — https://developer.apple.com/app-store/small-business-program/ (harmless to join now)
- [ ] A Mac with Xcode 16+ (you have this).

## 1. Project signing (the one manual code change)

The project ships with an empty team. In Xcode:

1. Open `NewsScanner.xcodeproj` → select the **NewsScanner** target → **Signing & Capabilities**.
2. Check **Automatically manage signing**.
3. Set **Team** to your Apple Developer team.
4. **Bundle Identifier**: `com.newsscanner.app` — change it if it's taken (e.g. `com.kievg.newsscanner`). It must be globally unique.
   - This sets `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER`, currently blank/`com.newsscanner.app` in `project.pbxproj`.

## 2. Archive & upload

1. Toolbar destination → **Any iOS Device (arm64)**.
2. **Product → Archive**.
3. In the Organizer: **Distribute App → App Store Connect → Upload**.
4. Wait for processing (a few minutes to an hour) in App Store Connect.

> TestFlight first (recommended): after upload, add yourself/testers under
> **TestFlight**. A public link lets up to 10,000 people install the beta with no
> full App Review wait — the fastest way to get it on real phones.

## 3. Create the App Store Connect record

App Store Connect → **Apps → +** → New App:

- Platform: **iOS**
- Name: **News Scanner**  *(must be unique store-wide; if taken, try "News Scanner — Topic Alerts")*
- Primary language: **English (U.S.)**
- Bundle ID: the one from step 1
- SKU: `newsscanner-001` (any internal string)

## 4. Paste-ready metadata

**Subtitle** (≤30 chars):
```
Track topics. Get alerted.
```

**Promotional text** (≤170 chars, editable anytime without review):
```
Add the topics you care about and get a notification the moment a genuinely new article appears — plus local news and weather for where you are.
```

**Description**:
```
News Scanner watches the news for the topics you care about and tells you when something new appears — no doomscrolling required.

HOW IT WORKS
• Add topics (keywords) you want to follow.
• The app scans Google News and surfaces genuinely new articles, skipping duplicates you've already seen.
• Get a push notification the moment something new is published.

FEATURES
• Per-topic results, each in its own collapsible section.
• Recency filters — show only the last X hours, days, weeks, or months, per topic.
• Local news for where you are: community, city, region, or country.
• Current weather and extreme-temperature alerts for your location.
• Share or export your matches.
• Private by design: everything stays on your device. No account, no analytics, no ads, no tracking.

News Scanner is an independent app and is not affiliated with or endorsed by Google. It reads the public Google News RSS feed for your personal use and links out to the original publisher for each article.
```

**Keywords** (≤100 chars, comma-separated):
```
news,alerts,topics,keyword,monitor,tracker,headlines,rss,breaking,local news,notify,watch
```

**Support URL**: `https://github.com/kievG/NewsScanner`
**Marketing URL** (optional): `https://github.com/kievG/NewsScanner`
**Privacy Policy URL**: `https://github.com/kievG/NewsScanner/blob/main/PRIVACY.md`

**Category**: Primary **News**; Secondary **Weather** (or Productivity).

## 5. App Privacy ("nutrition labels")

Answer the **App Privacy** questionnaire in App Store Connect. This app has **no
backend, no accounts, no analytics, no ads, no tracking**. Recommended (accurate,
conservative) answers:

- **Used to track you?** → **No** (no ad networks, no data brokers, no cross-app tracking).
- **Data collected:**
  - **Location → Coarse Location** — purpose: **App Functionality**; **Not** linked to identity; **Not** used for tracking. *(You send approximate coordinates to Open-Meteo for weather and to Apple's geocoder for place names.)*
  - **Search History** — purpose: **App Functionality**; **Not** linked; **Not** tracking. *(Your topic keywords are sent to Google News to fetch results. This is a judgment call — disclosing it is the safe choice since the query leaves the device.)*
  - Everything else → **Not Collected** (no name, email, contacts, identifiers, financial info, usage analytics, etc.).

> You are responsible for the accuracy of these labels. The reasoning: Apple treats
> data **transmitted off the device** as "collected," even without a server of your
> own — so location and the search query are disclosed, but nothing is linked to an
> identity and nothing is used for tracking.

## 6. Age rating

Answer the questionnaire truthfully. Because the app surfaces **unfiltered news**
and opens article links in an in-app browser, expect a **17+** rating (mature/
suggestive themes can appear in news; web links reach arbitrary publisher pages).
Don't claim "Unrestricted Web Access" — it uses an in-app browser scoped to article
links, not a general-purpose browser.

## 7. Export compliance

Already handled: `Info.plist` sets `ITSAppUsesNonExemptEncryption = false` (the app
uses only standard HTTPS). App Store Connect won't ask you each upload.

## 8. Screenshots

Required: **6.9" iPhone** (1320 × 2868 or 1290 × 2796 px), 3–10 images. You can
capture them from the iPhone 17 Pro Max simulator:

```sh
xcrun simctl io booted screenshot shot1.png
```

Good shots: the main screen with a few topics + results, the recency-filter pill
menu, the Local news pills, and the Weather/extreme-temp banner.

## 9. Review notes (paste into "App Review Information → Notes")

```
No account or login is required — the app works immediately.

News Scanner is a personal-use reader of the public Google News RSS feed; it shows
headlines and links and opens full articles on the publisher's own site. It is not
affiliated with Google.

Location permission is optional and used only for local weather and local-news
topics; the app is fully functional if location is denied.

All data stays on the device — there is no server, account, analytics, or ads.
```

## 10. Likely rejection risks for THIS app (and how to clear them)

| Risk | Why | Mitigation |
|------|-----|------------|
| **Guideline 5.2 (IP) — news content rights** | Reviewers sometimes question news aggregators | You link out (don't republish full text), credit publishers, and use the public RSS feed; state this in review notes. The disclaimer is in-app/README. |
| **Guideline 4.2 (minimum functionality)** | "Just an RSS reader" | The topic-monitoring + dedupe + notifications + recency filters + local news + weather is well past a thin wrapper. |
| **Trademark** | Using "Google News" branding | Don't use Google's logos; the name is generic ("News Scanner"); describe the source factually. |
| **Background timing claims** | Don't promise instant background alerts | Marketing copy avoids "real-time/instant background" — iOS background refresh is opportunistic. |
| **Privacy label mismatch** | Labels must match behavior | Use the section-5 answers; they match what the app actually sends. |

## 11. Submit

1. Attach the uploaded build to the version.
2. Fill in all metadata above + screenshots.
3. **Submit for Review**. First reviews are typically 24–48h.

---

### What's already done in this repo
- ✅ Release build verified for device (unsigned pre-flight).
- ✅ `ITSAppUsesNonExemptEncryption = false` in `Info.plist`.
- ✅ App icon (1024px in the asset catalog), launch screen, location usage string.
- ✅ MIT `LICENSE`, `PRIVACY.md`, disclaimer + attribution in `README.md`.
- ✅ Passing unit tests.

### What only you can do
- ⛔ Enroll in the Apple Developer Program ($99/yr).
- ⛔ Set the signing **Team** + unique bundle ID.
- ⛔ Archive, upload, and submit (tied to your Apple ID).
