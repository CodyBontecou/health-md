# Apple Health XML export claim verification

Verified: 2026-10-27 by Codex (agent), method: traced.

This is a documentation-traced explainer. No device export, archive extraction, converter installation/execution, comparative benchmark, browser/device QA or screenshots were performed. The new page processes no uploaded file. The fictional interval is authored for explanation, not a fixture from a real archive or a complete XML schema example.

## Claims

- [x] Apple Health exports XML through Health → Summary → profile → Export All Health Data. Evidence checked 2026-10-27: https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios . The selected metric/date workflow is Health.md's separate picker (`apple-health-export/index.html`, `docs-src/src/content/docs/export.md`), not a native archive conversion feature.
- [x] Native export ZIP and export.xml naming, converter inputs/outputs and example record fields are documented by the converter author: https://github.com/muquit/applehealth2csv . Its README accepts ZIP or XML, shows per-metric CSV/JSON output and sourceName, type, unit, creationDate, startDate, endDate and value. No current-schema completeness, reliability, endorsement benchmark, or execution claim is made. No download/install command or real health record is copied into this article.
- [x] ZIP extraction instructions follow the owning OS vendors: iPhone Files https://support.apple.com/102532 ; Mac Finder https://support.apple.com/guide/mac-help/zip-and-unzip-files-and-folders-on-mac-mchlp2528/mac ; Windows Extract All https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/zip-and-unzip-files . Extraction does not transform XML into CSV. These are documented workflows, not UI-qualified steps.
- [x] Health.md reads authorized device data, writes selected daily CSV/JSON/Markdown/Bases output, and does not import native XML archives. Evidence: `apple-health-export/index.html`, `docs-src/src/content/docs/export.md`, `format.md`, `daily-notes.md`. Lossless Health Records is a separate selected-source-record representation with capture status, not Apple XML or a private database copy: `docs-src/src/content/docs/reference/canonical-healthkit-records.md` and the public format reference. No export contract or native capability changes.
- [x] The CSV sample is synthetic and has Health.md's own row contract, not the converter's format. Evidence: `apps/apple/docs/reference/generated/core/summary-day.csv`, the published byte-identical reference, and `docs-src/src/content/docs/reference/export-formats.md`. The authored 25-step interval at 09:00–09:05 is explicitly fictional and not a day total; no measurement or source completeness is inferred. Existing sleep, steps and CSV guides establish the need to distinguish aggregates, samples, units and overlapping records.
- [x] Five export actions followed by lifetime access is the documented Apple offer: `docs-src/src/content/docs/paywall.md`. The app/store link is the existing verified Health.md destination. Android has its own guide and is not presented as an XML-compatible or semantically identical producer.

## Publication and measurement

One new English blog URL owns the existing-archive/open-export.xml intent. The existing export hub still owns the broad Apple Health export workflow; the CSV hub owns fresh selected CSV. Both hubs and the guide directory link contextually to this page. The fixed `xml_export` acquisition ID reuses existing page-view, CSV sample and store events, with no raw URLs, health values, visitor IDs or new event type. Deploy the updated campaign Worker from committed source before pushing main to publish the page. No D1 migration is required.

This is the next documented acquisition experiment, not a claim of verified search volume, rankings or conversion lift. Publication evidence and measurement notes belong in the primary checkout's ignored `.pi/seo-xml-export-oct27/`, not the deployed site.
