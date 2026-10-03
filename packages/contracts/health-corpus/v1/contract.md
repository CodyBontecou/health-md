# Health.md full public and authorized corpus contract v1

## Scope

`all_public_authorized` means every health record type and field that:

1. is exposed through the platform's public SDK or provider API;
2. is supported by the current Health.md mobile integration and operating-system version; and
3. the user has authorized Health.md to read.

It never means an Apple, Google, or provider-private database. Health.md must not infer, fabricate, or report inaccessible data as exported. Apple and Android artifacts remain platform-native; related-but-different records do not acquire a shared semantic identity merely because they use this scope.

## Completeness

The artifact is the authoritative completeness manifest. Producers must preserve enough native evidence to distinguish these semantic outcomes wherever the platform can expose them:

- `exported`: one or more readable records were emitted;
- `empty`: the authorized query completed with no records;
- `permission_not_granted`: required read authorization was not granted or cannot be demonstrated;
- `unsupported`: the current platform, OS, provider, or Health.md build does not support the type;
- `feature_unavailable`: a public feature exists but is disabled or unavailable in this product/build;
- `skipped`: the type was intentionally not attempted, with a reason;
- `partial`: only part of the requested type or attachment set was emitted;
- `read_error`: a read failed, with bounded health-free diagnostics.

Native envelopes may use more specific status names. Consumers must preserve those native values and map them to the semantic outcomes above only when the evidence is unambiguous. Omission is not proof of `empty` or `exported`. A job-level `success` means the durable job completed and validated; it does not mean every type contained readable records. `partial_success` remains a distinct terminal corpus outcome.

## Apple realization

The iPhone request uses direct application protocol v1 with:

- `response_mode = raw_json`;
- `raw_profile = health_data_projection`;
- `canonical_selection.all_metrics = true`;
- `canonical_selection.source_ids = ["apple_health"]`;
- lossless detail and the canonical `healthkit_record_archive` object.

The iPhone resolves `all_metrics` against `HealthMetrics.availableInCurrentBuild`, independently of saved/default metric selections, before HealthKit reads. The resulting `healthmd.raw_result` and schema-v8 `healthmd.health_data` documents retain daily capture manifests, canonical records, relationships, attachments, metadata, query statuses, missing dates, warnings, partial failures, and read failures. Public capabilities not available in the current build remain unavailable rather than being fabricated.

## Android realization

The Android request uses direct application protocol v2 and `android_provider_native_snapshot_v1` with:

- one explicit provider ID, defaulting to `health_connect`;
- `scope = all_authorized_supported_data`;
- JSON or NDJSON, with `auto` selecting NDJSON for Android;
- `include_exercise_routes = true` by default for this scope.

The provider-native snapshot retains its authorization snapshot, inventory, issues, records, fields, and attachment/route outcomes. Exercise routes that require interactive per-session consent may remain unavailable because local MCP cannot launch that consent UI. Android records are never converted to HealthKit-shaped documents.

## CLI and local MCP

The shell form is:

```text
healthmd export <date-selection> --raw --full-corpus [--output PATH]
```

The complete local stdio MCP surface provides:

- `healthmd_export_raw` to start the approval-gated durable job;
- `healthmd_export_job_status`, `healthmd_export_job_resume`, and `healthmd_export_job_cancel` for its lifecycle;
- `healthmd_raw_artifact_read` to inspect an exact completed job artifact.

A raw artifact read is bound to one durable job UUID, revalidates the stored byte count and SHA-256, accepts a nonnegative byte offset, returns at most 65,536 bytes, and encodes the chunk as base64. It never accepts a filesystem path. Artifacts use the existing private seven-day job spool and existing protocol resume semantics.

The local read-only stdio, Streamable HTTP, and OAuth profiles must neither list nor invoke raw-corpus or artifact-read operations. Whole-corpus transfer belongs to the CLI or durable spool; MCP inspection remains bounded and must not inject a multi-gigabyte artifact into one model response.

## Versioning

This contract adds an explicit host operation and scope over deployed iOS v1 and Android v2 raw products. It does not change either mobile wire protocol, the Apple export schema version, the Android provider-native snapshot schema, or the shared metric registry. A future change that alters those wire or artifact contracts must version the affected contract independently.
