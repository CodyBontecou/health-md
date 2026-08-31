---
title: "规范健康数据提取"
description: "使用 healthmd extract 获取所选 Apple Health 指标，并输出规范 schema-v8 文档、来源记录、JSON Pointer 投影或带明确回执的 JSONL。"
---

`healthmd extract` 是供脚本和智能体使用的来源数据命令。它会要求 iPhone 只获取所选指标和详细程度，验证持久传输，移除传输封装，再输出规范 `healthmd.health_data` v8 文档或明确标记的投影。

规范提取是一项 iPhone 功能，由 Mac 应用后端和 iOS v1 直连协议提供支持。Android 直连来源则改为通过[原始导出](/zh-hans/docs/cli-direct/)返回提供商原生的 Health Connect 快照。

需要 Health.md 原始数据时，请使用提取。需要睡眠时段、比较、锻炼对齐、覆盖范围或证据包时，请使用[类型化查询](/zh-hans/docs/agent-queries/)。

## 基本形式

一次提取需要：

1. 至少一个指标、类别、对象或 `--all-metrics` 选择器；
2. 一个日期选择器；
3. 可选的详细程度、对象、字段、格式、输出、超时和部分结果选项。

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

当前规范提取来源为 `apple_health`。提供方原生辅助记录会留在各自契约中，不会转换为合成的 Apple Health 值。

## 从小范围请求开始

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

在 iPhone 开始处理前，系统会根据当前目录验证指标和类别名称。重复使用选择器即可组合多个选择。

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## 先选择，再读取 HealthKit

提取不会先获取已保存的全指标导出，再在事后裁剪。CLI 会把选择器解析成不可变的 `CanonicalHealthDataSelection` 并发送到 iPhone。Health.md 只检查并读取所选指标对应的常规 HealthKit 类型。

这种区别对隐私、性能和完整性都很重要：

- 不会获取未选择的指标；
- 不会更改 iPhone 中已保存的指标偏好设置；
- 摘要请求不会暗中创建来源归档；
- 无损请求只获取当前选择所需的来源类型；
- 选择范围会成为持久请求指纹的一部分。

对象和 JSON Pointer 选择器会在采集后缩小输出范围；指标、类别、来源和详细程度选择器则会缩小 iPhone 实际获取的数据范围。

## 摘要与无损详情

默认使用摘要：

```bash
healthmd extract --category Activity --last 7 --detail summary
```

摘要输出可以包含类型化每日摘要、查询诊断，以及 `raw_capture_status: not_requested`。该状态如实表明：此命令没有获取规范来源记录。

如果需要来源对象、UUID、精确时间戳、溯源信息或归档诊断，请请求无损详情：

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

面向归档的对象（例如 `records`）会隐含无损详情，即使省略 `--detail` 也是如此。

## 对象选择器

使用 `--object` 保留每个所选日期中的已知部分。当前名称包括：

| 对象 | 典型内容 |
|---|---|
| `sleep` | 每日睡眠摘要字段 |
| `activity` | 步数、能量、距离、锻炼及相关活动摘要 |
| `heart` | 心率、静息心率、HRV 及相关摘要 |
| `vitals` | 血压、血糖、体温、血氧及其他生命体征摘要 |
| `body` | 体重、身体成分、身高和身体测量 |
| `nutrition` | 营养素和水分摄入摘要 |
| `mindfulness` | 正念时段和心理健康摘要 |
| `mobility` | 步行、步态和行动能力字段 |
| `hearing` | 音频暴露和听力字段 |
| `reproductive-health` | 生殖、孕期和周期字段 |
| `cycling` | 骑行摘要 |
| `vitamins` / `minerals` | 特定营养素摘要 |
| `symptoms` | 症状数据 |
| `medications` | 可用且已获授权的药物数据 |
| `workouts` | 规范锻炼摘要对象 |
| `archive` | 规范 HealthKit 归档封装 |
| `records` | 规范来源记录；隐含无损详情 |
| `external-records` | 公开每日数据中已有的外部记录 |
| `query-results` | 每项查询的采集结果 |
| `warnings` | 完整性警告 |

示例：

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## JSON Pointer 投影

