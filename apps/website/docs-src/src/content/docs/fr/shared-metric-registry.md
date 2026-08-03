---
title: Registre partagé des métriques
description: Identités multiplateformes des métriques Health.md et profils de compatibilité.
---

<!-- Generated from packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json. -->

Le registre Rust partagé contient des métadonnées de contrat déterministes. La collecte, les autorisations et les contrôles de disponibilité de HealthKit et Health Connect restent propres à chaque plateforme.

- 248 entrées sémantiques explicites
- 230 sélections Apple v7 ordonnées
- 106 sélections Android ordonnées
- 102 identités Android indisponibles ou obsolètes conservées
- Trois profils de sortie indépendants ; aucun schéma v8 unifié

| Profil interne | Profil public | Schéma | Sélections ordonnées | Descripteurs de sortie |
|---|---|---:|---:|---:|
| `apple_health_data_v7` | `apple-v7` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

Le [registre JSON canonique](/docs/reference/metric-registry-v1.json) permet d’examiner les contrats. Les ID sémantiques ne remplacent jamais les ID de sélection natifs persistants ni les clés de sortie publiques.
