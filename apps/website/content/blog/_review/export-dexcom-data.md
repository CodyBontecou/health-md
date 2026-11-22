# Dexcom export claim verification

Verified 2026-11-21 by Claude (agent), method: traced; Dexcom pages re-checked live on 2026-11-21. No health records, vendor account, actual export, device, simulator or product visual QA was accessed. Public source contracts and samples are unchanged.

## Claims

- [x] Dexcom's current raw-data FAQ https://www.dexcom.com/en-us/faqs/can-i-export-raw-data documents Clarity browser login, Reports export icon and date-range CSV. Its related answers distinguish PDF reports. Article paraphrase stays below 200 words from this source. No invented Clarity columns, download entitlement or full-history guarantee.
- [x] G7 FAQ https://www.dexcom.com/en-us/m/faqs/how-do-i-share-my-glucose-data-with-the-apple-health-app checked live: Connections/Apple Health/Activate/Blood Glucose/Allow; three-hour delay; G7 and G7 15 Day scope. No universal G6/ONE/Stelo/region menu promise. Under 200 words derived from this source.
- [x] Regional overview https://www.dexcom.com/en-GB/faqs/data-sharing?ipc=US supports conditional phone/system-dependent Health Connect sharing and three-hour delay. Not used to promise US/device-universal Android availability or reproduce iPhone schema on Android.
- [x] HealthKitManager.swift blood glucose fetch uses queryDiscreteStatisticsWithLegacyFallback average/minimum/maximum and optional timestamped samples; SystemHealthStoreAdapter.swift unit mapping is mg/dL. Selected-day statistics contain no Dexcom-only source predicate. CSVExporter.swift and JSONExporter.swift confirm labels, optional values and legacy bloodGlucose average alias. Summary versus Detailed Time-Series is preserved; no original-series reconstruction or clinical-summary parity claim.
- [x] Maintained first-export/date-range/format guides establish separate read authorization, folder, one-day preview, Markdown-first then CSV/JSON, and per-day outputs. Metric blood_glucose is in the Apple metric registry. Missing data is not interpreted as zero or proof of permission state. No native/schema/sample edits.
- [x] Existing verified-snippets.md and local-only export guide scope no-account/no-server-copy-by-default to core folder export; destinations have separate rules. App Store ID and internal destinations reuse verified existing routes. No price or measured download claim.
- [x] New guide has verification frontmatter, canonical/index/sitemap through existing blog generator and inbound related navigation from the Cronometer guide. Review ledger remains outside public output. Protected CSV/MCP experiments and both measurement registries remain unchanged.
- [x] Safety boundary explicitly excludes using retrospective files for live readings/alerts/treatment, and avoids clinical targets or treatment advice. Device validation was not performed.

## Refresh 2026-11-21

- [x] Answer box, "Can I export from the G7 app?" and FAQ: raw-data FAQ (CSV via export icon on Clarity Reports page, clarity.dexcom.com; Excel-viewable) and https://www.dexcom.com/en-us/faqs/clarity/using-clarity (Clarity app PDFs for 2/7/14/30/90 days; uploaded data stays accessible while product is available; no export limit stated). The G7 app is said to have no file export only as "Dexcom documents CSV in Clarity"; Dexcom does not state it outright.
- [x] Receiver section: https://www.dexcom.com/en-us/faqs/upload-dexcom-receiver-to-clarity (Clarity for Home Users, Upload, uploader download, USB cable, receiver on). No OS, model or frequency claims made.
- [x] CSV contents/units: Dexcom pages do not document columns or units; article says so and tells readers to read the file. No Tidepool claim (no primary source found).
- [x] G7 app **Connections** tab: G7 Apple Health FAQ (Connections tab, Apple Health, Activate, Blood Glucose, Allow), re-checked 2026-11-21.
- [x] Incoming link: export-omron-connect-data `related` now lists this guide (replacing the weight guide).
- [x] "Share with your clinic" section (no third-party platform claims): clinic sharing after receiver upload: raw-data FAQ sentence.
- [x] Three-hour delay and Health.md-cannot-read-Dexcom answers: G7 Apple Health FAQ and existing traced app behavior above. CTA text clarifies it is not a Clarity export.
- [x] Internal links: glucose-range chart preview, /apple-health-export/ hub; incoming links from the hub chooser and apple-health-to-excel. No topic cluster in build-blog.mjs fits.
