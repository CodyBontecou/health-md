# Strava export claim verification

Verified 2026-11-20 by Claude (agent), method: traced. Strava support pages re-fetched live on 2026-11-20. No account, device, actual archive or spreadsheet QA. No app behavior changed.

## Claims

- [x] https://support.strava.com/en-us/articles/15401919-how-do-i-export-my-strava-data (article dated Sep 14, 2026): website-only export; bulk path Settings → My Account → Download your account → Get Started → Request download; emailed link to profile email, may take a few hours; Export Original (uploaded format, often FIT), Export GPX, `/export_tcx`; TCX needs GPS; GPX empty/unreadable without GPS; GPX includes power-meter power, not estimated power.
- [x] Archive layout (activities.csv, activities/ folder, .fit.gz/.gpx/.tcx files, other CSVs) is NOT from Strava's article and was not verified against an inspected archive; it comes from general user and third-party descriptions of Strava archives (for example geo-activity-playground's moving-from-Strava notes, corroboration only). The page words it as "typical" and tells readers to check their own download.
- [x] The article does not mention phone-browser desktop mode, so that claim was dropped; the page says it was not verified. The article does not list archive contents or say whether photos are included; the archive-contents section is worded conditionally ("typical", "check your own download") and flagged as user/third-party description, not Strava's. The Strava "active account" requirement applies to Developer Hub data and is not claimed.
- [x] activities.csv import advice (CSV import, locale, check units/headers) is general spreadsheet guidance, makes no claim about Strava's column units; spreadsheet guides are stated to cover Health.md files.
- [x] https://support.strava.com/en-us/articles/15402024-apple-health-and-strava (dated Sep 21, 2026): Manage Apps and Devices → Health, Send to Health, route/type/distance/time/calories, third-party-recorded routes (Garmin, Zwift) don't sync. Kept as before.
- [x] https://support.strava.com/en-us/articles/15401554-health-connect-and-strava (dated Sep 18, 2026): Android app only; sends time/distance/calories of GPS-based activities; receives weight. Kept as before.
- [x] Health.md claims unchanged from the 2026-10-30 trace: reads authorized health-store records into daily CSV/JSON/Markdown; no Strava account connection, archive import or GPX/FIT/TCX output. Store links only in the Health.md section after the verification step.
- [x] Privacy matches the local folder workflow and the separate, opt-in, single-owner Health.md Cloud pilot that is not generally available.
- [x] FAQ: the timing answer repeats only the article's "few hours" for the bulk email and says nothing about single-activity timing; the routes answer is limited to the article's GPX (records GPS points) and TCX (GPS only) statements; other-athlete and re-import answers make no promises.
- [x] Incoming one-line links added to the Garmin, Polar Flow, COROS and Apple Health workouts guides; related list now includes apple-health-to-excel and export-garmin-connect-data.
