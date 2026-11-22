# Garmin Connect export claim verification

Verified: 2026-10-30 by Codex (agent), method: traced.

Public Garmin support pages were read in a rendered browser because text fetch returned only a shell. No Garmin account, device, permission flow, native app, spreadsheet or visual QA was performed. No native capability or export contract changed.

## Claims

- [x] Native CSV summaries, reports, weight/blood-pressure reports, activity formats and account export follow the rendered English FAQ https://support.garmin.com/en-US/?faq=W1TvTPW8JZ6LfJSfK512Q8. Native options precede the body app CTA; Health.md is not needed. No completeness, delivery-time, restore or native-file import promise.
- [x] Android 14+, one-way sharing after successful device sync and category examples follow the rendered English FAQ https://support.garmin.com/en-US/?faq=JToBEy0jfe6pIygark2Ui5. Actual record presence is checked first. No promise of all dashboard scores, backfill or reverse import.
- [x] Connection/category permissions follow https://support.google.com/android/answer/12201227 and maintained Android setup. Garmin writes, Health.md reads. Vendor sharing does not establish support for every Health.md output category; guide scopes selected supported records and a known-day check.
- [x] HealthConnectDataProvider, HealthProviderRegistry, HealthConnectManager, ExportScreen and FileExportManager corroborate source/read/preview/date/metric/format/folder flow. Reads may include several origins; no Garmin-only filter promised. `apps/android/docs/health-provider-support.md` marks the direct Garmin adapter unavailable pending partner/backend support. Users keep Health Connect selected.
- [x] CSV block is byte-identical to health-connect-summary-excerpt.csv, tied by `test/health-connect-sample.test.mjs` to frozen Android render fixtures. Fictional values, six fields/empty daily Timestamp and mixed Value types are explicit; no Garmin capture or vendor-CSV equivalence, no spreadsheet execution.
- [x] History follows https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data: before initial Health.md grant plus later records; conditional broader access and separate source backfill. Missingness is not zero; existing sleep-date and platform semantics remain unchanged.
- [x] Privacy follows maintained policy: no Health.md account/server copy by default, separate vendor handling; optional single-owner pilot only retains intentionally uploaded API exports with no signup/automatic sync/general availability. Publication guard includes new slug.
- [x] Android platform selects Google Play. Three related guides plus inbound Android Obsidian recommendation use existing generator; ledger excluded. No price/quota/configured OAuth/direct-cloud promise or public schema change.

- [x] 2026-11-18: one cross-link sentence to /blog/export-fitbit-data/ added; it restates only claims sourced in that guide's ledger (Garmin Health Connect is one-way per this guide; Fitbit Web API retired October 30, 2026 per Google's notice). No other body change.

- [x] 2026-11-22 refresh (traced; no Garmin account/device): Garmin's Apple Health FAQ (https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA) returned HTTP 403 to automated fetch, so its details (foreground requirement, past-two-weeks window, one-way direction, Activity rings) could NOT be confirmed and were deliberately omitted; the page only states that Garmin documents sharing to Apple Health, that it depends on settings/device, and sends readers to the FAQ. Body Battery staying in Garmin's own export is a scoping statement, not a sharing claim.
- [x] Apple Data Sources & Access / source priority: https://support.apple.com/guide/iphone/iph5ede58c3d/ios. Health category → day → Show All Data source check is a reader verification step.
- [x] Archive "mostly JSON and FIT", All Activities CSV as summary table, FIT original, TCX/GPX: Garmin export FAQ (already cited) and brief; archive delivery time undocumented, so not stated. Account Data Management: https://www.garmin.com/en-US/account/datamanagement/.
- [x] iPhone Health.md steps (read access, folder, CSV, one known day, reads any Apple Health source) trace to maintained iPhone docs /docs/iphone-first-export/ and /apple-health-export/. iPhone CSV uses same daily layout as linked /apple-health-to-csv/. No Garmin import/API/history-recovery claim. Platform both: App Store button in iPhone section, Play button in Android section.
- [x] Inbound links added in export-apple-health-workouts and export-coros-data.
