# Clinician Report

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Settings → Clinician Report
- **Source files:** `app/src/main/java/com/healthmd/presentation/clinicianreport/ClinicianReportScreen.kt`, `app/src/main/java/com/healthmd/presentation/clinicianreport/ClinicianReportViewModel.kt`, `app/src/main/java/com/healthmd/data/clinicianreport/`, `app/src/main/java/com/healthmd/domain/clinicianreport/`

## What it does

Build a private, factual health summary PDF to hand to a clinician. Pick a period (7/30/90 days or custom), choose measurements, optionally add a display name, preview the factual summary, then generate a tagged PDF **entirely on this device** and share or save it.

## Who it is for

- Appointments: one tidy document instead of scrolling Health Connect apps
- Anyone who wants summary-only (compact) or summary + readings (tables) detail
- Not a diagnosis tool — descriptive facts and coverage only, no risk scores or interpretation

## Where to find it

1. Open **Settings**.
2. Tap **Clinician Report** ("Create a private health summary PDF to share with a clinician").
3. Choose the **Report Period**, **Health Measurements**, detail level, and optional display name, then **Preview**.

## Prerequisites

- Health Connect permission for the selected measurements
- No export folder needed — the report is self-contained

## Setup

1. Grant the categories you want reflected.
2. Pick the period and measurements (select at least one measurement to preview).
3. Preview → generate → share or save the PDF.

## Example output

A multi-page tagged PDF: title and period, per-measurement sections with counts, coverage, median/range/latest, optional timestamped reading tables with source labels, and a missingness disclosure. The filename uses the locale-neutral form `<title>_<ISO-start>_<ISO-end>.pdf`; the display name never enters the filename.

## Tips

- Coverage is honest: "no data" means no data was available to Health.md for that period — never that a measurement didn't happen.
- Configuration freezes while preview/rendering is busy; Back cancels without confirmation.
- Blood-pressure rows come only from properly paired systolic/diastolic records.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Select a measurement" | Nothing selected | Tick at least one measurement |
| Section says no data | Permission missing or empty period | Check Health Connect permissions; widen the range |
| Controls disabled | Preview or render in progress | Wait, or Back to cancel |

## Video outline

- **Suggested title:** One PDF Your Doctor Will Actually Read
- **Hook:** "Choose 30 days. Get one document."
- **Demo flow:** pick period + measurements → preview → generate → share.
- **Key screenshot/recording moments:** period chips, preview scroll, share sheet.
- **CTA / next video:** Export History & Retry.

## Implementation notes

Four layers: configuration (`ReportConfiguration`, `ReportDateRangePreset`), data source (`data/clinicianreport/` adapting Health Connect reads with a pinned `ZoneId` — period aggregates are skipped in report mode because Health Connect has no `ZoneId` request; granular reads group from pinned instants and steps aggregate per exact zoned local day), normalized model + generator (`domain/clinicianreport/`), and the PDFBox-Android renderer with a genuine logical structure tree (`AndroidClinicianReportPdfRenderer`; tagged PDF, not a PDF/UA claim). Files live under `cacheDir/clinician-reports`, are published by atomic rename, and partial artifacts are deleted on cancellation. Configuration (including display name) is never persisted or added to export history. Architecture spec: [Clinician Report v1](../../../../docs/features/clinician-report-v1.md).
