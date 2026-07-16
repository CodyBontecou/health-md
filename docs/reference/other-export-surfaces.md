# Other export surfaces

Several Health.md features trigger or present the same production exports without defining a new health-data schema.

## Export Preview

Preview executes the configured exporter against the selected day and displays the resulting files before writing. Preview content follows the same JSON, CSV, Markdown, and Bases contracts documented in this reference.

A preview is not proof that every HealthKit query will remain available during a later export. Check the final file's capture status and diagnostics.

## Daily Note Injection

Daily Note Injection merges selected flat summary/frontmatter values into an existing Obsidian daily note. It draws from the same `ExportDataSnapshot`, metric mapping, frontmatter key customization, units, and schema-v7 diagnostics used by Markdown/Bases.

It does not inject the complete canonical archive. Use the companion JSON/CSV file for exact source records.

User renames affect the written `key`; the data dictionary retains `canonicalKey` for cross-vault integrations.

## Apple Shortcuts and App Intents

Shortcut export intents invoke Health.md's ordinary export orchestration for a date, yesterday, last N days, or a date range. They do not define a separate daily file schema.

Shortcut status/summary results are automation convenience values. Any files produced still follow the selected production format contracts. A shortcut reporting that an action completed does not replace per-day archive/query diagnostics.

## Scheduled exports

Scheduled exports use the same selected metrics, formats, schema versions, and lossless setting. Scheduling adds lifecycle/retry state, not a different health-data shape.

When HealthKit is protected or the device cannot complete work, pending dates are retained for retry. A later successful action should still be evaluated per daily capture status.

## Export Preview and serialization errors

Preview-friendly convenience methods can render an explicit serialization-error object/string when canonical encoding fails. Production writers use throwing paths and fail the affected date rather than silently dropping an unencodable record.

Do not ingest a `health-data-serialization-error` fallback as a normal daily record.

## Mac Destination and Manual IP

Nearby Mac Destination and paired Manual IP/Tailscale deliver the same captured job through different encrypted transports. Both use the connected request/result contracts and Mac-side shared exporters.

Transport choice does not change daily JSON/CSV/Markdown/Bases semantics.

## Provider sidecars

Enabled third-party integrations can add provider-specific external records to an API envelope or file job. Provider sidecars declare their own schema/version and do not mutate `healthmd.health_data` v7 or `healthmd.healthkit_records` v1.

Consumers should branch on provider identity/schema and retain unknown provider records separately from Apple Health source records.

## Export history

Export history records operational outcomes such as dates, target, files, failures, and retry state. It is app state, not a health-data export contract. Do not use history success as a substitute for reading final capture diagnostics.

## Archives and containers

Compression or connected-transfer spooling changes packaging, not the objects inside. Validate the inner declared schema after extraction/reassembly.

## Contract reuse summary

| Surface | Unique health-data schema? | Authoritative output |
|---|---:|---|
| Manual export | No | Selected daily/roll-up formats. |
| Export Preview | No | Preview of the selected production exporter. |
| Daily Note Injection | No | Flat summary/frontmatter projection. |
| Apple Shortcuts export intents | No | Selected production files. |
| Scheduled exports | No | Selected production files plus operational retry state. |
| Mac Destination | No | Shared Mac-written production files. |
| Manual IP/Tailscale | No | Same connected job over paired transport. |
| API Endpoint | Yes, envelope only | `healthmd.api_export` wrapping daily records. |
| Mac CLI strict raw | Yes, result envelope only | `healthmd.raw_result` wrapping daily records. |
| Provider integration | Provider-specific sidecar | Independently versioned external records. |
| Roll-ups | Yes | `healthmd.rollup_summary`. |
