---
title: 共有指標レジストリ
description: Health.mdのクロスプラットフォーム指標IDと互換性プロファイル。
---

<!-- packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.jsonから生成。 -->

共有Rustレジストリには、決定論的なコントラクトメタデータが含まれます。一方、HealthKitとHealth Connectのデータ取得、権限、利用可否の確認は、引き続き各プラットフォームのネイティブ実装が担当します。

- 明示的なセマンティック行248件
- 順序付きApple v7選択項目230件
- 順序付きAndroid選択項目106件
- 維持されるAndroidの利用不可／旧ID 102件
- 独立した出力プロファイル3種類。統合v8スキーマはありません

| 内部プロファイル | 公開プロファイル | スキーマ | 順序付き選択項目 | 出力記述子 |
|---|---|---:|---:|---:|
| `apple_health_data_v7` | `apple-v7` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

[正規のレジストリJSON](/docs/reference/metric-registry-v1.json)は、コントラクトを確認するためのものです。セマンティックIDが、永続化されたネイティブ選択IDや公開出力キーを置き換えることはありません。
