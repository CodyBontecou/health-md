# Claim ledger: How to export Apple Health data to Obsidian

Verified: 2026-10-25
Verified by: Codex (agent)
Method: mixed

Producer baseline: main `4da74b120e2858c29ee4a77aac0bb46810668974`.
The native producer tree is unchanged from the physically qualified #182 head.
Cloud source scope: `7002922d634811b7b3b1c51663814724b4f89e99`,
`apps/cloud/docs/public-account-dashboard.md` and `personal-tailnet-pilot.md`.
Those documents distinguish the active owner pilot from undeployed multi-user
foundations. This article does not qualify those foundations for release.

## Claims

- [x] **The iPhone reads authorized HealthKit records; users choose metrics, dates and a destination.**
  Traced to `apps/apple/HealthMd/Shared/Managers/HealthKitManager.swift`,
  `HealthKitDailyCapture.swift`, and `apps/apple/HealthMd/iOS/Views/ExportTabView.swift`.
  The #182 physical synthetic-workout run selected one metric and one day,
  without treating an empty query as proof that no source records exist.
- [x] **The quick workflow's permission, folder, format, date, preview and export controls are reachable.**
  Traced to `ExportTabView.swift`, `VaultManager.swift` and format settings.
  Physical #182 acceptance exercised the real local export path and the
  Markdown customization journey; this review does not claim every permission
  state or an Obsidian application click-through was executed.
- [x] **Local folders, Files providers and paired Mac destinations are distinct from a Health.md cloud copy.**
  Traced to `apps/apple/HealthMd/Shared/Managers/VaultManager.swift`,
  `APIEndpointExportRunner.swift`, and the frozen-settings/export job path.
  Physical #182 local and paired-Mac synthetic outputs matched byte-for-byte.
  Provider sync is described as a property of the chosen provider, not as an
  additional Health.md sync implementation.
- [x] **Markdown, Bases, JSON and CSV are supported output formats with different roles.**
  Traced to the four production exporters and `apps/apple/docs/reference/generated/core/`.
  Markdown/JSON/CSV were exercised on the physical iPhone in #182; Bases claims
  are source/fixture checks, not a new Bases UI execution.
- [x] **The Markdown example is abbreviated and uses illustrative values.**
  `HealthMetricsDictionary.swift` maps `steps`, `sleep_total_hours` and
  `workout_count`; `summary-day.md` contains the schema/capture metadata that
  the article explicitly omits from its short example. No illustrative number
  is represented as measured user data or an exact full producer artifact.
- [x] **Bases properties include typed dates/numbers and workout_details.**
  Traced to `ObsidianBasesExporter.swift` and generated `summary-day-bases.md`
  (including its workout_details array). No plugin behavior or automatic Bases
  database creation is implied by writing frontmatter properties.
- [x] **JSON categories and CSV row shapes match producer artifacts.**
  Checked `summary-day.json` top-level date/type/units and category keys,
  `CSVExporter.swift`, `summary-day.csv`, and `csv-row-contracts.md`.
  The article now states mixed Value types and five-/six-field row behavior;
  it links to the exact format documentation. See verified-snippets.md.
- [x] **Daily Note Injection updates managed fields/sections while preserving unrelated user writing.**
  Traced to `DailyNoteInjector.swift` and its regression suite. Physical #182
  ran rich → suppressed → suppressed → rich exports, preserving the sentinel
  journal/frontmatter and verifying repeated output and restored bytes.
- [x] **Catalog entries do not establish availability or historical clinical access.**
  Checked generated `metric-catalog.md`, `HealthKitRecordCatalog.swift`,
  `HealthKitManager.swift` authorization filtering and current privacy policy.
  The revised article states build/OS/permission/source limitations and that
  current App Store builds do not request historical clinical records.
- [x] **The suggested activity, sleep, heart, workout, mindfulness and symptom properties exist.**
  Traced to generated `metric-catalog.md` and `HealthMetricsDictionary.swift`.
  Suggestions are optional organization choices; they do not guarantee records
  exist for every user or provide clinical advice.
- [x] **The separate cloud pilot requires intentional uploads and has bounded, unbacked retention.**
  Traced to the immutable cloud deployment-contract/personal-pilot sources
  above and this PR's privacy policy: one owner, no public signup or automatic
  device sync, quota-limited revision retention, permanent-loss risk and
  asynchronous erasure after access disablement. Public unauthenticated login
  and account/export API boundaries were rechecked on 2026-10-22. No real
  export, credential issuance or account deletion was performed for this PR.
- [x] **Troubleshooting and scheduled-export language preserves uncertainty.**
  Traced to HealthKit query/capture state and `ScheduledExportCoordinator.swift`.
  The article recommends checking permission/scope/warnings and calls iOS
  background timing a target, not a guarantee. It does not diagnose an empty
  result as absent source data.
- [x] **Linked screenshots and product documentation exist.**
  Checked the three authored asset paths and reference/export/daily-note
  routes against the repository. The full website build/link checks qualify
  the rendered paths; images illustrate the workflow, not a claim that all
  future app layouts remain identical.

## October 25 discovery-guide update

The new instructions were traced against the existing iPhone export, daily-note, format, and sleep-date documentation; no new native-app or Obsidian UI qualification is claimed. Earlier mixed verification evidence above remains scoped to the earlier runs.

- [x] **One-day setup and filename choices match the documented daily-note controls.** Traced to `apps/website/docs-src/src/content/docs/iphone-first-export.md` and `daily-notes.md`: vault-relative Folder, extension-free Filename, `{date}`, Create note if missing, and optional metric sections.
- [x] **The synthetic Markdown excerpt retains exact selected fixture properties.** Compared with `apps/apple/docs/reference/generated/core/summary-day.md`: date `2026-03-15`, type `health-data`, resting heart rate `58`, sleep hours `7.75`, and steps `12500`. The article labels the excerpt as partial and synthetic.
- [x] **Sleep-start dates and missing-data checks retain documented semantics.** Traced to `apps/website/content/blog/why-sleep-is-in-yesterdays-note.md`; the update preserves current upstream permission and Cloud-pilot qualifications.
