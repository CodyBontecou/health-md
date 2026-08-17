---
title: Registro de métricas compartido
description: Identidades de métricas de Health.md entre plataformas y perfiles de compatibilidad.
---

<!-- Generado desde packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json. -->

El registro compartido de Rust contiene metadatos de contrato deterministas, mientras que la captura, los permisos y las comprobaciones de disponibilidad de HealthKit y Health Connect siguen siendo nativos.

- 248 filas semánticas explícitas
- 230 selecciones ordenadas de Apple v7
- 106 selecciones ordenadas de Android
- 102 identidades de Android no disponibles u obsoletas preservadas
- Tres perfiles de salida independientes; no hay un esquema v8 unificado

| Perfil interno | Perfil público | Esquema | Selecciones ordenadas | Descriptores de salida |
|---|---|---:|---:|---:|
| `apple_health_data_v8` | `apple-v8` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

El [JSON canónico del registro](/docs/reference/metric-registry-v1.json) está pensado para inspeccionar contratos. Los ID semánticos nunca sustituyen los ID de selección nativos persistidos ni las claves públicas de salida.
