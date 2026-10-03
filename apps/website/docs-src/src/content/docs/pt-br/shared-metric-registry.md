---
title: Registro compartilhado de métricas
description: Identidades de métricas e perfis de compatibilidade multiplataforma do Health.md.
---

<!-- Generated from packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json. -->

O registro Rust compartilhado contém metadados determinísticos de contrato, enquanto a captura, as permissões e as verificações de disponibilidade do HealthKit e do Health Connect continuam nativas.

- 248 linhas semânticas explícitas
- 230 seleções ordenadas do Apple v8
- 106 seleções ordenadas do Android
- 102 identidades indisponíveis/obsoletas do Android preservadas
- Três perfis de saída independentes; não existe um schema v8 unificado

| Perfil interno | Perfil público | Schema | Seleções ordenadas | Descritores de saída |
|---|---|---:|---:|---:|
| `apple_health_data_v8` | `apple-v8` | 8 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

O [JSON canônico do registro](/docs/reference/metric-registry-v1.json) destina-se à inspeção de contratos. IDs semânticos nunca substituem IDs de seleção nativos persistidos nem chaves públicas de saída.
