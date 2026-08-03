---
title: Android 应用
description: 设置 Android 版 Health.md，将 Health Connect 数据导出为 Markdown、Obsidian Bases、JSON 和 CSV，选择 Storage Access Framework 文件夹，设置计划导出，并通过 Tasker 或 adb 实现自动化。
---

<div class="docs-hero">
  <p class="docs-eyebrow">从 Health Connect 到私有文件</p>
  <p>Android 版 Health.md 在设备上读取 Health Connect，并将 Markdown、Obsidian Bases、JSON 或 CSV 写入您选择的文件夹。无需 Health.md 账户，不使用健康数据云服务，也无需订阅。</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">前往 Google Play 获取</a>
    <a class="docs-button-secondary" href="/zh-hans/docs/export/">阅读导出文档</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>个可选 Health Connect 指标</span></div>
<div><strong>4</strong><span>种导出格式</span></div>
<div><strong>10</strong><span>次免费手动导出</span></div>
<div><strong>0</strong><span>个必需的 Health.md 云账户</span></div>
</div>

## Android 应用的功能

Android 版 Health.md 将 Health Connect 转化为本地优先的健康日志。选择您关注的指标，预览输出，然后将整洁的文件导出到本地文件夹、Obsidian 知识库、同步服务提供方文件夹，或任何授予写入权限的 Android 文档提供方。

<div class="options">
  <div class="option"><strong>Health Connect 数据源</strong><p>通过 Android 的设备端 Health Connect API 读取活动、睡眠、心脏、生命体征、身体测量、营养、锻炼及其他类别的数据。</p></div>
  <div class="option"><strong>Obsidian 原生输出</strong><p>写入每日笔记、YAML/frontmatter、适用于 Obsidian Bases 的笔记、单独条目，以及与 Health.md Obsidian 插件兼容的 JSON。</p></div>
  <div class="option"><strong>Android 原生存储</strong><p>使用 Storage Access Framework，让您可以选择本地存储、Obsidian、Google Drive、OneDrive、Syncthing 或其他提供方公开的文件夹。</p></div>
</div>

## 系统要求

- Android 9 / API 28 或更高版本。
- 支持 Health Connect 的设备或模拟器。
- 来自向 Health Connect 写入数据的 Android 应用、可穿戴设备或服务的 Health Connect 数据。
- 允许导出文件写入的文件夹或文档提供方。

## 首次导出

1. 从 Google Play 安装 Health.md。
2. 打开 **Health Connect** 设置，仅授予 Health.md 需要导出的类别权限。
3. 通过 Android 文件夹选择器选择导出目标位置。
4. 选择格式：Markdown、Obsidian Bases、JSON、CSV，或任意组合。
5. 选择指标和日期范围。
6. 预览输出。
7. 轻点导出，然后在文件夹或知识库中确认生成的文件。

免费方案包含 10 次手动导出，让您可以在解锁无限导出前测试权限、文件夹访问、格式和 Obsidian 工作流。

## Android 上的目标位置

Android 不使用 iPhone → Mac 本地网络目标位置，而是依赖 Android 的 Storage Access Framework。

| 目标位置 | Android 支持情况 |
|---|---|
| 本地设备文件夹 | 支持通过文件夹选择器访问 |
| Obsidian 知识库 | 当知识库文件夹可通过 Android 选择器访问时支持 |
| Google Drive、OneDrive、Syncthing、Obsidian Sync 及类似提供方 | 当提供方公开可写文件夹时支持 |
| iPhone/Mac 本地网络目标位置 | Apple 平台专用；Android 不使用 |

如果提供方未通过 Android 选择器公开可写文件夹，Health.md 就无法安全地直接写入。请选择授予持久写入权限的提供方文件夹，或先导出到本地，再使用您偏好的工具同步。

## 格式

Android 应用与 Apple 应用遵循相同的纯文件设计目标：

| 格式 | 适用场景 |
|---|---|
| Markdown | 易读的每日健康摘要、模板和笔记 |
| Obsidian Bases | 以 frontmatter 为主、可在 Obsidian 数据库视图中查询的笔记 |
| JSON | 供脚本、仪表板、笔记本和 Health.md Obsidian 插件使用的结构化每日数据 |
| CSV | 电子表格和数据分析工作流 |

Android JSON 导出旨在与 Health.md 的 Obsidian 可视化兼容。Markdown 和 Bases 导出采用[格式指南](/zh-hans/docs/format/)中介绍的 frontmatter 工作流。

## 计划与自动化

当您授予 Android“闹钟和提醒”权限时，计划导出会使用一次性精确闹钟，并以持久的 WorkManager 工作作为后备。如果没有精确闹钟权限，WorkManager 将成为主要调度器，因此所选时间只是目标时间，无法严格保证。Health.md 会记录导出历史、恢复错过的计划日期，并允许您重试失败的运行。

对于 Tasker、adb 或其他自动化工具，Health.md 提供仅限显式调用的广播 intent。外部调用方必须直接指定接收器组件：

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

示例：

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

自动化会使用您当前的导出设置、所选文件夹、格式、指标选择、免费/付费导出额度和历史记录。

## 健康数据源

Health Connect 是默认的本地导出路径。Android 应用还提供健康数据源设置区域，支持 Samsung Health、Huawei Health、Fitbit、Garmin、Withings、Oura、Polar 和 WHOOP 等生态系统。当这些生态系统将数据写入 Health Connect 时，Health.md 可以导出相应的 Health Connect 记录。直接从云服务提供方导入需要提供方授权，并且可能有额外的设置或可用性限制。

受支持的提供方中有意不包含 Google Fit，因为 Health Connect 是 Android 首选的健康数据层。

## 定价与恢复购买

- Android 应用包含 10 次免费手动导出。
- 通过 Google Play Billing 一次性购买 Full Access，即可解锁无限导出和计划自动化。
- 无需订阅，也没有周期性收费。
- Google Play 会在购买前显示当前本地价格。
- “恢复购买”会使用购买 Full Access 的 Google 账户。

## 隐私模式

Android 版 Health.md 采用本地优先模式：

- Health Connect 记录在您的 Android 设备上读取。
- 导出文件直接写入您选择的文件夹。
- Health.md 不运行健康数据云服务。
- 设置和导出历史保留在设备上。
- 付款由 Google Play 处理。
- 由提供方管理的文件夹会按照相应提供方的条款同步。

如需最严格的本地设置，请手动导出到本地设备文件夹，并关闭计划导出和由提供方管理的同步。

## 相关文档

<div class="related">
  <a href="/zh-hans/docs/export/"><span>导出</span>手动导出流程、日期范围、预览、历史记录和文件输出。</a>
  <a href="/zh-hans/docs/metrics/"><span>指标</span>Health.md 各平台上的指标选择和类别工作方式。</a>
  <a href="/zh-hans/docs/format/"><span>格式</span>Markdown、Bases、JSON、CSV、单位、文件名和 frontmatter。</a>
  <a href="/zh-hans/docs/visualizations-roadmap/"><span>Obsidian</span>导出的 JSON 和 Markdown 如何驱动 Health.md 可视化。</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">最后更新于 2026-08-03</p>
