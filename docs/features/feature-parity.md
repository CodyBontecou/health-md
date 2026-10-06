# Apple ↔ Android Feature Parity Table

- **Status:** Living cross-reference. First compiled 2026-08-22 from both feature-doc trees (`apps/apple/docs/features/`, `apps/android/docs/features/`).
- **Purpose:** Pair the Apple and Android guides and preserve rationale for native/semantic differences. This is editorial navigation, not an independent availability, metric-count, pricing, or release ledger.
- **Authority:** The [unification policy](../architecture/cross-platform-unification-policy.md) governs intent; [product-capabilities.json](../../packages/contracts/product-capabilities.json) governs machine-readable capability classifications; code, tests, schemas, and configuration establish implementation. Consult those owners rather than inferring availability from a page or the markers below. Customer guidance has a separate audience in the website's `guides/platform-features.md`.
- **Rule:** Equivalent user outcomes require evidence. `platform-distinct` below describes an editorial/native-mechanism difference, not a machine-readable capability classification. Related-but-different values retain distinct identities (HealthKit HRV SDNN ≠ Health Connect/WHOOP RMSSD; Apple wrist temperature ≠ Health Connect skin temperature).

## Legend

| Marker | Meaning |
|---|---|
| ✅ | Dedicated feature page exists |
| 🟡 | Covered inside another page (folded) |
| 🔧 | Internal/runbook/contract doc only |
| — | No dedicated guide here; consult code and the capability ledger for availability |
| `shared` | Equivalent user outcome on both platforms |
| `platform-distinct` | Deliberately different mechanisms or data identities for the same need |
| `apple_only` / `android_only` | One platform; OS/API boundary documented |
| `planned` | Gap tracked with a concrete target |

## Setup & permissions

| Capability | Apple doc | Android doc | Parity | Notes |
|---|---|---|---|---|
| First-run onboarding | ✅ `onboarding.md` | ✅ `onboarding.md` | shared | Different step flows; same outcome (permissions → destination → unlock → ready). Android onboarding offers a Shared Setup entry point. |
| Health data permissions | ✅ `healthkit-permissions.md` | ✅ `health-connect-permissions.md` | shared | HealthKit type requests vs Health Connect category grants; Android adds a rationale activity (Health Connect policy). |
| Destination selection | ✅ `vault-folder-selection.md` | ✅ `folder-destination.md` | shared | Obsidian vault/iCloud/Files vs SAF folder picker (Drive/OneDrive/Syncthing/Obsidian Sync). |
| Share My Setup | ✅ `share-my-setup.md` (needs QA) | ✅ `share-my-setup.md` (needs QA) | planned | Contract `shared-setup/v2` is pre-canonical pending device QA on both; v2 is the one and only profile contract since the 2026-09-05 sunset (ADR-0006: v1 removed, default writers emit v2 exclusively, v1 input rejected as unsupported). Android page added 2026-09-05. |
| Metric selection | ✅ `metric-selection.md` | ✅ `metric-selection.md` | shared | Coverage and selection identities are owned by the [shared metric registry](../../packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json); align identities only where semantics are proven equivalent. |

## Export core

| Capability | Apple doc | Android doc | Parity | Notes |
|---|---|---|---|---|
| Manual date-range export | ✅ `manual-export.md` | ✅ `manual-export.md` | shared | Free-quota accounting on both (10 free actions). |
| Export preview | ✅ `export-preview.md` | ✅ `export-preview.md` | shared | Android raw-snapshot preview additionally runs provider-native reads with no upload. |
| Export profiles | ✅ `export-profiles.md` | ✅ `export-profiles.md` | shared | Named configs, independent destinations/schedules; profiles never change the public schema. |
| Multi-format single run | ✅ `multi-format-export.md` | ✅ `multi-format-export.md` | shared | MD + Bases + JSON + CSV counts as one export action on both. |
| Zip archive toggle | 🟡 in `multi-format-export.md` | — | apple_only | iOS writes one DEFLATE zip per run; Android writes loose files (no zip writer). |
| Export history & retry | ✅ `export-history-retry.md` | ✅ `export-history-retry.md` | shared | Room-backed history on Android. |
| Roll-up summaries | ✅ `rollup-summaries.md` | — | planned | Android adopts `rollup-summary` v9 range semantics in the first v9 writer; frozen v4 / analytical v5 stay byte-immutable (`export.range-summary`). |
| Scheduled exports | ✅ `scheduled-exports.md` | ✅ `scheduled-exports.md` | platform-distinct | APNs-preflighted local notifications vs WorkManager + optional exact alarm, boot recovery, missed-date recovery. |
| Scheduled Today Refresh | ✅ `scheduled-exports.md` | ✅ `scheduled-exports.md` | shared | Completed-day runs can also refresh today's partial file (`export.scheduled-today-refresh`): Apple runs best-effort same-day refresh occurrences (3/6/12 h), Android profile schedules mirror those slots, and the Android single schedule offers a "past complete days + today" window paired with its sub-day cadence. |
| Automated triggers | ✅ `apple-shortcuts.md` (App Intents) | ✅ `automation-intents.md` (Tasker/adb broadcasts, launcher shortcuts) | platform-distinct | OS automation surfaces differ by design. |
| API endpoint export | ✅ `api-endpoint-export.md` | ✅ `api-endpoint-export.md` | shared | Both POST a JSON envelope to a user endpoint; Android adds encrypted header storage and stricter framing/proxy-header rules. |

