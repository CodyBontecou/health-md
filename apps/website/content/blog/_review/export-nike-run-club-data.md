# Export Nike Run Club runs claim verification

Verified: 2026-11-27 by Claude (agent), method: traced.

No device run. Nike pages are client-rendered. On 2026-11-27 the connect-to-Health page and the privacy webform page were read; the nike-data-protection page returned only navigation to the fetch tool on repeated attempts. Statements from that page that could not be re-read (seven-day email, identity code, two-year/five-year inactivity policy) were therefore removed from the post.

## Claims

- [x] NRC to Apple Health path (Settings → Privacy & Security → Health → Nike Run Club, choose data) and named data (active energy, heart rate, walking and running distance, workouts; data syncs automatically): https://www.nike.com/help/a/connect-nrc-health-app, read 2026-11-27. The page doesn't mention routes, so the guide makes no route claim.
- [x] Download Your Data path (Account Settings → Privacy → Download Your Data → Request Data): research brief, and consistent with a third-party guide (https://takeoutday.org/guides/how-to-export-nike-run-club-data) and the Nike privacy webform's mention of data export requests. The post links Nike's article for timing and identity checks and states no seven-day figure, identity code or retention periods; archive formats not described. "No per-run export documented" is worded as about Nike's help pages only.
- [x] Webform for delete/correct/export requests: https://www.nike.com/help/privacy, read 2026-11-27.
- [x] Apple export.zip path and workout-routes GPX: https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios; routes as GPX per `_review/export-apple-health-workouts.md` (Apple Fitness refresh entry).
- [x] Health.md steps (Workouts in Health Metrics, CSV/JSON, Summary, start-day selection, folder, Preview), CSV rows-are-not-sessions, JSON per-session objects, reads only Apple Health, no GPX/FIT/TCX, no recovery of unsaved workouts, no direct app connection: existing entries in `_review/export-apple-health-workouts.md`. No new product claims. Nike-account connection and archive import are stated as not offered, consistent with the absence of any such code path in that ledger's evidence.
- [x] App Store URL: `_review/verified-snippets.md` (App Store URL entry). Paywall linked; no prices in body.
- [x] Related links: slugs and Excel/XML/Strava/workouts/export hub pages exist. Inbound: `related:` of export-strava-data now lists this post in place of export-garmin-connect-data (Garmin keeps inbound links from export-fitbit-data and export-health-connect-to-obsidian).
