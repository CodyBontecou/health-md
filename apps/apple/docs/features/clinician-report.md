# Clinician Report

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Settings (Profiles & Reports) on iPhone; Settings on Android
- **Source files:** `HealthMd/iOS/ClinicianReport/`, `HealthMd/Shared/ClinicianReport/`; architecture spec: repository-root `docs/features/clinician-report-v1.md`

## What it does

Clinician Report turns a date range of your health data into a single, accessible PDF you can hand to a clinician — previewed in-app, rendered on-device, and shared only when you explicitly choose to. It summarizes 11 commonly discussed metrics (blood pressure, heart rates, weight, glucose, oxygen saturation, respiratory rate, body temperature, sleep, steps, and workouts) with honest coverage and missingness disclosure, so "no data" never claims an event did not occur.

## Who it is for

- Patients preparing for an appointment who want one tidy document instead of scrolling Apple Health.
- Anyone who wants a shared document with per-reading tables (detail level) or compact summaries (summary level).
- Not for recurring exports: it is a one-report-per-range document workflow, not another scheduled export format. Use export profiles for durable daily files.

## Where to find it

1. Open Health.md → **Settings** tab.
2. Under **Profiles & Reports**, tap **Clinician Report**.
3. Choose a preset range (last 7, 30, or 90 days) or custom start/end dates, select report metrics, pick a detail level, and optionally enter a display name.
4. Tap preview to inspect the report, then **Share** to export the PDF (share sheet / save to Files).

## Prerequisites

- HealthKit read permission for the selected report metrics.
- No vault/folder or export format is required — the report is self-contained.
- iPhone only on Apple (the UIKit sheet is excluded from the macOS target). Android: Settings → Clinician Report.

## Setup

1. Grant the health types you want reflected (see [HealthKit permissions](./healthkit-permissions.md)).
2. Open the Clinician Report sheet and pick your range.
3. Toggle the metrics you want included.
4. Preview, then share or save the PDF.

## Example output

A multi-page tagged PDF: title/date range, per-metric sections with summary facts (count, coverage, median/range, latest), optional tables of timestamped readings with source labels, and a disclosure footer. The share filename follows `<title>_<ISO-start>_<ISO-end>.pdf` and never contains your ephemeral display name.

## Tips

- Blood pressure rows come only from true paired systolic/diastolic records — single unpaired values are omitted rather than guessed.
- The optional display name is ephemeral: it is used in the document only and never persisted or written to the filename.
- Coverage percentages use the inclusive count of calendar days in your range, computed in your device timezone (DST-safe).

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "No data available" for a metric | Permission not granted, or no samples in range | Check HealthKit permissions; widen the range |
| Configuration controls disabled | A preview/render is in progress; config is frozen while busy | Wait, or close to cancel — closing cancels without confirmation |
| Blood pressure count lower than expected | Only trustworthy paired correlations are reported | Expected behavior; unpaired values are excluded |

## Video outline

- **Suggested title:** Bring One Clean Health Summary to Your Next Appointment
- **Hook:** "Your clinician doesn't want 40 screenshots."
- **Demo flow:**
  1. Open Settings → Clinician Report.
  2. Pick 30 days, select BP + resting HR + sleep.
  3. Preview the report, walk a table.
  4. Share to Files/mail.
- **Key screenshot/recording moments:** preview scroll, coverage disclosure line, share sheet.
- **CTA / next video:** Export Profiles for recurring daily files.

## Implementation notes

Four-layer architecture (configuration → report data source → normalized model/generator → native PDF renderer); renderer knows nothing about HealthKit. Apple uses Core Graphics tagged-PDF APIs; Android uses PDFBox-Android logical structure. Local-only: no report networking, analytics, export-history entry, or Practice protocol involvement — the footer `healthmd.app/practice` link is informational. Public export schemas are untouched (no version bump). Known V1 limits: glucose is `mg/dL` only; pulse is not joined to blood pressure; Apple denied-read vs empty-query is indistinguishable, so copy says "unavailable to Health.md". Full boundaries, metric rules, and validation status: repository-root `docs/features/clinician-report-v1.md`.
