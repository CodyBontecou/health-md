---
title: "持久 CLI 作业与自动化"
description: "通过机器可读输出、有限等待、七天持久作业、明确的部分状态、恢复和经确认的取消，安全自动化 healthmd。"
---

Health.md 将设备间导出和上下文获取视为持久作业。作业的生命周期独立于启动它的进程：即使终端关闭或网络连接中断，已完成的分区也不会被丢弃。

除非某个命令另有更严格的说明，本页适用于文件导出、严格原始导出、规范提取和全新加密上下文获取。

## 核心原则

超时或断开连接不等于取消。

结果未知时，不要启动重复作业。请保存返回的作业 ID，检查状态，再恢复同一作业。

导出、原始导出和提取作业使用顶层生命周期命令：

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

加密上下文获取作业使用本地智能体生命周期命令：

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## 七天有效期

持久作业的 `expires_at` 固定为创建七天后；作业进度不会延长有效期。两端都会保存不可变请求和足以安全恢复的已提交传输状态。

作业可以持久保存：

- 精确日期或解析后的全部历史标识符；
- 指标、类别、来源和详细程度范围；
- 后端和已配对设备绑定；
- 设置策略；
- 原始配置或提取选择；
- 文件目标位置身份；
- 请求指纹；
- 会话和传输清单；
- 分区摘要链；
- 已提交分区和字节边界；
- 完成或取消确认。

恢复作业时，不能重新解释这些字段。

## 状态不只有运行中和已完成

作业响应可能包含：

| 字段 | 含义 |
|---|---|
| `durable` | 操作是否具有可恢复的作业状态 |
| `state` | 当前持久生命周期状态 |
| `job_id` | 稳定的作业标识符 |
| `session_id` | 绑定的传输会话标识符 |
| `paused` | 作业是否需要同一台 iPhone 重新连接 |
| `processed_days` / `total_days` | 逻辑归属日进度 |
| `committed_partitions` | 接收方已持久确认的分区数 |
| `committed_bytes` | 已安全提交的载荷字节数 |
| `fraction_complete` | 不含健康数据的完成比例 |
| `expires_at` | 固定的作业到期时间戳 |

状态字段包含日期、ID、计数、字节和安全错误，不应包含健康样本。

## 启动作业前明确输出方案

原始导出：

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

规范提取：

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

直连生成文件：

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

请求开始前，请先确定最终输出文件或目标位置。原始作业会绑定输出行为；直连文件作业会把确切的目标根目录写入不可变请求。

## 恢复

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

直连模式必须选择原始请求使用的同一后端、设备、传输方式、端口和 iPhone：

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

断开连接后，尚未提交的字节可能会被丢弃。已提交分区不会重新传输或重新解释。只有所有不可变描述符都匹配时，接收方才会接受先前已提交的分区。

恢复文件作业时不能替换目标位置。如果原始根目录已发生变化，Health.md 会以失败方式安全关闭，而不会写入其他文件夹。

## 取消

请使用创建该作业的生命周期命令：

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

取消分为两个阶段：

1. CLI 记录并发送持久取消请求；
2. iPhone 确认取消，作业才进入终止状态。

如果 iPhone 不可用，作业会保持为 `cancellation_pending`。请重新打开同一台 iPhone，再次执行取消。不能仅根据本地取消意图就报告作业已取消。

进程收到 Ctrl-C 后应退出，不应虚构终止取消状态。确实要取消时，请使用明确的取消命令。

## 输出通道

Health.md 会将命令结果与进度分开：

| 通道 | 内容 |
|---|---|
| stdout | 版本化 JSON 命令结果、错误，或请求的 JSON/JSONL 流 |
| stderr | 纯文本配对说明、不含健康数据的进度、流式输出时的 JSONL 回执，以及用法文本 |
| `--output PATH` | 以原子方式提交且包含健康数据的 JSON 或 JSONL |
| `OUTPUT.receipt.json` | JSONL 文件输出对应的不含健康数据的提取回执 |

`--help` 使用纯文本。命令执行前的参数错误会写入 stderr 并以 2 退出；命令一旦开始执行，运行时错误就使用机器可读 JSON。

自动化解析器切勿合并 stdout 和 stderr。

## 退出状态与数据状态

进程退出状态只是一个信号。声明成功前，必须解析响应。

