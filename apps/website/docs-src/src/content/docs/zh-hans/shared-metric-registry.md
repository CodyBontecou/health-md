---
title: 共享指标注册表
description: 跨平台的 Health.md 指标标识与兼容性配置。
---

<!-- Generated from packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json. -->

共享 Rust 注册表包含确定性的契约元数据，而 HealthKit 和 Health Connect 的采集、权限与可用性检查仍由原生代码处理。

- 248 个显式语义条目
- 230 个有序 Apple v7 选择项
- 106 个有序 Android 选择项
- 102 个保留的 Android 不可用或过时标识
- 三个独立输出配置；不存在统一的 v8 架构

| 内部配置 | 公开配置 | 架构 | 有序选择项 | 输出描述符 |
|---|---|---:|---:|---:|
| `apple_health_data_v8` | `apple-v8` | 7 | 230 | 226 |
| `android_frozen_v4` | `android-frozen-v4` | 4 | 106 | 161 |
| `android_analytical_v5` | `android-analytical-v5` | 5 | 106 | 161 |

[规范注册表 JSON](/docs/reference/metric-registry-v1.json) 用于检查契约。语义 ID 绝不会替代持久化的原生选择 ID 或公开输出键。
