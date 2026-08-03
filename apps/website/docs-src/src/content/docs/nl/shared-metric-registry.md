---
title: Gemeenschappelijk meetwaarderegister
description: Platformonafhankelijke Health.md-identiteiten voor meetwaarden en compatibiliteitsprofielen.
---

<!-- Generated from packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json. -->

Het gemeenschappelijke Rust-register bevat deterministische contractmetadata. Vastlegging, machtigingen en beschikbaarheidscontroles in HealthKit en Health Connect blijven systeemeigen.

- 248 expliciete semantische rijen
- 230 geordende Apple v7-selecties
- 106 geordende Android-selecties
- 102 behouden niet-beschikbare of verouderde Android-identiteiten
- Drie onafhankelijke uitvoerprofielen; geen gemeenschappelijk v8-schema

| Intern profiel | Openbaar profiel | Schema | Geordende selecties | Uitvoerbeschrijvingen |
|---|---|---:|---:|---:|
| `apple_health_data_v7` | `apple-v7` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

De [canonieke JSON van het register](/docs/reference/metric-registry-v1.json) is bedoeld voor contractinspectie. Semantische ID's vervangen nooit opgeslagen systeemeigen selectie-ID's of openbare uitvoersleutels.
