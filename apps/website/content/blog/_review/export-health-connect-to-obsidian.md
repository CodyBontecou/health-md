# Android Health Connect to Obsidian claim verification

Verified: 2026-10-27 by Codex (agent), method: traced.

Source and documentation review only. No emulator, device, Obsidian import, scheduled export, purchase, installation or visual QA was performed. Website tests check publication, links and existing analytics classification; they do not establish device/provider availability or a completed download.

## Claims

- [x] October30,2026: the related-guide recommendation now links to the Samsung Health → Health Connect CSV workflow, which has its own producer/official-source claim ledger. Only the related slug and publication revision changed; existing article body and verified feature claims remain unchanged.

- [x] Android reads authorized Health Connect records on the device and writes selected formats to a chosen folder: `apps/android/app/src/main/java/com/healthmd/data/health/HealthConnectManager.kt`, `data/health/HealthConnectDataProvider.kt`, `data/storage/FileExportManager.kt` and `apps/website/docs-src/src/content/docs/android.md`. Source apps must actually write records to Health Connect; missing data is not a zero or proof of an absent real-world event.
- [x] Folder access uses an Android document-tree picker and persisted URI permissions: `presentation/export/ExportScreen.kt`, `presentation/onboarding/OnboardingViewModel.kt` and `data/storage/FileExportManager.kt`. The guide conditions sync/provider use on writable persistent access and offers local export followed by the user's chosen sync tool. It does not promise every provider exposes a writable folder.
- [x] Markdown, Bases frontmatter, JSON and CSV outputs are implemented by `data/export/MarkdownExporter.kt`, `ObsidianBasesExporter.kt`, `JsonExporter.kt` and `CsvExporter.kt`; also documented in `docs-src/src/content/docs/android.md` and `format.md`. Formats may be combined; previewing a small date/metric selection follows the documented first-export workflow. Bases notes do not imply a prebuilt Bases view.
- [x] Overnight sleep uses the session start day: `HealthConnectManager.kt` groups sleep sessions by `startTime.atZone(zone).toLocalDate()`, consistent with `docs-src/src/content/docs/sleep-date-attribution.md`. Yesterday on a Tuesday morning is the Monday start day. Apple and Android still have distinct source metrics/profiles; `docs/architecture/cross-platform-unification-policy.md` and `android.md` prohibit fabricated parity.
- [x] Exact alarms and durable work fallback, history and recovery: `data/scheduler/ScheduledProfileScheduler.kt`, `ExportScheduler.kt`, and `docs-src/src/content/docs/android.md`. A requested schedule time is not guaranteed, and Google Play scheduling requires the lifetime entitlement while F-Droid includes it. No automation execution was performed.
- [x] Google Play matches the canonical app URL and was fetched publicly on 2026-10-27. The F-Droid catalog URL returned a real 404; `apps/android/docs/fdroid-distribution-plan.md` records publication gates pending. The guide links to the maintained Android distribution-status notice instead of advertising a catalog download. `apps/android/README.md` documents free manual actions followed by lifetime access, F-Droid full Health Connect access without billing, and channel signature/uninstall/state boundaries. The guide defers the exact Play allowance to the installed app instead of promising a fixed number; direct-provider differences are explicitly separate from the folder workflow.
- [x] The CSV link is the existing `assets/samples/health-connect-summary-excerpt.csv`: header `Date,Category,Metric,Value,Unit,Timestamp`, with fictional Steps and Walking Running Distance rows for 2026-03-15. The guide labels it a limited synthetic CSV excerpt, distinguishes it from Markdown/Bases notes, and does not present it as a complete export or personal health data.
- [x] The described core folder export requires no Health.md account or relay through a Health.md health-data server: `android.md`, `FileExportManager.kt` and `privacy-policy.html`. Selected sync/document providers have their own data paths. This claim is scoped to the folder workflow rather than every optional product surface.

- [x] Public distribution status is separated from build capability: the official F-Droid catalog returns a real 404 at verification, while `apps/android/docs/fdroid-distribution-plan.md` states publication gates are pending. Homepage download metadata, Android acquisition hub and localized docs link to the authored `distribution-status` notice rather than claiming catalog availability. No F-Droid publication or application release was attempted.

## Sleep-date clarification — 2026-10-27

- [x] Supersedes the earlier calendar-start-day shorthand. Android SleepJournalSummary uses a local noon-to-noon window, matching the normative android-sleep-journal-summary.md contract. After-midnight sleep can belong to the previous journal date; raw records retain their own ownership. No Android exporter, schema, unit, aggregation or fixture changed. Current website wording and localized troubleshooting now point to the shared concrete examples. Verification is source tracing, not a new device export.

- [x] October 30 discovery follow-up adds the verified Garmin export guide to related recommendations; the article body and prior claims are unchanged.

- [x] October 30 related-guide follow-up adds the source-traced Fitbit/Google Health export chooser. Article body and prior workflow claims are unchanged.
