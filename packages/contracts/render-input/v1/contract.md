# `healthmd.render_input` v1 and artifact-plan v1

Status: canonical internal contract
Public exports preserved: Apple `healthmd.health_data` v7, Android frozen v4, Android analytical v5

## Purpose

`healthmd.render_input` is the destination-neutral boundary between a completed `healthmd.semantic_result` v1 session and profile-specific Rust rendering. It is not a public health export and is never written into a user destination.

The render boundary exists separately from semantic input because exact public rendering also needs frozen presentation settings, profile-specific source detail, explicit locale-sensitive strings, filenames, and opaque native structures retained by semantic tokens. Moving renderer code does not change a shipped public schema.

## Authority and ownership

Rust owns after this boundary:

- profile-specific frontmatter/Bases, Markdown, CSV, summary JSON, and roll-up byte rendering;
- deterministic format and row ordering, escaping, omission, whitespace, line endings, and checksums;
- validated relative-path and artifact planning;
- Markdown managed-section merge behavior;
- individual-entry and Daily Note mutation plans;
- API envelope construction and exact encoded-byte batching;
- bounded stream framing and checksums for lossless records and attachments.

Native Swift/Kotlin continues to own:

- HealthKit, Health Connect, and provider capture;
- platform availability, permissions, localization lookup, and lifecycle;
- freezing settings and resolving locale-sensitive labels/date/time substitutions;
- joining semantic retention tokens to typed native side tables;
- security-scoped URLs, Android SAF, destination reads, atomic writes, ZIP containers, HTTP, authentication, and durable transport;
- deciding whether a destination side effect is allowed.

A render session consumes the same frozen capture and completed semantic result. It may not query health APIs or reinterpret persisted selection IDs.

Revision 2 keeps all generated public-profile bytes and schemas unchanged while hardening the profile-owned managed-Markdown merge operation. It preserves complete YAML property blocks, distinguishes quoted string keys from implicitly typed plain keys, rejects ambiguous ownership explicitly, and routes the compatibility Apple merge entry point through the profile implementation.

## Independent versions

| Field | v1 value |
|---|---:|
| `render_input_version` | 1 |
| `artifact_plan_version` | 1 |
| `canonical_model_version` | 1 |
| metric registry | 1 |
| profile implementation revision | 2 |

The UniFFI core API advances independently. Render input v1 does not alter semantic input v1 or the public schema/profile versions.

## Session model

A render session is created from:

1. bounded render configuration;
2. exact completed `healthmd.semantic_result` v1 bytes.

It accepts ordered batches of presentation facts and retained extension payloads, then finalizes one artifact plan. Batches are transactional: malformed or cancelled input does not advance the expected batch index. A session is terminal after completion or observed cancellation.

Configuration and semantic result must agree on request/session identity, profile, profile revision, registry hash, canonical model version, calendar timezone, and owner dates. Android roll-up input is rejected. Android API v1 is rendered only from `android_frozen_v4`; analytical-v5 local settings cannot silently upgrade API/plugin output.

## Presentation facts

Each daily metric fact references an `output_key` accepted by the matching completed semantic day. It carries only presentation data that semantics cannot reconstruct:

- category identity and resolved label;
- public/frontmatter key and JSON placement;
- exact public JSON scalar or structured value;
- display lexeme and public unit;
- optional exact rendered timestamp;
- deterministic ordinal.

The public value is validated against its accepted output key and bounded shape. It is not permission to add a metric filtered by the semantic session. Missing and explicit zero remain distinct.

Exact native profile structures may additionally cross as bounded presentation documents: an explicitly ordered JSON tree with numeric lexemes, typed CSV cells, and a line-oriented Markdown body. These are presentation facts, not opaque finished artifacts: Rust still owns escaping, indentation, delimiters, newline assembly, and checksums. Any such document must attest exactly the accepted `semantic_output_keys` for its owner day; duplicates, missing keys, or stale/additional keys fail transactionally. Native callers must provide the already-filtered frozen export snapshot so platform-only compatibility fields follow the same persisted settings.

Locale-sensitive labels and substitutions are explicit inputs. Render v1 accepts the reviewed `en-US` renderer vocabulary; adding locale behavior requires a render-input revision and independent goldens.

## Native extension payloads

A profile-specific structure that is not safely generalized crosses only after its M4 retention token was accepted. Each payload:

