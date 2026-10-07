---
title: "快捷指令与 App Intents"
description: "在快捷指令和 Siri 中使用 7 个 Health.md 操作。Mac 上下文刷新操作仅为提案，尚不可用。"
---

<div class="availability preview"><strong>源码中注册了 7 个操作</strong><p>Refresh Mac Health Context 和 Get Mac Context Refresh Status 仅为提案，尚未实现，在开发版中也不可用。请关注<a href="https://github.com/CodyBontecou/health-md/issues/173">问题 #173</a>；提供这些操作需要实现、验证以及明确的 Apple 版本发布说明。</p></div>

## 操作

- 导出昨天、指定日期、日期范围或最近 N 天；
- 获取健康摘要或最近导出状态；
- 开启或关闭计划任务。

### 提议的 Mac 上下文操作（尚不可用）

请求的 **Refresh Mac Health Context** 操作应使用明确的配置文件与日期范围、经过认证的兼容设备以及持久上下文获取，不生成导出文件，也不消耗文件导出配额。**Get Mac Context Refresh Status** 应报告待处理、完成或失败状态，并提供可恢复的任务标识。这些是需求，不是当前应用支持的操作名称、参数或返回结果。

电脑端 MCP 刷新不能满足 iOS 个人自动化需求。不要用普通导出快捷指令代替：它们仍然保留 iPhone 文件夹语义。任何自动化都不能承诺唤醒休眠的 Mac 或绕过受保护的 HealthKit 数据。在验证此功能前，仍需在唤醒后的真实 iPhone 上进行个人自动化 QA。

四个导出操作可接受可选的**配置文件**。未知名称会安全失败，不会回退。普通快捷指令写入 iPhone 文件夹，不会静默切换到 API Endpoint 或 Connected Mac。

允许锁定时运行不会解锁 HealthKit。Health.md 会保留请求并显示 **Health Export Needs Attention**。

### 早晨自动化

1. 创建定时自动化。
2. 添加 **Export Yesterday's Health Data**。
3. 添加 **Get Last Export Status** 和通知。

“昨天”包含昨晚开始的睡眠。参阅[睡眠日期](/zh-hans/docs/sleep-date-attribution/)。

<div class="related"><a href="/zh-hans/docs/export-profiles/"><span>配置文件</span>稳定标识。</a><a href="/zh-hans/docs/release-status/"><span>兼容性</span>检查版本。</a></div>
