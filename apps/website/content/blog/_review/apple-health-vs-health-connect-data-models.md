# Cross-platform data model explanation verification

Verified: 2026-10-27 by Codex (agent), method: traced.

No new producer/consumer behavior, schema or fixture change; no native/device or visual QA. This article explains existing contracts.

## Claims

- [x] Proven-equivalence mappings use shared outcomes/semantic IDs while platform-specific data retains distinct identities. Source: `docs/architecture/cross-platform-unification-policy.md`, `packages/contracts/product-capabilities.json`, and the maintained shared metric/platform references. Unsupported is not fabricated parity.
- [x] Daily sleep compatibility summaries use a local noon-to-noon journal window, distinct from raw-record ownership. Apple HealthKitManager sleepWindow/fetchSleepData, Apple export-schema Day ownership, Android SleepJournalSummary and its normative export-contract document establish this. The article's former start-date shorthand is corrected without changing the implementation.
- [x] Apple public schema-v8 canonical HealthKit documents and Android provider-native raw snapshots are distinct artifacts, not private database backups. Evidence: `apps/apple/docs/features/export-schema.md`, Android export-contract compatibility documentation, and `docs-src/src/content/docs/guides/raw-snapshots.md`. A summary and archive serve separate consumer purposes.
- [x] Missing, unsupported, empty, failed and partial outcomes have different meanings, but HealthKit's read-privacy behavior prevents determining some denied states from empty results. Apple's authorization documentation and the Apple export-schema capture guidance establish the limit. The article now qualifies reported states rather than promising permission inference.
- [x] Units, timezone, source, schema profile and coverage must accompany values. Evidence: cross-platform unification policy and export format/capture references. No claim that similar field spelling alone proves semantic equivalence; no unit, schema key or exporter output was changed.
