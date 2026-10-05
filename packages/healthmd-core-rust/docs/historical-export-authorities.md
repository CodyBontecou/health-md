# Historical export authorities

The consumer outcome is to finish a known pending export under its original authority and reproduce its original bytes. New operations still use the current registry and existing rollout policy. Registry version 1 does not authorize arbitrary digests.

`authority.rs` selects exact embedded bytes by digest and profile. Semantic results retain the configured digest. Render configuration and result must name the same authority; neither pins nor completed results are upgraded. The coarse UniFFI historical snapshot getter applies the same policy. Native Apple/Android planners select that snapshot before adapting captured data and validate the full persisted pin against it and the packaged build.

## Retained pre-v8 authority

- Source: `c77024b87170260531f8df8fc5b604ad35375466`.
- Registry SHA-256: `b988fa9a0fea4cf3a0768ee6ad89251a15386c87eb929ce1e46b136fd33b1f4b`.
- Profiles: `apple_health_data_v7`, `android_frozen_v4`, `android_analytical_v5`.
- Semantic revision: 1. Render revision: 1. Native core API: 4 (canonical semantic results declare 3, as before).
- Registry snapshot: `registry/metric-registry-pre-v8-c77024b.json`, copied from the source object's `registry/metric-registry-v1.json` without re-encoding.
- Semantic fixture: `packages/contracts/semantic-input/v1/fixtures/historical-pre-v8-c77024b.json`, SHA-256 `0f5c8dfc6e52759c7b671082bfd5121253f1907d5af97ad1ec4f2c6bb9fefb7e`.
- Render fixture: `packages/contracts/render-input/v1/fixtures/historical-pre-v8-c77024b.json`, SHA-256 `59fee27e488f76da193d8013fba4ff82d76887fe12df45439ea7de286feb4bc3`.

Both fixtures are exact copies of the corresponding `differential-v1.json` git objects. They coexist with current fixtures; never regenerate them. Apple v7 daily/API and calendar-rollup implementations retain their historical schema labels and artifact identities. V7 cannot acquire the newer range grammar or typed WHOOP section. The provider-free native presentation adapter changes only owned schema metadata when resuming v7; authentic independent Swift v7 goldens remain the oracle.

The current `56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99` inventory, metric mappings and capability classifications are unchanged. There is no new public profile, schema, unit, direct-wire or journal version. This restoration is not a rollout approval.

## Recovery and consumers

Unmaterialized scheduled, Direct CLI and Connected Mac operations retain their exact decoded pins. Nil-pin legacy work does not obtain a new pin. Prepared journals continue replaying stored immutable artifacts/bodies and frontiers without re-rendering, re-capture or migration. Unknown hashes, malformed pins, profile/hash/revision mismatches and unsupported operations fail closed.

Affected producers are the core and native Apple/Android adapters. CLI daily readers already accept Apple v7/v8 and Android v4/v5; no CLI/core workspace or lockfile is combined. Website mirrors remain current-profile inventories rather than rewriting historical authorities. The external Obsidian consumer and native/device rollout gates remain independently required; local core tests cannot qualify them. Integration with capability-only registry changes must union reviewed exact authority rows, not replace this history or relax hash checks.
