---
title: Shared metric registry
description: Cross-platform Health.md metric identities and compatibility profiles.
---

<!-- Generated from packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json. -->

The shared Rust registry contains deterministic contract metadata while HealthKit and Health Connect capture, permissions, and availability checks remain native.

- 248 explicit semantic rows
- 230 ordered Apple v7 selections
- 106 ordered Android selections
- 102 preserved Android unavailable/stale identities
- Three independent output profiles; no unified v8 schema

| Internal profile | Public profile | Schema | Ordered selections | Output descriptors |
|---|---|---:|---:|---:|
| `apple_health_data_v7` | `apple-v7` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

The [canonical registry JSON](/docs/reference/metric-registry-v1.json) is intended for contract inspection. Semantic IDs never replace persisted native selection IDs or public output keys.