| 结果 | 默认退出行为 |
|---|---|
| 完整成功 | 零 |
| 请求范围完全为空 | 零 |
| 经过验证的部分严格原始导出或提取 | 非零 |
| 明确使用 `--allow-partial` 的部分结果 | 零，但响应仍为部分结果 |
| 参数错误 | 以 2 退出，stderr 为纯文本 |
| 验证或传输失败 | 非零，并提供结构化运行时错误 |

`--allow-partial` 是接受策略，不是数据修复。所有缺失日期、失败查询、不支持类型和警告仍会保留。

## 分页遍历与作业完成彼此独立

类型化查询响应采用分页。全新数据获取作业可以已经完成，而查询仍有下一页。

不使用 `--all-pages` 时，请检查 `next_cursor`。如果存在下一页，高级 CLI 会报告 `partial_success`，而不会声称已经完整遍历。

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages` 会跟随不透明游标、检查重复项，并限制总页数和字节数。达到上限时，请缩小范围或使用底层 API 手动分页。结果总量没有隐藏上限，但单次调用始终有界。

## 全新、缓存与复用已有覆盖范围

高级查询命令默认从 iPhone 获取全新数据：

```bash
healthmd query --metric resting_heart_rate --last 30
```

仅当过期的上下文仍可接受时，才使用缓存数据：

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

只有在 Health.md 验证请求日期具备完整且感知指标的摘要覆盖范围后，才可使用 `--reuse-covered` 跳过获取：

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

复用快捷方式不适用于无损数据或新派生的睡眠时段操作。其他提供方的数据或较早的过期 Blob 绝不会被视为本次请求全新完成的证明。

## Shell 示例

以下示例将健康数据载荷保存在受保护的文件中，只输出安全状态字段。示例假定已安装 GNU `timeout`；其他自动化主机应设置自己的进程截止时间。

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

可能流式输出健康数据 JSON 或包含敏感路径的命令周围，切勿启用 `set -x`。

## 结果未知后的智能体行为

智能体或调度程序应按以下顺序处理：

1. 读取结构化错误和作业 ID。
2. 在本地运行 `status --job`。
3. 检查作业是已暂停、已终止、已过期，还是正在等待确认。
4. 需要获取新数据或确认时，重新打开同一台 iPhone。
5. 使用相同的后端和设备恢复现有作业。
6. 只有在已明确知道先前结果，或明确接受先前作业过期后，才启动新作业。

即使文件提交本身具备幂等性，盲目重试会产生副作用的操作仍可能重复来源端工作。

## 常见机器可读错误

| 代码 | 含义 | 安全处理方式 |
|---|---|---|
| `timed_out` | 作业完成前，命令已停止等待 | 检查返回的作业并恢复 |
| `job_not_found` | 该 ID 没有对应的本地持久记录 | 重新开始前确认后端和状态目录 |
| `job_expired` | 固定的七天期限已过 | 记录缺口，并在适当时创建新请求 |
| `direct_export_paused` | 直连作业需要已配对的 iPhone 重新连接 | 重新打开 iPhone 并恢复 |
| `direct_cancellation_pending` | 本地取消意图尚未得到 iPhone 确认 | 重新打开 iPhone 并再次执行取消 |
| `invalid_direct_raw_response` | 严格原始响应验证失败 | 不要使用输出 |
| `invalid_direct_file_receipt` | 文件清单或提交回执验证失败 | 不要手动修复或追加文件 |
| `partial_canonical_extraction` | 请求的提取不完整 | 检查回执；只有可以接受时才允许部分结果 |
| `unvalidated_response_too_large` | 当前验证边界无法公开单个结果 | 缩小范围或使用合适的输出模式 |
| `stale_cursor` | 签发分页游标后，加密上下文已发生变化 | 针对当前语料库重新开始该查询 |

## 不记录载荷的进度信息

高级查询阶段和分页遍历可使用 `--progress-json`：

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

进度 JSONL 可以包含阶段、页数、项目数、日期和安全诊断，但不得包含健康数值。请将它与最终结果分开，并仍然采用适当的保留策略。

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/cli/"><span>设置</span>Health.md CLI：安装、选择后端并理解命令输出。</a>
  <a href="/zh-hans/docs/cli-direct/"><span>直连</span>iPhone 直连 CLI：配对、有限后台时间、明确目标位置和可信恢复。</a>
  <a href="/zh-hans/docs/agent-queries/"><span>分页</span>类型化查询手册：全新与缓存模式、分页遍历、覆盖范围和回执。</a>
  <a href="/zh-hans/docs/reference/generated/cli/exit-codes/"><span>生成契约</span>CLI 退出代码：由生产实现生成的状态和错误行为。</a>
</div>
