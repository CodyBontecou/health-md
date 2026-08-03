---
title: "环回查询 API"
description: "通过 HTTP 或底层 healthmd agent 命令调用 Health.md 的版本化本地查询、证据、刷新、就绪状态、指标和持久作业路由。"
---

Health.md Mac 版在 `/v1/agent/` 下提供版本化本地 API，用于加密上下文查询、证据包、按请求范围从 iPhone 获取数据、检查就绪状态和管理持久获取作业。

该 API 仅绑定端口 `17645` 的环回地址，只接受经过验证的 IPv4 或 IPv6 环回对等方。

<div class="callout">
<strong>切勿暴露此端口。</strong>
<p style="margin-top:6px;">此 API 没有持有者令牌、调用方注册、访问配置或授权数据库。能否访问环回地址就是完整的授权边界。Health.md 打开时，任何本地进程都能发出请求。</p>
</div>

## 路由

| 方法 | 路由 | 用途 |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | 列出版本化架构、支持的范围和分页边界 |
| `GET` | `/v1/agent/metrics` | 返回可查询指标的规范 ID、类别、单位和要求 |
| `GET` | `/v1/agent/readiness` | 返回加密上下文和从 iPhone 获取新数据的就绪状态及后续操作 |
| `POST` | `/v1/agent/query` | 运行一页有界的类型化查询 |
| `POST` | `/v1/agent/evidence` | 派生一页有界的事实证据包 |
| `POST` | `/v1/agent/refresh` | 从 iPhone 获取明确范围的数据并写入 Mac 加密上下文 |
| `GET` | `/v1/agent/jobs/{id}` | 查看本地持久获取作业 |
| `POST` | `/v1/agent/jobs/{id}/resume` | 恢复不可变的获取请求 |
| `POST` | `/v1/agent/jobs/{id}/cancel` | 明确请求取消作业 |

原有的 `/v1/agent/profiles` 和 `/v1/agent/activity/query` 路由会返回 `410 removed_endpoint`。

iPhone 直连后端不提供这些 HTTP 路由。独立的 `healthmd` 命令通过直连后端执行规范提取和导出；`healthmd mcp serve` 则直接通过 iPhone 查询协议 v3 提供全新类型化查询、证据、指标目录、就绪状态、可视化和持久导出工具。配对和 MCP 使用同一可执行文件身份；刷新和 Mac 加密上下文仍是此 HTTP API 独有的功能。

## 首选 CLI 适配器

底层 CLI 会原样保留请求正文，并处理环回传输错误：

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

正文较小时，可用 `--json JSON` 代替 `--input`。CLI 不会在未提示的情况下扩大或缩小提供给这些命令的 JSON 范围。

普通工作流请使用 `healthmd query`、`healthmd sleep sessions` 或 `healthmd compare` 等高级命令。它们会验证选择器，并替您构造类型化操作。

## 查询正文

`POST /v1/agent/query` 的顶层只接受 `request` 和可选的 `detail_level`：

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

未知的封装字段会被拒绝。查询请求契约定义指标、来源、日期、操作和分页控制。`detail_level` 可取 `summary` 或 `lossless`。

响应为 `healthmd.query_response` v1，其中包含类型化项目、覆盖范围、证据、来源描述符、限制以及可选的 `next_cursor`。

