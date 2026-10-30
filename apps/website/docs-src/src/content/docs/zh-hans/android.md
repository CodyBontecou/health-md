---
title: "安卓应用程序"
description: "为 Android 设置Health.md 。导出Health Connect数据，选择存储访问框架文件夹，计划导出，并使用 Tasker 或 adb 实现自动化。"
---

<div class="docs-hero">
 <p class="docs-eyebrow"> Health Connect到私有文件</p>
 <p> Health.md for Android 读取设备上的Health Connect并将Markdown 、 Obsidian Bases、JSON 或 CSV 写入您选择的文件夹。此文件夹导出工作流程不需要Health.md帐户。 Google Play访问选项和F-Droid包含的访问如下所述。 </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">继续Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droid发布状态</a>
 <a class="docs-button-secondary" href="/zh-hans/docs/export/">阅读导出文档</a>
 </div>
 <p id="distribution-status"> F-Droid目录发布待定。在Google Play上获取当前的 Android 版本。 </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> <span>可选Health Connect指标</span> </div>
 <div> <strong> 4 </strong> <span>导出格式</span> </div>
 <div> <strong> 2 </strong> <span> Android 分发渠道</span> </div>
 <div> <strong> 0 </strong> <span> Health.md需要云帐户</span> </div>
 </div>

## Android 应用程序的作用

Android 版Health.md将Health Connect变成本地首屈一指的健康日志。选择您需要的指标并预览输出。然后将文件导出到本地文件夹、 Obsidian保管库、同步提供程序文件夹或可写 Android 文档提供程序。

<div class="options">
 <div class="option"> <strong> Health Connect源</strong> <p>通过 Android 设备上Health Connect API 读取活动、睡眠、心脏、生命体征、身体测量、营养、锻炼和其他类别。 </p> </div>
 <div class="option"> <strong> Obsidian -本机输出</strong> <p>编写每日笔记、YAML/frontmatter、 Obsidian基础友好笔记、个人条目和与Health.md Obsidian插件兼容的 JSON。 </p> </div>
 <div class="option"> <strong> Android 原生存储</strong> <p>使用存储访问框架，因此您可以选择本地存储、 Obsidian 、Google Drive、OneDrive、Syncthing 或其他提供商公开的文件夹。 </p> </div>
 </div>

## ＃＃ 要求

- Android 9 / API 28 或更高版本。
- 具有Health Connect功能的设备或模拟器。
- Health Connect来自写入Health Connect的 Android 应用程序、可穿戴设备或服务的数据。
- 允许导出写入访问的文件夹或文档提供程序。

## 第一次导出

1. 从Google Play安装当前的Health.md版本。
2. 打开 ** Health Connect ** 设置并仅授予您想要Health.md导出的类别。
3. 通过 Android 的文件夹选择器选择导出目的地。
4. 选择格式： Markdown 、 Obsidian基础、JSON、CSV 或任意组合。
5. 选择指标和日期范围。
6. 预览输出。
7. 点击导出并验证文件夹或保管库中生成的文件。

支持订阅的Google Play手机版本需要有效试用、订阅、终身或保留手动导出的永久访问权限。符合条件的订阅包括 7 天试用期；一生没有考验。 F-Droid版本包括无限访问，无需购买或恢复流程。

## Android 上的目的地

Android 不使用iPhone → Mac 本地网络目标。相反，它依赖于 Android 的存储访问框架。

| 目的地 | 安卓状态 |
| --- | --- |
| 本地设备文件夹 | 通过文件夹选择器支持 |
| Obsidian金库 | 当库文件夹暴露给 Android 的选择器时支持 |
| Google Drive、OneDrive、Syncthing、 Obsidian Sync 和类似提供商 | 当提供程序公开可写文件夹时受支持 |
| iPhone /Mac 本地网络目标 | Apple 平台特定； Android 不使用 |

如果提供程序不通过 Android 的选择器公开可写文件夹，则Health.md无法直接在那里安全地写入。选择一个授予持久写入访问权限的提供程序文件夹，或在本地导出并与您的首选工具同步。

## 格式

Android 应用程序与 Apple 应用程序具有相同的纯文件目标：

| 格式 | 用它来 |
| --- | --- |
| Markdown | 可读的每日健康摘要、模板和注释 |
| Obsidian Bases | 可以在Obsidian数据库视图中查询的 Frontmatter-first 注释 |
| JSON | 脚本、仪表板、笔记本和Health.md Obsidian插件的结构化日常负载 |
| CSV | 电子表格和分析工作流程 |

Android JSON 导出旨在与Health.md的Obsidian可视化兼容。 Markdown和 Bases 导出使用 [格式指南](/zh-hans/docs/format/) 中记录的相同的以 frontmatter 为中心的工作流程。

## 调度和自动化

在支持订阅的Google Play手机版本中，计划导出需要有效试用、订阅、终身或保留的永久访问权限；它们包含在F-Droid版本中。当您授予 Android 的闹钟和提醒访问权限时，它们会使用一次性精确闹钟，并以持久的WorkManager工作作为备份。如果没有精确警报访问， WorkManager将成为主要调度程序，因此所选时间是一个目标而不是硬性保证。 Health.md记录导出历史记录，可以恢复错过的计划日期，并允许您重试失败的运行。