## Export formats

| Capability | Apple doc | Android doc | Parity | Notes |
|---|---|---|---|---|
| Markdown export | ✅ `markdown-export.md` | ✅ `markdown-export.md` | shared | Same template tiers and frontmatter workflow. |
| Obsidian Bases export | ✅ `obsidian-bases.md` | ✅ `obsidian-bases.md` | shared | |
| JSON export | ✅ `json-export.md` | ✅ `json-export.md` | platform-distinct | Same `healthmd.health_data` family, independently versioned: Apple v8 (+ typed WHOOP section), Android frozen v4 + analytical v5. Proposed unified v9. |
| CSV export | ✅ `csv-export.md` | ✅ `csv-export.md` | shared | |
| NDJSON raw output | — (raw via CLI `--raw-format ndjson`) | ✅ `raw-snapshots.md` | android_only | Raw snapshot artifact format. |
| Filename templates | ✅ `filename-templates.md` | ✅ `filename-templates.md` | shared | Same placeholder vocabulary. |
| Folder organization | ✅ `folder-organization.md` | ✅ `folder-organization.md` | shared | `{year}/{month}`, `{year}/{quarter}`. |
| Frontmatter customization | ✅ `frontmatter-customization.md` | ✅ `frontmatter-customization.md` | shared | |
| Date/time/unit preferences | ✅ `date-time-units.md` | ✅ `date-time-units.md` | shared | Date, clock, and display-unit preferences; Android JSON stays frozen v4/analytical v5 with canonical numerics while Apple documents the v8 time-context and structured-unit contract. |
| Markdown template customization | ✅ `markdown-template-customization.md` | 🟡 in `markdown-export.md` | shared | |
| Write modes | ✅ `write-modes.md` | ✅ `write-modes.md` | shared | Overwrite / append / update-merge. |
| Daily note injection | ✅ `daily-note-injection.md` | ✅ `daily-note-injection.md` | shared | |
| Data dictionary | ✅ `data-dictionary.md` + generated reference | 🔧 `docs/export-contract/` ledgers | platform-distinct | Generated field catalogs (Apple) vs mapping/parity ledgers (Android); shared registry is the cross-language spine. |

## Advanced data

| Capability | Apple doc | Android doc | Parity | Notes |
|---|---|---|---|---|
| Individual entry tracking | ✅ `individual-entry-tracking.md` | ✅ `individual-entry-tracking.md` | shared | Workouts / sleep stages / vitals timestamped files. |
| Workout details | ✅ `workout-details.md` | ✅ `workout-details.md` | shared | Android correlates by time window; page documents HC limitations honestly. |
| Lossless source archive | ✅ `time-series-data.md` (`healthmd.healthkit_records` v1) | — | apple_only | Health Connect records are not HealthKit objects; UUID/relationship semantics cannot exist (`apple.lossless-healthkit-archive`). |
| Raw API snapshots | — | ✅ `raw-snapshots.md` (+ contract docs) | android_only | Separate archival product: immutable provider-native JSON/NDJSON + manifests/checksums; Fitbit/Oura/WHOOP/Withings provider bytes. |
| Raw changes backend | — | 🔧 `raw-changes-v1.md` | android_only | Change tokens + deletion tombstones. |
| Cloud provider connections | 🟡 dormant prototypes in `third-party-integrations.md` | ✅ `cloud-providers.md` | platform-distinct | Apple: typed WHOOP provider sections in v8 (beta-flagged) + dormant prototypes. Android: provider-native raw snapshots via OAuth. Not aliased. |
| Mood / State of Mind | ✅ `mood-state-of-mind.md` | — | apple_only | Health Connect has no State of Mind record. |
| Medication dose events | ✅ in `export-schema.md` | — | apple_only | HealthKit medication catalog; HC PHR is not equivalent. |
| Wrist vs skin temperature | 🔧 generated metric catalog (`docs/reference/generated/core/metric-catalog.md`) | 🔧 HC records in export | platform-distinct | Apple Watch wrist temperature ≠ Health Connect skin-temperature deltas/baselines. |
| HRV | 🟡 `export-schema.md` + generated catalog | 🟡 `widgets.md` note + metrics | platform-distinct | HealthKit SDNN ≠ Health Connect RMSSD — never merged. |

