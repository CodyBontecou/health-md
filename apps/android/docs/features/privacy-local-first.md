# Local-First Privacy

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Settings (privacy disclosures) — applies to every screen
- **Source files:** `app/src/main/res/values/strings.xml` (privacy disclosures), `app/src/main/java/com/healthmd/rawexport/RawExportStorage.kt`, `app/src/main/java/com/healthmd/rawexport/DirectRawExportStorage.kt`, `app/src/main/java/com/healthmd/domain/distribution/DistributionPolicy.kt`

## What it does

Health.md does not operate a health-data cloud and has no accounts. Health data is read from your device, shown to you, and written only to destinations you explicitly choose: a folder through the Android picker, your own API endpoint, a paired Direct CLI computer, or an on-device PDF. In-app privacy disclosures state exactly which permission maps to which data flow.

## Who it is for

- Anyone deciding whether to trust Health.md with Health Connect data
- Reviewers of the Settings privacy section before granting background or history access

## Where to find it

1. Open **Settings** → **Health Connect Permissions**.
2. Read the permission-by-permission mapping before granting.

## Prerequisites

- None — the model is the default; there is nothing to enable

## Setup

Nothing to configure. Every health-data network or cross-device flow requires an explicit action first (selecting an API endpoint, pairing a CLI, or—in Play—connecting a direct provider). The F-Droid build contains no Health.md telemetry endpoint, attribution/referrer code, onboarding analytics worker, telemetry identifier, or telemetry DataStore.

## Example output

The disclosure states: every permission maps directly to data read from Health Connect and exported only to the destination you choose; folder exports stay in local or provider-backed storage; API endpoint sends records directly to the HTTP(S) URL you configure (HTTP is not encrypted in transit); Direct CLI sends records through an authenticated encrypted connection to that computer.

## Tips

- Intermediate data never leaks to cloud storage: raw snapshots, previews, and Direct CLI transfers spool under Android **no-backup** private storage (`noBackupFilesDir`), invisible to backups and device transfer.
- API credentials are Keystore-encrypted and excluded from backups, logs, and history.
- In the Play build, configuration-gated campaign attribution sends only random app-generated install/event UUIDs and validated campaign metadata—never health data, raw referrers, device IDs, exports, accounts, or paths. Play onboarding telemetry is similarly bounded and allowlisted.
- The F-Droid build performs no Health.md telemetry and creates no telemetry identity, queue, or persisted state. User-configured API exports, feedback links, update checks performed by the repository client, and explicit Direct CLI transfers are not telemetry.
- In Play, Wear OS receives only a private aggregate snapshot over the data layer; the phone stays authoritative. Wear controls and transport are absent from F-Droid.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Unsure where data goes | Destination changed | Check Export Target and the Settings privacy mapping |
| Worried about HTTP endpoint | Plain HTTP is unencrypted | Use an HTTPS endpoint |
| Direct CLI data lingering | Spool retained for resumability | Cancel/Forget paired CLI; spools delete sooner than seven days |

## Video outline

- **Suggested title:** Where Your Health Data Actually Goes
- **Hook:** "No cloud. No account. Here's the proof."
- **Demo flow:** read the permission mapping → show a folder export → show a Direct CLI pairing notice.
- **Key screenshot/recording moments:** privacy section, no-backup spool path (debug), seven-day retention copy.
- **CTA / next video:** Direct CLI.

## Implementation notes

Storage roots: `noBackupFilesDir/raw-export` (`RawExportStorage` — "Internal storage rooted exactly at noBackupFilesDir/raw-export") and Direct CLI private spools. Direct CLI retention is bounded to seven days and deleted sooner on cancel/forget. Personal Health Record (FHIR) resources export only when explicitly selected and permitted; history access is used for large manual exports; background access only when scheduling is enabled. Distribution source sets keep Play Billing, Install Referrer, onboarding analytics, Play review, OAuth callbacks, and Wear Data Layer code out of the F-Droid runtime graph and merged manifest. CI also scans the unsigned release APK for forbidden packages. The Android lock-screen widget exclusion (no measurement-bearing lock-screen widgets, since Android lacks Apple-style sensitive-value redaction) is a deliberate privacy decision. The corresponding Apple privacy page documents its own platform flows; semantics are intentionally aligned, never copied.
