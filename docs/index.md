# Health.md Docs

## Technical export reference

- [Complete export reference](./reference/index.md): Stripe-style user/developer documentation for every format, field family, canonical record, diagnostic, API/CLI response, connected message, and generated synthetic showcase.
- [Generated examples](./reference/generated/): complete JSON, CSV, Markdown, Bases, Individual Entry, roll-up, CLI, API, and connected-protocol fixtures produced by the real serializers.

## Export architecture

- [Export schema contract](./features/export-schema.md): current schema v6, canonical `healthmd.healthkit_records` v1 archive, completeness, ownership, and migration guidance.
- [Lossless Health Records](./features/time-series-data.md): default source-record capture, format roles, practical limits, and the legacy `includeGranularData` key.
- [JSON export](./features/json-export.md): authoritative embedded canonical archive.
- [CSV export](./features/csv-export.md): canonical records as RFC 4180-safe JSON rows.
- [Markdown](./features/markdown-export.md) and [Obsidian Bases](./features/obsidian-bases.md): readable summaries plus capture diagnostics/counts.
- [Mac Destination](./features/mac-sync.md) and [Mac CLI](./features/cli-mac-iphone-export.md): bounded connected transfer and strict raw profile.

## More documentation

- [Feature documentation](./features/index.md): full user-facing feature inventory and video planning.
- [Privacy and local-first design](./features/privacy-local-first.md): what stays local, what can leave the device, and lossless-data sensitivity.
- [Experiment runbooks](./experiments/index.md): pricing and product experiment plans, gates, and results logs.
- [Testing docs](./testing/TODO-INDEX.md): internal testing plans and quality gates.
