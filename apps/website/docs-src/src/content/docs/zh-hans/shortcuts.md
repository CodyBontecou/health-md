---
title: "快捷指令与 App Intents"
description: "在快捷指令和 Siri 中使用 7 个已发布操作，以及开发源码中的 2 个 Mac 上下文操作。"
---

<div class="availability preview"><strong>已发布 7 个操作 · 当前源码 9 个</strong><p>两个 Mac 上下文操作要求兼容的 iPhone/Mac 构建。请查看准确版本的发布说明。</p></div>

## 操作

- 导出昨天、指定日期、日期范围或最近 N 天；
- 获取健康摘要或最近导出状态；
- 开启或关闭计划任务；
- **Refresh Mac Health Context**（开发中）：发起绑定配置文件的持久加密上下文刷新；
- **Get Mac Context Refresh Status**（开发中）：读取状态和 job ID。

四个导出操作可接受可选的**配置文件**。未知名称会安全失败，不会回退。普通快捷指令写入 iPhone 文件夹，不会静默切换到 API Endpoint 或 Connected Mac。

允许锁定时运行不会解锁 HealthKit。Health.md 会保留请求并显示 **Health Export Needs Attention**。

### 早晨自动化

1. 创建定时自动化。
2. 添加 **Export Yesterday's Health Data**。
3. 添加 **Get Last Export Status** 和通知。

“昨天”包含昨晚开始的睡眠。参阅[睡眠日期](/zh-hans/docs/sleep-date-attribution/)。

<div class="related"><a href="/zh-hans/docs/export-profiles/"><span>配置文件</span>稳定标识。</a><a href="/zh-hans/docs/release-status/"><span>兼容性</span>检查版本。</a></div>