- references exactly one retained token;
- repeats the selected native IDs used for fail-closed overlap validation;
- has a stable source ordinal;
- may add a typed public JSON field/value, typed CSV rows, structured Markdown blocks, or bounded attachment artifacts.

Unretained, duplicate, selection-disjoint, or disabled extension payloads are rejected. A retained token with no payload emits nothing; Rust never fabricates source detail. Apple HealthKit archives and Android granular/provider/workout/PHR structures remain explicit profile extensions rather than fake shared fields.

## Artifact plan

`healthmd.artifact_plan` v1 returns an ordered list. Every inline artifact contains:

- deterministic domain-separated `artifact_id`;
- validated POSIX `relative_path`;
- media type and logical format;
- write mode (`overwrite`, `append`, `markdown_merge`, or `api_post`);
- exact bytes;
- byte count and lowercase SHA-256.

Native code must verify the descriptor before side effects. It must not rewrite content, normalize line endings, or choose another path after planning.

A streamed artifact finalizes as the content-free item shape in `stream-artifact-plan-item.schema.json`: the same domain-separated ID, validated path, media type, write mode, byte count, and SHA-256, while bytes have already been delivered incrementally to the native spool. `api_post` is not accepted for planned streams.

### Paths

Paths are relative POSIX paths. Rust rejects:

- absolute paths, backslashes, NULs, and empty paths;
- empty, `.` or `..` components;
- traversal and unresolved template markers;
- duplicate targets;
- targets colliding after Unicode normalization and case folding.

Destination roots and platform URL/URI identities never cross as logical path components.

### Write behavior

`update` means managed Markdown merge only. Structured JSON, CSV, and Bases artifacts use overwrite. Destination reads remain native; existing bounded UTF-8 Markdown is passed to the pure merge operation. Append and merge replay must be idempotent when the same content is already present.

## API envelopes

API planning uses final encoded envelope bytes, not estimates. Every requested owner date must resolve to exactly one successful record or one failure. Records, failures, and Apple provider sidecars are partitioned together by owner date and grouped by the configured day and byte bounds. Failure-only batches are retained. One indivisible day may exceed the target and is emitted alone. Requests are sequential native side effects; Rust returns only `api_post` artifacts.

Apple envelopes preserve the deployed API envelope version and v7 daily records. Android API v1 declares frozen daily schema v4 even when analytical v5 is selected for local files. URLSession/HTTP clients, credentials, headers, redirects, retries, and response handling remain native.

## Bounded lossless streaming

Large Apple archive JSON/CSV records and attachment bytes use a separate synchronous bounded stream object. The stream accepts at most one bounded record/chunk per call and immediately returns the framed output chunk. It retains only sequence state, SHA-256 state, and byte count—never the complete artifact.

Supported framing is raw bytes, JSON-array items, and RFC 4180 rows. Finalization emits the closing frame plus an artifact descriptor. Native code writes returned chunks into its existing atomic spool/ZIP pipeline. Cancellation and malformed input are terminal and health-free.

## Limits

| Item | Limit |
|---|---:|
| configuration | 256 KiB |
| completed semantic result | 32 MiB |
| one render batch | 2 MiB |
| facts per batch | 4,096 |
| owner dates | 400 |
| artifacts per plan | 4,096 |
| one ordinary inline artifact | 8 MiB |
| one indivisible API envelope | 32 MiB |
| total inline artifact bytes | 32 MiB |
| one stream item | 1 MiB |
| one stream | 2 GiB |

Oversized public source layers must use the stream API; limits may not be bypassed by base64 nesting.

## Determinism and comparison

For fixed input bytes, profile revision, and settings, rendering is independent of environment locale, timezone, filesystem, and current time. Any generated timestamp is explicit input.

Equivalence is exact:

- ordered path list;
- media and write mode;
- complete bytes, byte count, and SHA-256;
- JSON key/number ordering;
- CSV rows, quoting, delimiters, and trailing newline;
- Markdown/YAML whitespace and line endings.

Production mismatch diagnostics contain only versions, profile, counts, lengths, hashes, and first differing byte offset. Fixtures are synthetic and contain no production health data.

## Golden provenance

Renderer fixtures are frozen from the existing production Swift/Kotlin exporters before Rust authority. They are not generated by Rust or parsed/re-encoded. Existing Apple v5/v6/v7 and Android v4/v5 structural signature fixtures remain immutable and independent.

A profile is eligible for M6 shadow mode only after every format and destination-neutral plan in its reviewed corpus matches byte-for-byte. M5 does not switch production authority.
