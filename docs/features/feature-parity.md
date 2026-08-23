# Apple ↔ Android Feature Parity Table

- **Status:** Living cross-reference. First compiled 2026-08-22 from both feature-doc trees (`apps/apple/docs/features/`, `apps/android/docs/features/`).
- **Purpose:** One row per user-facing capability, pairing the Apple and Android feature pages and stating the honest parity classification. Use it to find documentation gaps, plan cross-platform work, and avoid fabricated parity.
- **Sources of truth:** [`docs/architecture/cross-platform-unification-policy.md`](../architecture/cross-platform-unification-policy.md) (governing policy), [`packages/contracts/product-capabilities.json`](../../packages/contracts/product-capabilities.json) (machine-readable export-contract classifications), and both feature trees.
- **Rule:** A pair is `shared` only when the *user outcome* is equivalent. Where the OS APIs differ, the row says `platform-distinct` with the difference named — related-but-different values keep distinct identities (HealthKit HRV SDNN ≠ Health Connect/WHOOP RMSSD; Apple wrist temperature ≠ Health Connect skin temperature).

## Legend

| Marker | Meaning |
|---|---|
| ✅ | Dedicated feature page exists |
| 🟡 | Covered inside another page (folded) |
| 🔧 | Internal/runbook/contract doc only |
| — | No doc (feature absent or undocumented) |
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
| Share My Setup | ✅ `share-my-setup.md` (needs QA) | 🟡 mention in `onboarding.md` | shared (code), docs gap | Contract `shared-setup/v1` is pre-canonical pending device QA on both. **Android lacks a dedicated page.** |
| Metric selection | ✅ `metric-selection.md` | ✅ `metric-selection.md` | shared | 225+ HealthKit definitions / 21 categories vs 106 Health Connect metrics; identities aligned through the shared Rust metric registry. |

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
| Automated triggers | ✅ `apple-shortcuts.md` (App Intents, 9 intents) | ✅ `automation-intents.md` (Tasker/adb broadcasts, launcher shortcuts) | platform-distinct | OS automation surfaces differ by design. |
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
| Date/time/unit preferences | ✅ `date-time-units.md` | 🟡 in format pages (`DateFormatPreference`, `unitPreference`) | shared | Android lacks a standalone page; covered inside format customization content. |
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
| Direct CLI pairing | ✅ `cli-direct-iphone.md` | ✅ `direct-cli.md` | shared | Same direct-protocol family; iOS 6-digit code / protocol v1 vs Android 20-digit code / protocol v2. iPhone serves query v3; Android does not. |
| Mac as destination | ✅ `mac-sync.md` | — | apple_only | Android's desktop story is the CLI (`../android-desktop-destination.md`). |
| Manual IP / Tailscale | ✅ `manual-ip-sync.md` | 🟡 in `direct-cli.md` | shared | Connect-by-address on both. |
| CLI-triggered export | ✅ `cli-mac-iphone-export.md` | 🟡 in `direct-cli.md` | shared | Mac app broker on Apple; CLI direct on Android. |
| Home-screen widgets | ✅ `widgets.md` | ✅ `widgets.md` | shared | Four families each; Android substitutes Steps for Stand Hours (no HC Stand Hours) and excludes lock-screen measurement widgets (no Apple-style redaction). |
| Watch/wearable | ✅ `watch-app.md` (app + 10 widgets) | 🔧 `wear-os-implementation.md` runbook (tiles + 10 complications) | platform-distinct | watchOS app+widgets vs Wear OS tiles/complications; both phone/watch-authoritative or phone-only sensing. Android docs are a runbook, not a feature page. |
| Export progress Live Activity | 🟡 in `scheduled-exports.md`/`widgets.md` | — | apple_only | No Android equivalent (foreground service notification instead — 🟡 in `direct-cli.md`). |
| Agent/MCP local surfaces | ✅ `agent-local-api.md`, `local-mcp.md`, encrypted store/executor pages | — | apple_only | Loopback agent API and MCP hosting live on the Mac app; CLI/MCP client itself is cross-platform (see CLI inventory rows). |

## Reports, purchase, privacy

| Capability | Apple doc | Android doc | Parity | Notes |
|---|---|---|---|---|
| Clinician report (PDF) | ✅ `clinician-report.md` | ✅ `clinician-report.md` | shared | One v1 architecture spec governs both (root `docs/features/clinician-report-v1.md`); 11 metrics, same privacy model. |
| Monetization | ✅ `full-access-unlock.md` | ✅ `lifetime-unlock.md` | platform-distinct | StoreKit 2 subscriptions + individual/family lifetime vs Google Play one-time lifetime only. Same 10-free-action quota concept. |
| Local-first privacy | ✅ `privacy-local-first.md` | ✅ `privacy-local-first.md` | shared | No health-data cloud; user-directed destinations; private spools. |
| Community & feedback | ✅ `community-feedback.md` | 🟡 README/Play surfaces | shared | Discord/GitHub on both; email feedback is Apple-settings only. |

## Documentation gaps surfaced by this table

1. **Android Share My Setup page** — feature implemented on both; only Apple has a dedicated page (and it is `needs QA` pending contract canonicalization).
2. **Android date-time-units page** — capability exists (`DateFormatPreference`, `unitPreference`); currently folded into format pages. Either fold deliberately into `markdown-export.md`/format content or split a page.
3. **Android Wear OS feature page** — only a runbook + website guide exist; no user-facing page in the Android tree.
4. **Android roll-up summaries** — page intentionally absent until the v9 writer ships (`planned`); do not document ahead of the capability.
5. **Zip export** — Apple-only toggle today; revisit if Android adds zip writing.

## Maintenance

- When a feature page is added to either tree, add/update its row here and in both platform indexes.
- Classification changes (e.g., `planned` → `shared`) must match `product-capabilities.json` for export-contract capabilities — update both in the same commit.
- Never mark a pair `shared` to close a doc gap; either document the real difference or fix the gap.