完整的合成响应见 [`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json)。

## 继续使用游标

要请求下一页，请发送语义完全相同的请求，并将返回的游标放入 `page.cursor`：

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

持续跟随 `next_cursor`，直到该字段不再出现。游标经过身份验证，并与请求和加密语料库版本绑定。Health.md 会拒绝被修改、与请求不匹配或已过期的游标。

分页边界只限制单次请求，不会限制历史记录或结果总量。

## 证据正文

`POST /v1/agent/evidence` 使用相同的封装。操作类型为 `derive_packet`，并指定证据包类型和明确选择的详情。

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

响应仍是分页查询响应，其中包含一个 `healthmd.evidence_packet` v1 片段。事实同时包含类型化值和证据；证据包还会注明仅限事实观察这一限制。

完整的合成响应见 [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json)。

## 刷新正文

刷新只获取明确指定的范围。正文接受日期、指标、来源、详细程度和有限的等待超时：

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Mac 会根据当前目录验证范围，并将其转换为不可变的规范选择。iPhone 只读取所选的常规 HealthKit 类型。按请求提供的设置不会更改 iPhone 中已保存的导出偏好设置。

刷新使用专用的 `encrypted_context` 传输模式：

- 不写入导出文件；
- 不消耗文件导出额度；
- 传输有界且可恢复的分区；
- Mac 会先提交每个确定性的精简归属日，再发送确认；
- 完整请求会随持久作业一并保存。

仅包含提供方的范围无需读取 Apple Health。提供方原生历史记录仍作为提供方原生证据保留，不会转换为合成的 Apple Health 指标。

## 选择所有可用数据

指标和日期选择器可使用 `all_available`：

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

iPhone 会确定所选 Apple Health 记录中最早可用的记录，并涵盖从该日起到今天的每个来源日历日。提供方数据获取会遵循提供方原生历史游标。解析出的标识符会在传输前固定，因此恢复作业时请求范围不会漂移。

日期或结果没有固定上限。分区、分页、按日解密、磁盘空间和有限等待共同构成资源边界。

## 持久获取作业

等待刷新时，即使等待超时，作业仍可能继续运行。响应会包含作业 ID 和不含健康数据的安全进度信息。

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

作业会在创建七天后到期。恢复作业会沿用相同的请求、Mac、iPhone、来源范围和已提交边界。

只有在 iPhone 确认后，取消才成为终止状态。如果 iPhone 不可用，作业可能会停留在等待取消状态。

## 直接调用 HTTP

建议使用 CLI，但本地软件也可以直接调用 HTTP：

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

监听器会限制标头和 JSON 正文大小，要求明确的方法和内容类型，并强制执行接收期限及有限请求行为。

直接 HTTP 客户端必须与 Health.md 位于同一台 Mac。请勿添加 LAN 绑定、代理、隧道或远程 HTTP MCP 封装。

## 类型化值与缺失状态

查询结果会保留类型和单位。值可以是数量、时长、计数、字符串、类别、布尔值、时间戳、日历日期、嵌套数组，或未来新增的未知类型化值。

缺失状态包括完全为空、部分、失败、不支持、已跳过、已取消、未请求、旧版不可用、已编辑和未同步。使用方不得将这些状态强制转换为零。

覆盖范围包含请求范围、可用范围、纳入统计的天数、有值的天数，以及经过压缩但仍携带状态的缺失区间。

## 错误处理

错误使用 `healthmd.query_error` v1，包含稳定的代码、消息、是否可重试以及类型化详情。不同错误分别涵盖：

- 无效的分页控制；
- 格式错误或被篡改的游标；
- 游标与查询不匹配；
- 语料库版本过期；
- 日期范围无效；
- 指标或来源验证失败；
- 单位或聚合不匹配；
- 操作不受支持；
- 证据范围违规；
- iPhone 或加密存储尚未就绪；
- 持久作业状态错误。

刷新结果未知时，切勿盲目重试。请先检查作业状态。

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/agents/"><span>概览</span>本地智能体与健康上下文：设置、加密存储、范围和结果报告规则。</a>
  <a href="/zh-hans/docs/agent-queries/"><span>高级</span>类型化查询手册：常见指标、睡眠、锻炼和证据问题的已验证命令。</a>
  <a href="/zh-hans/docs/mcp/"><span>工具</span>本地 MCP 服务器：stdio 配置、类型化工具、分页和沙盒限制。</a>
  <a href="/zh-hans/docs/reference/api-and-cli/"><span>参考</span>API 与 CLI 契约：导出、提取、查询、直连后端和操作限制。</a>
  <a href="/zh-hans/docs/reference/evidence-packets/"><span>数据契约</span>精简查询与证据包：类型、游标、操作和确定性证据包 ID。</a>
</div>