对于 Tasker、adb 或其他自动化工具， Health.md公开仅显式广播意图。外部调用者必须直接寻址接收器组件：

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

自动化默认使用活动配置文件，包括其冻结目的地、格式、指标、会计和历史记录。提供的`PROFILE` extra 可以选择稳定的配置文件 ID 或名称。未知参考无法关闭，而不是使用当前设置。预定的跑步也与他们的个人资料绑定。请参阅[导出配置文件](/zh-hans/docs/export-profiles/)。

### 后台准备和预定取消

- 允许后台Health Connect读取无人值守导出。否则打开Health.md来完成健康数据读取。
- 保持通知启用状态，以便 Android 可以显示活动工作、前台服务状态、结果和恢复操作。
- 仅当您需要精确的警报安排时才授予警报和提醒。如果没有它，持久的WorkManager工作仍然可用，但选择的时间是近似的。
- 取消计划的运行只会停止该尝试。已完成的日期保持完整，未解决的日期可以重试，并且重复计划保持启用状态。

## 健康来源

Health Connect是两个通道中的本地导出路径。 Google Play版本还包括三星健康、华为健康、Fitbit、Garmin、Withings、Oura、Polar 和 WHOOP 等生态系统的健康源设置区域。当这些生态系统写入Health Connect时，任一构建都可以导出生成的Health Connect记录。直接云提供商导入和 OAuth 回调仅供播放。 F-Droid提供程序目录仅包含Health Connect 。

Google Fit 被故意排除在受支持的提供商表面之外，因为Health Connect是 Android 的首选健康数据层。

### 当地当天的准确步数

每日步数总计使用精确的分区本地日边界。在聚合之前， Health.md在当地午夜剪辑并分割重叠的Health Connect间隔。因此，旅行和夏令时的更改不会将步骤移至错误的日期。

## 分销、定价和转换

- ** Google Play ：** 支持订阅的手机版本提供个人每周/每年订阅和终身订阅。符合条件的首次订阅者将获得 7 天试用期，然后按显示的价格自动续订，直到通过Google Play取消。终身立即充值一次，无需试用。当地自由出口补贴已不复存在。现有的永久访问权限将被保留。恢复购买使用购买的 Google 帐户；删除应用程序或购买终身不会取消订阅。较早发布的版本可以显示以前的津贴。当前版本仅适用于手机。 Wear OS 配套产品将推迟到稍后的资格周期。
- ** F-Droid ：** 包括无限访问。没有免费计数器、计费依赖性、付费专区、购买或恢复操作。
- ** F-Droid范围：** 仅Health Connect ，没有 Wear OS 集成、直接云提供商 OAuth、Play 审核、归因或Health.md入门遥测。
- **共享结果：** 两个通道使用相同的Health Connect捕获、导出器、架构、自动化操作和直接设备协议。
- **切换：** Google Play和F-Droid使用不同的签名密钥，因此更改频道需要先卸载应用程序。

频道切换不会迁移购买、设置、历史记录、凭证或私人​​传输状态。导出的文件保留在您选择的目标位置。

如果Google Play Billing 暂时断开连接，Play 构建会重新连接并自动刷新权利状态。暂时的服务损失不会永久删除高级服务。仅当连接恢复后帐户仍未解决时才使用“恢复购买”。

## 隐私模型

Android 的Health.md是本地优先的：

- Health Connect记录在您的 Android 设备上读取。
- 导出内容直接写入您选择的文件夹。默认情况下，
- 核心文件夹导出和直接设备查询不会创建Health.md服务器副本。
- 设置和导出历史记录保留在设备上。
- 计费由 Play 版本中的Google Play处理。 F-Droid包括无计费的无限制访问，并且不包含Health.md遥测代码或遥测身份/状态。
- 提供商支持的文件夹根据该提供商自己的条款进行同步。

如果您想要最严格的本地设置，请运行手动导出到本地设备文件夹并禁用计划导出和提供商支持的同步。

另行提供的可选 Health.md Cloud 试点仅供单一所有者使用，只保留主动上传的 API 导出。不开放公众注册，不自动同步设备；此文件夹流程不会上传至该试点。保留、删除、容量配额和无备份导致的丢失风险见[隐私政策](/privacy-policy.html)。

## 相关文档

<div class="related">
 <a href="/zh-hans/docs/export-profiles/"> <span>配置文件</span>保存独立的目标、输出设置、计划和稳定的自动化 ID。 </a>
 <a href="/zh-hans/docs/export/"> <span>导出</span>手动导出流程、日期范围、预览、历史记录和文件输出。 </a>
 <a href="/zh-hans/docs/metrics/"> <span>指标</span>指标选择和类别如何在Health.md中发挥作用。 </a>
 <a href="/zh-hans/docs/format/"> <span>格式</span> Markdown 、基础、JSON、CSV、单位、文件名和 frontmatter。 </a>
 <a href="/zh-hans/docs/visualizations-roadmap/"> <span> Obsidian </span>导出的 JSON 和Markdown如何增强Health.md可视化效果。 </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">最后更新于 2026 年 10 月 4 日</p>
