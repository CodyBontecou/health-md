---
title: 原始 API 快照
description: 将 Health Connect 记录以及 Fitbit、Oura、WHOOP、Withings 服务商响应导出为不可变、带版本管理的 JSON 或 NDJSON 快照，并附带分类型清单和校验和。
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · 档案级导出</p>
  <p>Raw API Snapshot 是 Health.md for Android 的独立导出产品，面向迁移与归档工作流：每个选定范围生成一个不可变、带版本管理的 JSON 或 NDJSON 工件，并保留原生记录。</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">前往 Google Play 获取</a>
    <a class="docs-button-secondary" href="/zh-hans/docs/android/">Android 应用指南</a>
  </div>
</div>

## 什么是原始快照

兼容性导出会将 Health Connect 记录转换为可读的每日 `HealthData` 摘要。原始快照则完全跳过这一转换：

- **Health Connect 快照**保留锁定的 AndroidX API 暴露的每一个字段，包括原生标识与元数据、纳秒级时间戳、可空来源偏移、原始枚举值、嵌套样本、阶段、路线以及计划锻炼结构。
- **Fitbit、Oura、WHOOP 和 Withings 快照**保留服务商成功响应的确切字节，并披露端点分页与服务器端聚合。不支持的服务商会如实报告，而不会被规范化，也不会被 Health Connect 数据静默替换。
- 每个工件都以一个**清单**结尾，其中包含各类型的状态、问题、数量和校验和。文件夹导出还会获得一个 `.sha256` 附属文件。

原始快照对应用锁定的服务商 API 而言是 API 完整的，但并不是服务商数据库的事务性备份。它无法恢复无法访问的记录、API 未暴露的原始单位、已删除的记录或已安装 SDK 未知的字段。

## 在选择目标前预览

无需配置目标即可预览原始快照。预览会向专用免备份存储执行完整的服务商原生读取，仅在内存中保留有界的开头与结尾文本，并在不上传任何内容的情况下删除临时工件。

## 交付规则

原始 API 上传刻意比兼容性 API 导出更严格：

| 规则 | 原因 |
|---|---|
| 仅限 HTTPS | 流式传输的工件绝不会以明文形式传输 |
| 拒绝重定向 | 工件和凭据绝不会被重放到其他源 |
| 架构、导出和校验和标头 | 接收端点可以验证它接收到的内容 |
| 尝试后删除临时专用工件 | 设备上不会残留任何副本 |

## 增量归档

独立版本管理的 `healthmd.raw-changes` 后端使用 Health Connect 更改令牌和删除墓碑记录，为未来的增量归档工作流奠定基础，因此完整快照不必是唯一的归档策略。

## 要求

- 带有 Raw API Snapshot 产品的 Health.md for Android。
- 所选记录类型的 Health Connect 权限，或用于服务商快照的已连接 Fitbit、Oura、WHOOP 或 Withings 账户。
- 如果上传快照，需要 HTTPS 端点；本地文件夹导出没有任何传输要求。

## 延伸阅读

- [原始快照 v1 契约](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [原始记录 v1 契约](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [原始变更 v1 契约](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
