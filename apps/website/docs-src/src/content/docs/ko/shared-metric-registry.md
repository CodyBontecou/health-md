---
title: 공유 측정 항목 레지스트리
description: 크로스 플랫폼 Health.md 측정 항목 식별자 및 호환성 프로필.
---

<!-- packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json에서 생성되었습니다. -->

공유 Rust 레지스트리에는 결정론적 계약 메타데이터가 포함되며, HealthKit 및 Health Connect의 캡처, 권한, 사용 가능 여부 확인은 네이티브로 유지됩니다.

- 명시적인 의미 체계 행 248개
- 순서가 지정된 Apple v7 선택 항목 230개
- 순서가 지정된 Android 선택 항목 106개
- 보존된 Android 사용 불가/오래된 식별자 102개
- 서로 독립적인 출력 프로필 3개. 통합된 v8 스키마는 없음

| 내부 프로필 | 공개 프로필 | 스키마 | 순서가 지정된 선택 항목 | 출력 설명자 |
|---|---|---:|---:|---:|
| `apple_health_data_v7` | `apple-v7` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

[정규 레지스트리 JSON](/docs/reference/metric-registry-v1.json)은 계약 검토를 위한 것입니다. 의미 체계 ID는 저장된 네이티브 선택 ID 또는 공개 출력 키를 절대로 대체하지 않습니다.
