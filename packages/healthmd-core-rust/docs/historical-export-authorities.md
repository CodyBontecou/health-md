# Historical export authorities

The consumer outcome is to finish a known pending export under its original authority and reproduce its original bytes. New operations still use the current registry and existing rollout policy. Registry version 1 does not authorize arbitrary digests.

`authority.rs` selects exact embedded bytes by digest and profile. Semantic results retain the configured digest. Render configuration and result must name the same authority; neither pins nor completed results are upgraded. The coarse UniFFI historical snapshot getter applies the same policy. Native Apple/Android planners select that snapshot before adapting captured data and validate the full persisted pin against it and the packaged build.

## Retained shipped v3.4.2 authority

- Source tag: `v3.4.2`, commit `837687662aa2853d1872724c72a97e1526519bbc`.
- Registry SHA-256: `56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99`.
- Profiles: `apple_health_data_v8`, `android_frozen_v4`, `android_analytical_v5`.
- Semantic revision: 1; Apple v8 explicit range grammar also retains revision 2. Render revision: 2. Native core API: 4 (canonical semantic results declare 3, as before).
- Registry snapshot: `registry/metric-registry-shipped-v3.4.2.json`, copied from the tag's `registry/metric-registry-v1.json` without re-encoding.
- Semantic fixture: `packages/contracts/semantic-input/v1/fixtures/historical-shipped-v3.4.2.json`, SHA-256 `fcdf1190d5360e1641b23fbde30ab02016624d2f3b01c70c23b5d6110ca8a439`.
- Render fixture: `packages/contracts/render-input/v1/fixtures/historical-shipped-v3.4.2.json`, SHA-256 `0938986585652b3df4734ed52b3e8b8be3e6122837fb947f83a764e8c56447a2`.

Both fixtures are exact copies of the tag's corresponding `differential-v1.json` git objects. They coexist with current fixtures; never regenerate them. The tag's 248 metric rows and three profiles equal the current inventory. Capability-only additions changed the exact canonical digest, not the data meanings or render revisions.

The current `7b7c3d2b9030c8fbc6db08b4e740922140d7cc2a9b7727461c47ad9baa6fd771` inventory, mappings and capability classifications are unchanged. There is no new public profile, schema, unit, direct-wire or journal version. This compatibility path does not approve any Cloud rollout or change its blockers.

## Recovery and consumers

Unmaterialized scheduled and direct operations retain their exact decoded pins. Nil-pin legacy work does not obtain a new pin. Prepared journals continue replaying stored immutable artifacts/bodies and frontiers without re-rendering, re-capture or migration. Unknown hashes, malformed pins, profile/hash/revision mismatches and unsupported operations fail closed.

Affected producers are the core and native Apple/Android adapters. CLI daily readers already accept Apple v7/v8 and Android v4/v5; no CLI/core workspace or lockfile is combined. Website mirrors remain current-profile inventories rather than rewriting historical authorities. The external Obsidian consumer and native/device rollout gates remain independently required; local core tests cannot qualify them. Serial integration with the pre-v8 restoration must union reviewed exact authority rows, not replace that history or relax hash checks.
