---
title: "Apple Health 导出缺少数据？Health.md 问题排查"
description: "排查 Apple Health 或 Health Connect 导出为空、睡眠缺失、CSV 详细程度、文件写入失败和计划延迟。先核对一个完整日期。"
---

Apple Health 或 Health Connect 导出缺少数据时，先区分**读取问题**和**文件写入问题**。数据缺失不代表测量值为零。

## 从可以核对的一天开始

1. 在 Apple Health 或 Health Connect 中确认一条已记录的数值及其日期。先等待手表或来源应用完成同步。
2. 在 Health.md 中检查当前配置档、指标、日期范围、格式和目标。从一个已结束日期的一项受支持指标开始。
3. 解锁手机并打开 Health.md，在可用时查看预览。随后导出，核对实际结果和目标。预览成功并不能证明文件已保存。

参见 [iPhone 首次导出](/zh-hans/docs/iphone-first-export/)或 [Android 设置](/zh-hans/docs/android/)。

## 来源中有数据，但导出为空

在 iPhone 上，检查 Apple Health 中允许 Health.md 读取的类别。**HealthKit 不会告知应用读取权限是否被拒绝**，因此空结果无法区分访问受限和没有匹配记录。权限请求成功也不能证明所有读取类别均已获准。参见 [Apple 授权文档](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)。

在 Android 上，确认来源应用确实将记录写入 Health Connect，且 Health.md 可以读取该受支持类型。只在另一个应用内可见的数据不一定可以导出。参见 [Google 同步与权限检查清单](https://support.google.com/android/answer/13770384)。

同步或更改权限后，再次核对指标和日期。不要用零替代缺失值。

结构化结果中的 `complete_empty` 应与不支持、部分完成、已跳过或失败的输出区分。它不能证明测量值为零，也不能表明读取权限是否被拒绝。

## “今天”中没有昨晚的睡眠

**夜间开始日（默认）：** Health.md 在 Apple 和 Android 上使用本地时间**正午到次日正午**的睡眠日记窗口。周二早上请导出**昨天（周一）**，即使睡眠是在周二午夜之后开始。若要同时包含睡眠和活动，可导出周一和周二。来源同步较晚时，重新导出对应日记日期。参见[日期示例](/zh-hans/docs/sleep-date-attribution/#sleep-date-examples)。 **早晨结束日：** 请导出醒来的日期，周一晚上的睡眠应导出周二。两种方式都使用导出时区。

## 预览有数据，但文件夹为空

在 iPhone 上，检查当前配置档的目标是本地文件夹、Connected Mac 还是 API Endpoint。对于文件，检查文件夹、子文件夹、文件名及已写入、已跳过或失败的结果。跳过文件可能符合所选写入行为。重新选择不可用的文件夹，确认文件提供方可用后再试。参见[文件夹与保管库](/zh-hans/docs/folder-vault/)和[导出配置档](/zh-hans/docs/export-profiles/)。

## CSV 只有汇总，没有预期的测量记录

在 iPhone 上，Summary 与 Detailed Time-Series 的详细程度不同。扩大日期范围前，检查 Data Detail 和指标。元数据不是健康测量值。保留单位，并区分每日汇总与来源记录。Lossless Health Records 有单独的采集状态；仅有摘要不能证明来源记录完整。参见[格式与覆盖范围参考](/zh-hans/docs/reference/export-formats/)。

## 计划导出没有到达

iOS 后台任务和 Android WorkManager 使用目标时间，并不保证交付时间。解锁设备并打开 Health.md，在再次运行前检查历史记录和待恢复任务。通知不能证明写入成功。参见 [iPhone 计划与恢复](/zh-hans/docs/scheduling/)或 [Android 自动化](/zh-hans/docs/android/)。

## CLI 超时

超时不会取消已接受任务：

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

在声明完整前检查状态、缺失日期、覆盖、`next_cursor`、版本和限制。`--allow-partial` 只改变退出策略。

## 不分享健康记录也能请求帮助

说明应用与系统版本、平台、格式，以及问题是数据为空、输出被跳过还是写入失败。分享截图或日志前遮盖私人信息。不要公开健康数值、移动路线、临床文档、令牌、配对码或私人路径。

<div class="related"><a href="/zh-hans/docs/cli-jobs/"><span>任务</span>恢复与取消。</a><a href="/zh-hans/docs/release-status/"><span>版本</span>兼容性。</a></div>
