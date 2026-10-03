---
title: "Health.md 问题排查"
description: "排查空导出、缺失睡眠、手机不可用、计划任务、文件夹、部分结果和超时。"
---

从一台设备、一天、一个类别和一个目标开始。不要在问题报告中提交健康数据、路线、临床文档、令牌、配对码或私密路径。

## 数据为空

确认 Apple Health 或 Health Connect 中存在该值，检查权限，并导出一天的一个类别。区分 `complete_empty`、缺少权限、不支持、跳过、部分和失败。缺失不等于零。

## “今天”没有昨晚睡眠

睡眠属于夜晚开始的日期。周二早晨请导出**昨天**，或同时导出周一和周二。参阅[睡眠日期](/zh-hans/docs/sleep-date-attribution/)。

## 文件与计划任务

检查仓库、文件夹权限、子文件夹、模板和配置文件。iOS 后台与 WorkManager 的时间是目标，并非绝对保证。解锁设备并使用恢复流程。

## CLI 超时

超时不会取消已接受任务：

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

在声明完整前检查状态、缺失日期、覆盖、`next_cursor`、版本和限制。`--allow-partial` 只改变退出策略。

<div class="related"><a href="/zh-hans/docs/cli-jobs/"><span>任务</span>恢复与取消。</a><a href="/zh-hans/docs/release-status/"><span>版本</span>兼容性。</a></div>
