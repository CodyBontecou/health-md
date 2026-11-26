---
title: "How to export Apple Watch ECG recordings (PDF and raw data)"
description: "Export an Apple Watch ECG as a PDF for your doctor in Health, or export recordings as JSON data files with Health.md's Lossless Health Records, voltage waveform included."
lead: "For one recording, use Health → Browse → Heart → Electrocardiograms (ECG) → Export a PDF for Your Doctor. For the data itself, Health.md can write ECG recordings into daily JSON files in a folder you choose."
date: "2026-11-26"
updated: "2026-11-26"
category: "Workflow guide"
platform: apple
related:
  - export-apple-health-heart-rate
  - export-apple-health-hrv
  - export-apple-health-data-pdf
draft: false
verified: "2026-11-26"
verified_by: "Claude (agent)"
verified_method: traced
tags:
  - apple-health
  - ecg
  - json
  - export
---

To send one Apple Watch ECG to a doctor, use the PDF that the Health app creates. It takes about a minute and needs no extra app. If you want the numbers instead of a picture, Health.md can export ECG recordings as data files; that route is further down.

## Short answer: export an ECG as a PDF

Apple's support article [Take an ECG with the ECG app on Apple Watch](https://support.apple.com/en-us/120278) gives these steps:

1. Open the **Health** app on your iPhone.
2. Tap the **Browse** tab, then tap **Heart**.
3. Tap **Electrocardiograms (ECG)**, then tap the chart for the recording you want.
4. Tap **Export a PDF for Your Doctor**, then tap the Share button to print or share the PDF.

The PDF is for the one recording you opened. Repeat the steps for each additional recording.

## What an Apple Watch ECG recording contains

Apple documents ECG recordings in HealthKit as [`HKElectrocardiogram`](https://developer.apple.com/documentation/healthkit/hkelectrocardiogram) samples. They carry a classification, an average heart rate, a symptoms status, a sampling frequency and the number of voltage measurements. The voltage series is a single lead, which Apple describes as similar to Lead I. Apps read the voltages with an [`HKElectrocardiogramQuery`](https://developer.apple.com/documentation/healthkit/hkelectrocardiogramquery).

This guide describes the data only. It does not interpret any recording.

## PDF or data file: which do you need?

| | PDF from the Health app | Data file from Health.md |
| --- | --- | --- |
| Best for | Showing a clinician | Analysis or archiving |
| Form | A rendered tracing, fixed | Machine-readable JSON, with the voltage values |
| Scope | One recording at a time | Recordings across a date range, one file per day |
| Raw numbers | No | Yes |

## Export ECG data with Health.md (iPhone)

Health.md reads recordings stored in Apple Health; it does not take ECGs. The metric catalog lists **Electrocardiograms** under Heart as "Source archive only": the data lives in the Lossless Health Records archive.

1. Install [Health.md](https://apps.apple.com/us/app/health-md/id6757763969) and grant Health read access, including **Electrocardiograms**. See [your first iPhone export](/docs/iphone-first-export/) if setup is incomplete.
2. Choose **JSON** as the format and turn on **Lossless Health Records** (see [Export options](/docs/export/) and the [format guide](/docs/format/)).
3. Select a short date range around the recordings you want, pick a folder, and export.
4. Open that day's JSON file and look in `healthkit_record_archive` for records whose `record_kind` is `electrocardiogram`. The values are under `payload.fields`: `classification`, `average_heart_rate` and `voltage_measurements`.

A fictional record, modeled on the [published fixture](/docs/reference/generated/core/specialized-records/) and cut down to the relevant fields (a real recording has far more voltage entries):

```json
{
  "record_kind": "electrocardiogram",
  "object_type_identifier": "HKDataTypeIdentifierElectrocardiogram",
  "start_date": "2026-03-15T00:20:00.125000000Z",
  "payload": {
    "kind": "electrocardiogram",
    "type": "structured",
    "fields": {
      "average_heart_rate": { "type": "floating_point", "value": 72 },
      "classification": { "type": "string", "value": "sinus_rhythm" },
      "voltage_measurements": {
        "type": "array",
        "value": [
          { "type": "floating_point", "value": 0.12 },
          { "type": "floating_point", "value": 0.18 }
        ]
      }
    }
  }
}
```

Use a [Python script](/blog/apple-health-to-python/) or a JSON-aware tool to read it. Because ECG is archive-only, it does not appear as a summary line in Markdown or CSV daily summaries. If you choose CSV with Lossless Health Records on, the canonical objects appear as JSON cells, as the [canonical records reference](/docs/reference/canonical-healthkit-records/) explains.

ECG files are large. Keep the date range short, as the [API endpoint guide](/docs/api-endpoint/) advises for ECGs.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Export your ECG recordings as data files</a>

## Limits and gotchas

- **Apple only.** The archive is Apple-only; Android Health Connect has no equivalent in Health.md.
- **Only what Apple exposes.** Health.md reads public APIs and does not infer ECG lead internals ([canonical records reference](/docs/reference/canonical-healthkit-records/)).
- **Recordings must be in Apple Health** and read permission granted. An empty result can look the same as denied access, because Apple protects read privacy.
- **Integrity warnings.** The archive can carry warnings, for example for a missing voltage quantity or a count mismatch. Check them before relying on a file ([diagnostics reference](/docs/reference/query-manifests-and-diagnostics/)).
- **Saved recordings only.** HealthKit supplies recordings already saved, not a live stream.
- **Not medical advice.** A data file is not a diagnosis, not a 12-lead ECG, and Health.md is not a medical device. If you have symptoms, follow Apple's guidance and contact a doctor.

A heart-rate number in bpm is not a waveform; see the [heart rate guide](/blog/export-apple-health-heart-rate/) and the [HRV guide](/blog/export-apple-health-hrv/). For a clinician-oriented summary of other measurements, see [Apple Health data as a PDF](/blog/export-apple-health-data-pdf/).

## Protect ECG files

ECG data is sensitive. Health.md's local folder export writes files to the folder you choose; a synced folder or any service you upload to follows that provider's rules. Do not paste payloads into issue reports or chats. The separate Health.md Cloud pilot is opt-in, single-owner and not generally available; the folder workflow here does not use it.

## FAQ

**Can I export all my ECGs at once with Apple's tools?** The Health app's PDF is per recording. Apple's Export All Health Data makes a full archive; see the [Apple Health XML export guide](/blog/apple-health-xml-export/). This guide doesn't claim what that archive holds for ECGs.

**Does the PDF include the raw numbers?** No. It is a rendered tracing. The voltage values are in the data file.

**Can I get live ECG data?** No. Only saved recordings are available through HealthKit.
