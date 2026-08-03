---
title: "类型化查询手册"
description: "运行 Health.md 的全新或缓存指标、睡眠、训练、锻炼、覆盖范围、周期比较和证据查询，并明确处理分页和缺失状态。"
---

高级 CLI 命令会将常见的健康数据问题转换为固定的类型化查询操作。默认情况下，它们会从 iPhone 获取请求的数据，查询 Mac 上的加密上下文，并返回包含证据和覆盖范围的版本化 JSON。

需要完整的 `healthmd.health_data` 每日数据或来源记录时，请改用[规范提取](/zh-hans/docs/cli-extract/)。

## 检查就绪状态并查找指标

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

指标目录会返回规范 ID、显示名称、类别、单位和可用性要求，但不会声称某项指标已获得 HealthKit 授权。

请从目录复制 ID，不要自行猜测。

## 查询指标序列

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

类别会根据当前目录展开：

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

可组合多个指标和类别标志。全新获取会将展开后的选择发送到 iPhone，但不会更改已保存的导出设置。

响应使用 `healthmd.cli_metric_query` v1 封装，在嵌套的类型化查询响应之外保留数据获取诊断信息。

## 全新、缓存与复用已有覆盖范围

默认使用全新数据：

```bash
healthmd query --metric resting_heart_rate --last 30
```

该命令会向已连接的 iPhone 请求精确范围，提交更新后的加密归属日，再查询这些数据。

缓存模式不会联系 iPhone：

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

仅当已存数据的采集时间和覆盖范围符合要求时，才应使用缓存模式进行离线分析。

`--reuse-covered` 会先检查加密摘要的覆盖范围：

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

只有每个请求的指标和日期都具备完整且兼容的摘要覆盖范围时，Health.md 才会跳过获取。无损请求和新派生的睡眠时段操作不会使用此快捷方式。

## 理解完成状态字段

全新查询响应会区分三个概念：

| 字段 | 回答的问题 |
|---|---|
| `requested_scope_status` | 本次获取中，请求的每项指标、来源、提供方和归属日是否都已完成？ |
| `corpus_status` | 获取的语料库中，其他分支是否报告警告、跳过或失败？ |
| `unrelated_skips` | 哪些已跳过或不受支持的分支不在请求范围内？ |

请求范围可以完整，同时语料库中存在不相关的跳过项。Health.md 会同时保留这两个事实，而不是错误地降低请求结果的状态或隐藏语料库诊断信息。

对于全新获取，完成状态只计算本次刷新开始后被替换的 Blob。过期的缓存值无法补足失败的请求。

## 对结果分页

不使用 `--all-pages` 时，命令只返回一页有界结果。请检查 `next_cursor`：

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

游标非空表示仍有更多结果。在遍历完成前，外层高级状态会保持为 `partial_success`。

自动遍历会跟随不透明游标并检查游标是否重复：

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

响应会将第一个 `healthmd.query_response` 保存在 `query` 下，将后续版本化响应保存在 `pages` 下，并提供一个 `healthmd.cli_query_receipt` v1，其中包含页面、项目、事实和证据数量，以及最终遍历状态。

自动遍历设有总页数和字节数上限。达到上限时，请缩小日期或指标范围，或使用[底层 API](/zh-hans/docs/agent-api/) 手动分页。

## 进度与表格输出

可将不含健康数据的阶段和分页进度以 JSONL 写入 stderr：

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSON 才是完整输出。表格模式是供终端用户选择的有损 TSV 视图：

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

表格页脚会保留覆盖范围、来源、限制、完成状态和不相关跳过项的说明。如果脚本需要精确的类型化值或证据，请勿使用表格输出。

## 睡眠时段

Apple Health 的睡眠阶段会跨越午夜，不同来源之间也可能重叠。睡眠命令会构建稳定的睡眠时段，而不是把每个归属日视为一个数值总计。

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

也可以选择精确日期或全部历史记录：

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

每个睡眠时段可以报告：

- 稳定的时段身份；
- 归属日期和本地时区；
- 精确的本地及 UTC 开始和结束时间戳；
- 夜间睡眠或小睡分类；
- 所选阶段的总时长；
- 已观测和未追踪时长；
- 完整性和排除项；
- 相对于时段固定的时间窗口；
- 相邻日期的生理指标覆盖范围；
- 来源证据。

获取睡眠时段时，会请求无损的规范睡眠阶段区间和完整的规范阶段指标集。Health.md 最多额外读取一个相邻归属日以确定边界，随后从结果中排除无关日期。

