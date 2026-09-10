---
title: 各平台功能概览
description: Health.md 在 iPhone、iPad、Mac、Android、Wear OS 和 CLI 上的功能——共享能力与如实标注的平台差异。
---

<div class="docs-hero">
  <p class="docs-eyebrow">平台概览</p>
  <p>Health.md 在 iPhone、iPad、Mac、Android、Wear OS 和 CLI 上分别能做什么——在平台允许之处保持一致，在不同之处如实呈现。</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone 与 Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

**Wear OS 条目是计划中的功能，不包含在当前 Google Play 版本中。**

图例：✓ 可用 · ◐ 可用，但存在行中注明的平台差异 · △ 计划中或 QA 中 · ? 不声明可用性 · — 该平台不可用。

CLI 并不是一个独立的健康数据平台列：CLI 功能出现在自动化相关的行中，并保留其 iPhone 或 Android 来源的语义。

## 设置与权限

| 功能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 健康数据权限（精确选择要读取的内容） | ✓ Apple Health 类型 | ◐ 通过已配对的 iPhone / Mac 目标读取 | ✓ Health Connect 类别 | — |
| 选择导出目标位置 | ✓ Obsidian 知识库、iCloud Drive、文件 | ✓ 本地文件夹 | ✓ 任意 Android 文件夹提供程序（Drive、OneDrive、Syncthing、Obsidian Sync…） | — |
| 带示例预览的初始设置 | ✓ | ✓ | ✓ | — |
| Share My Setup（在设备间迁移偏好设置） | △ QA 中 | △ QA 中 | △ QA 中 | — |

## 读取与导出

| 功能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 每日导出为 Markdown、Obsidian Bases、JSON、CSV | ✓ | ✓（文件从 iPhone 送达） | ✓ | — |
| 225+ 项 Apple Health 指标 / 106 项 Health Connect 指标 | ✓ | ✓ | ✓ | — |
| 写入前预览 | ✓ | ✓ | ✓ | — |
| 具有独立设置的已保存导出配置文件 | ✓ 在 iPhone 上管理；? 不声明支持 iPad 管理 | ? 不声明支持管理 | ✓ 在 Android 上管理 | — |
| 每周 / 每月 / 每年汇总摘要 | ✓ | ✓ | △ 计划中；需要单独评审的 Android 架构配置（现有 v4/v5 保持不变） | — |
| 导出历史与重试 | ✓ | ✓ | ✓ | — |
| 在不禁用计划的前提下停止或取消当前运行 | ✓ 已完成的日期保留；未解决的日期可重试 | ✓ | ✓ 已完成的日期保留；未解决的日期可重试 | — |
| 单次运行的 ZIP 归档 | ✓ | ✓ | — | — |
| 摘要数据细节 | ✓ | ✓ | ✓ | — |
| 所选指标的详细时间序列 | ✓ | ✓ | ✓ | — |
| 无损健康记录的规范来源归档 | ✓ `healthmd.healthkit_records` | ✓ | — 仅限 Apple；请改用原始 API 快照 | — |
| 原始 API 快照导出（不可变的 JSON/NDJSON） | — | — | ✓ Health Connect + Fitbit、Oura、WHOOP、Withings | — |

## 高级数据

| 功能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 单项条目跟踪（锻炼、睡眠阶段、生命体征） | ✓ | ✓ | ✓ | — |
| 锻炼详情（在支持处提供完整图表和路线） | ✓ | ✓ | ✓ | — |
| 心情 / State of Mind 导出 | ✓ | ✓ | —（Health Connect 中无对应项） | — |
| 用药剂量事件 | ✓ | ✓ | —（Health Connect 中无对应项） | — |
| 血压、血糖、血氧、体温读数 | ✓ | ✓ | ✓ | — |
| 第三方提供方数据 | ◐ 导出中的 WHOOP 部分（测试版） | ◐ | ✓ 提供方原生原始快照 | — |

某些数据在各平台间刻意**不作为等价数据处理**：心率变异性在 Apple 上为 SDNN，在 Android 和 WHOOP 上为 RMSSD——Health.md 将它们保留为不同的指标，而不是混为一谈。Apple Watch 的手腕温度与 Health Connect 的皮肤温度也同样保持独立。

## 自动化与集成

| 功能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 定期计划导出 | ✓ 通知 + APNs 回退 | ✓ | ✓ WorkManager（+ 可选精确闹钟）、开机恢复 | — |
| 系统自动化 | ✓ 快捷指令 / Siri / App Intents | — | ✓ Tasker、adb、显式广播 Intent | — |
| 将导出发送到您自己的 HTTP(S) API 端点 | ✓ | — | ✓ 支持加密存储请求头 | — |
| 独立 CLI（`healthmd`）配对 | ✓ 前台直接服务 | ✓ 内置 + 独立 | ✓ 20 位配对码 | — |
| 直接 CLI 请求唤醒 | ✓ 有限等待 + 可选开启的 APNs | ✓ CLI 发起 | ◐ 有限等待；FCM 计划中 | — |
| 面向 AI 智能体的 MCP 服务器 | ◐ 通过 Mac 内置提供；类型化的便携直接 MCP 仅限 iPhone | ✓ 内置 `healthmd-mcp` | — 不支持类型化的直接 MCP | — |

## 设备与一览界面

| 功能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 主屏幕小组件 | ✓ 摘要、活动圆环、心率区间、睡眠 | — | ✓ 摘要、活动、心率区间、睡眠（以步数替代站立时长） | — |
| 导出进度的实时活动 | ✓ | — | — | — |
| 手表界面 | ✓ 手表应用 + 10 种复杂功能 | — | — | △ 计划在 1.10.0 推出 |
| 以 Mac 作为导出目标（加密本地传输） | ✓ iPhone 发送 | ✓ 接收 | — | — |

## 购买与隐私

| 功能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 免费档 | ✓ 10 次手动或计划导出操作 | — | ✓ 10 次手动导出操作 | — |
| 解锁 | ✓ 一次性终身买断（个人 / 家庭） | ◐ 同一 Apple 解锁 | ✓ 一次性终身买断，含计划功能 | — |
| 本地优先隐私 | ✓ 无 Health.md 健康数据云端 | ✓ | ✓ | △ 计划中 |
| 临床医生报告（就诊用单个 PDF） | ✓ | — | ✓ | — |

Health.md 不运营任何健康数据云端。健康数据只可能存在于您选择的目标位置、加密的本地上下文，以及受限的私密传输状态中。每个文件夹、Mac、API 端点或 CLI 目标都需显式配置。配置文件与计划保留在创建它们的设备本地。各平台的工作流程请参阅[导出配置文件](/zh-hans/docs/export-profiles/)、[Android 指南](/zh-hans/docs/android/)和 [iPhone 导出指南](/zh-hans/docs/export/)。