## Devices & sync

| Capability | Apple doc | Android doc | Parity | Notes |
|---|---|---|---|---|
| Direct CLI pairing | ✅ `cli-direct-iphone.md` | ✅ `direct-cli.md` | shared | New clients share selector 3's universal QR and 20-digit code while preserving legacy Apple selector 1 / Android selector 2; application v1/v2 remain distinct. iPhone serves query v3; Android does not. |
| Direct CLI wake window | ✅ `cli-direct-iphone.md` + RFC-0005 | ✅ `direct-cli.md` + RFC-0005 | shared | The same bounded P1 wait lets opening either app unblock the in-flight request. |
| Direct CLI push wake | ✅ `cli-direct-iphone.md` + RFC-0005 | 🟡 RFC-0005 P3 | planned | Opt-in APNs doorbell is available for enrolled iPhones; Android FCM, Play/F-Droid degradation, and physical qualification remain a concrete P3 target. |
| Mac as destination | ✅ `mac-sync.md` | — | apple_only | Android's desktop story is the CLI (`../android-desktop-destination.md`). |
| Manual IP / Tailscale | ✅ `manual-ip-sync.md` | 🟡 in `direct-cli.md` | shared | Connect-by-address on both. |
| CLI-triggered export | ✅ `cli-mac-iphone-export.md` | 🟡 in `direct-cli.md` | shared | Mac app broker on Apple; CLI direct on Android. |
| Home-screen widgets | ✅ `widgets.md` | ✅ `widgets.md` | shared | Native widget families are documented in their owning guides; Android substitutes Steps for Stand Hours (no HC Stand Hours) and excludes lock-screen measurement widgets (no Apple-style redaction). |
| Watch/wearable | ✅ `watch-app.md` | ✅ `wear-os.md` (+ runbook `wear-os-implementation.md`) | platform-distinct | watchOS app+widgets vs Wear OS tiles/complications; both phone/watch-authoritative or phone-only sensing. Android's implemented Wear preview is unpublished; current Play releases hide setup and disable sync. Its concrete requalification target and gates are owned by `apps/android/release-scope.json` and the completion audit. |
| Export progress Live Activity | 🟡 in `scheduled-exports.md`/`widgets.md` | — | apple_only | No Android equivalent (foreground service notification instead — 🟡 in `direct-cli.md`). |
| Agent/MCP local surfaces | ✅ `agent-local-api.md`, `local-mcp.md`, `evidence-packets.md`, encrypted store/executor pages | — | apple_only | Loopback agent API and MCP hosting live on the Mac app; CLI/MCP client itself is cross-platform (see CLI inventory rows). |

## Reports, purchase, privacy

| Capability | Apple doc | Android doc | Parity | Notes |
|---|---|---|---|---|
| Clinician report (PDF) | ✅ `clinician-report.md` | ✅ `clinician-report.md` | shared | One v1 architecture spec governs both (root `docs/features/clinician-report-v1.md`); 11 metrics, same privacy model. |
| Monetization | ✅ `full-access-unlock.md` | ✅ `lifetime-unlock.md` | platform-distinct | StoreKit 2 individual/family lifetime and family upgrade vs Google Play one-time lifetime; no recurring Apple subscription. Same 10-free-action quota concept. |
| Local-first privacy | ✅ `privacy-local-first.md` | ✅ `privacy-local-first.md` | shared | User-directed destinations and private spools; the portable CLI has no retained typed-query corpus. |
| Community & feedback | ✅ `community-feedback.md` | 🟡 README/Play surfaces | shared | Discord/GitHub on both; email feedback is Apple-settings only. |

## Guide coverage and release gates

- Share My Setup guides exist on both platforms, but the capability remains planned until the [v2 physical-device matrix](../qa/shared-setup-v2.md) is qualified. Page existence and a v2-only writer are not availability approval.
- Android Wear has separate maintainer and public guides because implementation, distribution, and physical qualification are distinct. Follow its completion audit and release scope, not historical emulator receipts alone.
- Android roll-up guidance remains absent until its planned v9 writer exists; frozen v4/analytical-v5 behavior is not silently upgraded.
- Revisit zip-export guidance if Android adds an implementation. Track work and completion in the issue tracker, not another completed-task list here.

## Maintenance

- When a feature page is added to either tree, add/update its row here and in both platform indexes.
- Let `product-capabilities.json` own classifications and targets. When an approved capability changes, update affected guide pointers and customer-facing explanations; do not maintain a second metric/configuration catalog here.
- Never mark a pair `shared` to close a doc gap; either document the real difference or fix the gap.
