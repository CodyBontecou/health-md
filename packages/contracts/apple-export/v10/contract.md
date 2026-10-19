# Apple `healthmd.health_data` v10

Status: canonical Apple profile. This is not the deferred unified daily v9 grammar.

Apple v10 advances the Apple v8 layout to accommodate independently versioned [WHOOP v2 physiological-cycle steps](../../provider-sections/v2/contract.md). The schema remains `healthmd.health_data`; `schema_version` becomes `10`. Primary Apple Health keys, units, reducers, selection IDs, raw HealthKit archive v1, and native provider sidecar v1 remain unchanged. WHOOP never replaces primary Apple Health summaries or creates WHOOP-only daily records.

## Independent identities

- Public profile: `apple-v10`.
- Internal profile: `apple_health_data_v10`.
- Shared core/UniFFI API: 5; semantic input/result, canonical model, and render-input/artifact-plan grammars keep their existing independent versions.
- Metric registry: exact frozen v1 bytes and SHA-256. The [Apple-v10 profile extension](../../../healthmd-core-rust/crates/healthmd-core/registry/apple-health-data-v10-profile-v1.json) derives the identical primary metric catalog and output mappings from `apple_health_data_v8`, without rewriting registry v1 or its pinned Shared Setup/semantic fixtures.
- WHOOP section: v2 for new captures; v1 remains readable for retained legacy captures.
- New range summaries: separately versioned `healthmd.rollup_summary` v10, source daily version 10, reduction rules version 8. WHOOP cycle steps remain excluded.

Apple v8/WHOOP v1, Android frozen v4/analytical v5, historical roll-up v8/v9, and the unified daily v9 proposal retain their identities and fixtures. Android does not emit Apple v10 or claim typed WHOOP-cycle parity.

## Producer and consumer boundary

The current native JSON, Markdown, Bases, CSV, dictionary and API-record writers identify daily v10. Provider-bearing rendering remains native-authoritative. Provider-free shared Rust rendering requires an explicit v10 profile; explicit historical v8 Rust rendering continues to produce its frozen v8 bytes. API envelope versions v1/v2 and direct transfer/query/pairing wire grammar are unchanged.

Affected consumers are the Apple/Android native bridges, shared core, portable CLI raw/file receivers, website documentation/gallery tooling, opt-in cloud ingestion/MCP/dashboard, and external Obsidian plugin. Readers must dispatch by known version, not numeric `<= 10`: unified daily v9 is still unreviewed. WHOOP cycle counts remain provider facts, not additions to primary metric catalogs or cloud aggregate-only step charts.

Cloud metric-specific repair drafts/supplement scopes remain explicitly pinned to their existing reviewed v8 contract and are not widened by this migration. Generic v10 ingestion, exact-original field inspection and reviewed primary-summary reads do not grant repair, device, upload, or third-party read authority.

## Durable authority

New nonlegacy export jobs pin the v10 profile and core API 5. The v10 runtime keys are separate from v8 rollout keys. Decoding historical pins retains their original profile, public version and core API; it does not migrate them to v10. A persisted nonlegacy v8/core-4 pin is incompatible with the current planner and must stop before writes/network commits, not silently downgrade or resume as v10. Start a newly reviewed export if the original renderer is unavailable. Already attested/completed files remain unchanged.

## Qualification and release order

Preserve all historical signatures and fixtures. Generate a new `export_schema_signature_v10.json` using the Apple signature command, validate the profile/provider/roll-up inventory and native binding generation, and run affected producer/consumer regressions, including v8 and WHOOP-v1 reads. Use synthetic payloads for local verification.

Publish/deploy compatible external readers before releasing or enabling v10 writers against them. Local source qualification does not establish compatibility of an already deployed cloud receiver, installed Obsidian plugin, older connected Apple app, or live WHOOP account. Simulator/device/live-provider QA and releases/deployments require separate authorization.
