# Health Context Profiles

Health Context Profiles are durable access policies for Health.md data requests. A profile independently identifies its policy schema, revision, allowed callers and surfaces, metric and provider scope, summary or lossless detail, date policy, confirmation rule, expiration, and destination binding.

Profiles do not impose arbitrary data-volume or time-range limits. A profile can explicitly allow:

- `all_available` metrics, which dynamically includes metrics added by future Health.md versions;
- every available source/provider;
- lossless detail; and
- `all_history` as a first-class value, without fake start or end dates.

An explicit selected-metric or selected-provider scope is frozen at that revision. Newly supported metrics and providers are not silently added to explicit selections. Large authorized requests are made resource-safe downstream through streaming, pagination, partitioning, and resumable persistence, not by denying a valid profile.

## Execution pinning

Before work starts, the pure resolver verifies the exact profile ID, revision, canonical SHA-256 policy digest, caller, surface, destination, expiration, confirmation, and runtime-supported metric/provider set. The resulting immutable execution policy pins those values together with the exact resolved request. Explicit, caller-provided, and relative dates become exact bounded intervals. All-history remains an explicit unbounded value.

Unknown policy schema versions and unknown caller or surface values can be decoded for inspection and migration, but execution fails closed. Corrupt or unsupported profile-store documents are also never reset or accepted implicitly.

## Separate from HealthKit and exports

A Health Context Profile answers whether a particular Health.md caller may request a particular context. It does **not** grant Apple HealthKit authorization; HealthKit permission is still requested and enforced separately by the operating system. It also does not inherit or alter saved export formatting, enabled-metric preferences, file templates, or destination settings. Callers must resolve a profile explicitly, and resolution never falls back to current export settings.

This policy schema is independent from the public Health.md export schema and does not change `HealthMdExportSchema.version`.
