---
title: Registro condiviso delle metriche
description: Identità delle metriche multipiattaforma di Health.md e profili di compatibilità.
---

<!-- Generated from packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json. -->

Il registro Rust condiviso contiene metadati contrattuali deterministici, mentre l’acquisizione, le autorizzazioni e i controlli di disponibilità di HealthKit e Health Connect rimangono nativi.

- 248 voci semantiche esplicite
- 230 selezioni Apple v7 ordinate
- 106 selezioni Android ordinate
- 102 identità Android non disponibili o obsolete conservate
- Tre profili di output indipendenti; nessuno schema v8 unificato

| Profilo interno | Profilo pubblico | Schema | Selezioni ordinate | Descrittori di output |
|---|---|---:|---:|---:|
| `apple_health_data_v7` | `apple-v7` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

Il [JSON canonico del registro](/docs/reference/metric-registry-v1.json) è destinato all’ispezione del contratto. Gli ID semantici non sostituiscono mai gli ID di selezione nativi persistenti né le chiavi di output pubbliche.
