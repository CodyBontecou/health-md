---
title: "睡眠日期与每日笔记"
description: "了解夜间睡眠为何归属于开始日期，以及早晨应导出哪个范围。"
---

Health.md 将睡眠时段归到它**开始的日期**。周一 23:45 到周二 7:30 的睡眠属于周一摘要。即使 Health Connect 显示起床日期，Apple 与 Android 仍使用这一规则。

| 目标 | 导出 |
|---|---|
| 周二早晨查看昨晚睡眠 | **昨天**（周一） |
| 周二活动 | **今天** |
| 两者 | 周一和周二 |

可读的每日摘要会把整晚放在一起。规范源记录保留原始开始和结束时间，并属于开始日；Health.md 不会虚构地拆成两半。需要时段语义时请使用 `healthmd_sleep_sessions`。

Daily Note Injection 与 API Endpoint 使用同一归属方式。如果数据源同步较晚，请重新导出开始日。目前没有把摘要改归起床日的选项。

<div class="related"><a href="/zh-hans/docs/scheduling/"><span>自动化</span>早晨包含“昨天”。</a><a href="/zh-hans/docs/troubleshooting/"><span>帮助</span>排查空数据和延迟。</a></div>