重复使用 `--field` 和 RFC 6901 JSON Pointer，可输出精确的值或状态条目：

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Pointer 结果是投影，不是完整的每日文档。它们会引用来源架构和日期，但不会携带可能让子树看起来像完整导出的 `schema: healthmd.health_data`。

如果所选路径不存在，系统会报告完全为空，或沿用该日期的不完整状态。Health.md 不会把缺失转换为零。

## JSON 输出

默认 JSON 输出包含以下数据集合之一：

- `health_data`：完整的规范每日文档；或者
- `projections`：对象或 Pointer 结果。

输出还包含 `healthmd.extract_receipt`，用于记录：

- 解析后的选择和日期范围；
- 来源和详细程度；
- 每日结果；
- 保留项目数和采集数；
- 缺失日期；
- 部分或失败诊断；
- 输出完成状态。

回执属于协议元数据，不能替代来源架构。

## JSONL 输出

使用 JSONL 进行流式处理：

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

每一行都是一个数据项目。回执不会混入健康数据流：

- 使用 `--output` 时，回执写入 `OUTPUT.receipt.json`；
- 不使用 `--output` 时，回执写入 stderr。

因此，管道行为可预测：

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

不要把 stderr 传给 JSONL 解析器，因为 stderr 会携带回执和不含健康数据的进度信息。

## 完整、为空和部分结果

Health.md 会区分以下状态：

| 状态 | 含义 |
|---|---|
| `success` | 请求的每个分支均已完成，包括完全为空的分支 |
| `complete_empty` | 已表示请求范围，但其中没有观测值 |
| `partial_success` | 保留了部分请求数据，但至少有一个请求分支不完整 |
| `failed` | 请求分支失败 |
| `unsupported` | 平台或 HealthKit 不支持请求分支 |
| `skipped` | Health.md 有意未查询该分支 |
| `cancelled` | iPhone 已确认取消 |
| `missing` | 请求的日期或分支未得到表示 |

默认情况下，部分提取不会输出已保留的数据。只有当使用方能够接受并保留不完整范围时，才应添加 `--allow-partial`：

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

该标志只改变输出和退出行为，不会删除诊断信息，也不会把部分数据变成完整数据。

## Mac 应用与直连后端

该命令可通过任一后端运行：

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

两条路径都使用同一公开每日架构和严格验证。传输、配对、存储和作业记录则有所不同。两条路径都需要 iPhone 来源；Android 直连后端不实现规范提取。

## 大量历史数据

`--all` 没有固定日期上限：

```bash
healthmd extract --metric steps --all --output all-steps.json
```

iPhone 会确定所选记录中最早可用的一条，固定从该日起到今天的每个来源日历日，并传输有界分区。CLI 会在磁盘上组装和验证，而不是构建一个无界的内存响应。

语料库较大时，请使用 JSONL 或缩小选择范围。可用磁盘空间和某个异常密集的日期仍是实际限制。

## 隐私检查清单

- 任何包含健康数据的结果都应优先使用 `--output`。
- 保护输出和回执文件时，应采用与 Apple Health 来源相同的谨慎程度。
- 不要在健康数据命令周围启用 shell 跟踪。
- 不要让载荷进入 CI 日志或智能体记录。
- 排查问题时，只检查回执、计数、状态、架构和缺失状态字段。
- 目标使用方安全提交数据后，删除临时导出文件。

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/cli/"><span>CLI</span>Health.md CLI：设置、后端选择、命令索引和输出规则。</a>
  <a href="/zh-hans/docs/agent-queries/"><span>派生视图</span>类型化查询手册：指标序列、睡眠、训练、锻炼、比较和证据。</a>
  <a href="/zh-hans/docs/reference/daily-records/"><span>架构</span>每日记录：完整的 schema-v8 每日文档契约。</a>
  <a href="/zh-hans/docs/reference/canonical-healthkit-records/"><span>来源归档</span>规范 Apple Health 记录：身份、溯源信息、关系和载荷。</a>
  <a href="/zh-hans/docs/reference/api-and-cli/"><span>协议</span>API 与 CLI 参考：提取请求、回执、严格验证和退出行为。</a>
</div>