计算总睡眠时长时，会对重叠来源的阶段记录去重。只有聚合值的缓存上下文会标记为 `aggregated`，不会声称具备区间观测覆盖范围。固定的 `first:4h` 窗口绝不会把每日聚合值按比例分摊到四小时内。

## 锻炼与睡眠对齐

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

Health.md 会为每项选定锻炼查找 36 小时内最近且符合条件的前一段和后一段睡眠，并报告：

- 稳定的锻炼和睡眠时段 ID；
- 精确的时间间隔；
- 请求的睡眠窗口；
- 生理指标样本数；
- 睡眠阶段和时段覆盖情况；
- 证据和排除项。

此操作是确定性的时间对齐，不会声称锻炼导致某种睡眠结果，也不会声称睡眠导致某种锻炼表现。它最多额外读取两个相邻归属日，并且不会返回无关数据。

## 列出锻炼

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

锻炼列表会保留稳定身份、精确时间戳、类型化详情、证据和缺失状态。结果按开始时间戳和稳定锻炼身份排序。锻炼总数没有固定上限；分页控制只限制每次响应。

## 覆盖范围

如果问题是“我有哪些数据？”，而不是“数值是多少？”，请使用覆盖范围命令。

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

覆盖范围会返回请求范围、可用范围、纳入统计的天数、有值的天数，以及携带状态的缺失区间。状态和原因相同的相邻区间可以压缩，而不会丢失含义。

没有匹配观测值的日期可能为 `complete_empty`；从未同步的日期会使用另一种状态。两者都不会被转换为零。

## 比较精确周期

CLI 不会猜测某项指标应当求和、求平均、取最小值、取最大值、计数还是取最新值。请在每个指标 ID 后指定聚合方式：

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

支持的聚合方式包括：

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

单位或类型不匹配时，操作会失败，而不会在未提示的情况下合并。缺失周期没有聚合值。如果第一个周期的基线为零，响应会提供绝对变化，但不提供百分比变化，并将 `zero_baseline` 列为限制。

变化方向只陈述事实：`increased`、`decreased`、`unchanged` 或 `not_comparable`，绝不表示更好或更差。

## 训练证据包

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

只在需要时请求具体的锻炼详情：

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

选择锻炼详情后，系统会获取该请求所需的无损范围。证据包包含事实值、覆盖范围、来源描述符、证据定位器和限制。

证据包 ID 是根据语义内容计算的确定性 SHA-256 摘要。即使生成元数据发生变化，在其他时间重新生成相同证据包仍会得到相同的语义 ID。

契约 v1 中的证据包类型包括 `daily_wellness`、`training` 和 `doctor_visit`。高级便捷命令目前只提供训练证据包。需要精确请求正文时，请使用底层 API。

## 日期归属与时区

查询日期采用精简上下文中的 `owner_date` 值。每一天还会保留用于确定该日期的精确半开 UTC 区间和采集时的 IANA 日历时区。

睡眠时段会保留本地时间戳和跨午夜日期。系统会读取技术上相邻的日期，以便睡眠时段跨越归属日边界时，不会因 Mac 当前时区而移动数据。

向智能体提出与日期有关的问题时，请指定预期的归属日期并检查返回的时区，不要假定使用计算机的时区。

## 智能体回答不得隐藏缺失状态

安全的摘要应保留：

- 指标 ID 和规范单位；
- 日期范围和时区；
- 全新、缓存或复用已有覆盖范围的模式；
- 请求范围状态和语料库状态；
- 分页遍历是否完成；
- 证据引用或来源摘要；
- 完全为空和缺失区间；
- 警告、限制和不相关跳过项。

请勿通过求平均掩盖失败日期，不要把缺失视为零，也不要把时间对齐描述成因果关系。

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/agents/"><span>架构</span>本地智能体与健康上下文：设置、加密、请求范围、证据和保留策略。</a>
  <a href="/zh-hans/docs/mcp/"><span>MCP</span>本地 MCP 辅助程序：查询、睡眠、对齐、锻炼、覆盖范围、比较和证据的类型化工具。</a>
  <a href="/zh-hans/docs/agent-api/"><span>原始契约</span>环回查询 API：精确请求、单页响应、刷新和作业路由。</a>
  <a href="/zh-hans/docs/reference/evidence-packets/"><span>参考</span>精简查询与证据包：类型化值、游标、操作、覆盖范围和 ID。</a>
</div>
