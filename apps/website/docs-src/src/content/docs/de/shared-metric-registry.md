---
title: Gemeinsames Metrikregister
description: Plattformübergreifende Metrikidentitäten und Kompatibilitätsprofile von Health.md.
---

<!-- Generated from packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json. -->

Das gemeinsame Rust-Register enthält deterministische Vertragsmetadaten, während Erfassung, Berechtigungen und Verfügbarkeitsprüfungen für HealthKit und Health Connect nativ bleiben.

- 248 explizite semantische Zeilen
- 230 geordnete Apple-v7-Auswahlen
- 106 geordnete Android-Auswahlen
- 102 beibehaltene nicht verfügbare oder veraltete Android-Identitäten
- Drei unabhängige Ausgabeprofile; kein vereinheitlichtes v8-Schema

| Internes Profil | Öffentliches Profil | Schema | Geordnete Auswahlen | Ausgabedeskriptoren |
|---|---|---:|---:|---:|
| `apple_health_data_v7` | `apple-v7` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

Das [kanonische Register als JSON](/docs/reference/metric-registry-v1.json) dient zur Prüfung des Vertrags. Semantische IDs ersetzen niemals gespeicherte native Auswahl-IDs oder öffentliche Ausgabeschlüssel.
