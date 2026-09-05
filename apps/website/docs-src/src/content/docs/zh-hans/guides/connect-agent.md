---
title: "10 分钟连接智能体"
description: "将已发布的 Health.md Mac 版 MCP 辅助程序连接到 Codex 或 Claude，从 iPhone 获取一个明确范围，运行受限查询，并安全地验证完整性。"
---

<div class="availability available">
<strong>现已提供 · Health.md Mac 版</strong>
<p>本路径使用已发布 Mac 应用内置的已签名 <code>healthmd-mcp</code> 辅助程序。它不使用便携 CLI 预览、Direct CLI 访问、配对二维码或端口 17647。</p>
</div>

你将连接本地 MCP 主机，在不读取健康数值的情况下验证就绪状态，从 iPhone 显式刷新一个小范围，然后查询该加密 Mac 上下文。当两个应用都已安装并处于同一本地网络时，大约需要十分钟。

## 1. 安装并打开 Health.md

在 Mac 和 iPhone 上都[从 App Store 下载 Health.md](https://apps.apple.com/us/app/health-md/id6757763969)。打开两个应用。

HealthKit 保留在 iPhone 上。Mac 应用托管已签名的 MCP 辅助程序和一个加密的、可丢弃的查询上下文；它不会直接读取 HealthKit。

## 2. 连接 iPhone 和 Mac

1. 在 Mac 上保持 Health.md 打开。
2. 在 iPhone 上打开 **Health.md → 同步**，并启用 Mac 连接。
3. 让两台设备保持在同一个可访问的本地网络中，并在开始新的处理期间让 Health.md 在 iPhone 上保持前台。
4. 确认 Mac 应用显示了预期的 iPhone 连接。如果没有，请重新打开两个应用，并查看 [Mac 同步就绪状态](/zh-hans/docs/sync/)。

这是已发布的 Mac 连接。不要运行 `healthmd direct pair`；该命令属于单独的便携预览。

## 3. 复制已签名辅助程序的路径

打开 **Health.md Mac 版 → CLI**，复制显示的 MCP 辅助程序路径。正常的 `/Applications` 安装使用：

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

如果应用安装在其他位置，请使用显示的路径。请直接配置辅助程序——不要把它包装在 shell 中，也不要作为交互式命令启动。

## 4. 配置 Codex 或 Claude

### Codex

将以下内容添加到 `~/.codex/config.toml`，并在需要时替换辅助程序路径：

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

保存文件后重启 Codex。

### Claude Desktop 或 Claude Code

将以下本地 stdio 条目添加到 Claude Desktop 的 MCP 配置或可信的 Claude Code `.mcp.json` 中：

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

重启 Claude Desktop，或者信任 Claude Code 工作区并批准该服务器。请让刷新、导出、恢复和取消操作保持启用批准提示。

## 5. 检查就绪状态

调用 `healthmd_doctor`。它只读取不含健康数值的就绪状态。

就绪的结果包含以下字段：

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

完整结果还包含检查项和后续操作。在继续之前解决所有阻塞的检查项。已连接的辅助程序**并不**证明加密上下文是最新的。

接着调用 `healthmd_metrics`，确认你打算请求的规范指标 ID 和单位。本演练仅以 `steps` 为例。

## 6. 显式刷新一个小范围

先确定你真正需要的日期，再以精确的闭区间调用 `healthmd_refresh`。示例请求一天的汇总数据：

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

审查参数、批准获取，并保持两个应用打开。刷新不会写入导出文件，也不会更改 iPhone 上保存的导出设置。保留返回的 `job_id`，直到作业到达终态。

## 7. 运行第一个受限查询

刷新完成后，使用相同的日期、指标、来源选择和详细程度调用 `healthmd_metric_chart`：

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true` 只在辅助程序的聚合页数和字节上限之内遍历不透明游标。对于睡眠，请调用 `healthmd_sleep_sessions`，而不是用规范提取来代替。

## 8. 回答之前验证完整性

不要把工具成功当作完整健康覆盖的证明。请检查以下所有各项：

- 刷新已针对相同的精确日期、指标、来源和详细程度到达成功的终态；
- 响应的架构和版本是可识别的；
- 请求的范围和时区与问题相符；
- 每个陈述的值都保留其规范指标 ID 和单位；
- 覆盖状态、考虑的天数、有值的天数以及每个缺失区间都有报告；
- `complete_empty`、`partial`、`failed`、`unsupported`、`skipped` 和 `cancelled` 不会被转换为零；
- 遍历已完成，或者披露了任何剩余的游标或聚合上限；
- 证据/来源描述符和限制仍附加在答案上；
- 事实性方向不会被变成诊断、治疗建议、因果结论或“更好/更差”的表述。

### 在不丢弃有用数据的前提下读取部分结果

类型化查询可能只在所请求范围的一部分完成时，仍返回有效的 `healthmd.query_response`。生成的[部分查询响应夹具](/docs/reference/generated/automation/agent-query-response-partial.json)保留一个可用的步数条目，并单独报告失败的那一天：

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

上面 `items` 和 `limitations` 中的字符串是说明性缩写；请使用可下载的生成夹具获取确切的字段和证据。将保留的条目、失败区间、覆盖计数和限制一并保留。

不要把 `status: "partial_success"` 添加到 `healthmd.query_response`。该状态属于更高层级的 CLI 和导出封装，用于获取、遍历或文件生成不完整的情况。超时则又是另一回事：它是一个结果未知的持久作业，必须通过作业 ID 进行检查。

结构化失败使用 `healthmd.query_error` v1 而不是部分响应。请查看 [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json) 了解生成的生产形态，其中包含稳定的代码、消息、可重试性和类型化详情。

## 9. 从超时中安全恢复

超时、主机关闭或被取消的 MCP 等待操作不会取消已被接受的刷新。

1. 保留返回的 `job_id`。
2. 使用该 ID 调用 `healthmd_job_status`。
3. 如果该不可变作业可以恢复，请审查并批准带相同 ID 和有限等待超时的 `healthmd_job_resume`。
4. 只有在状态证明没有已接受的作业仍能完成之后，才开始新的刷新。
5. 仅在确实要终止作业时才使用 `healthmd_job_cancel`；取消只有在 iPhone 确认后才成为终态。

在结果未知时绝不要盲目重试。持久刷新作业会保留已接受的范围和已提交边界。

## 你已连接

当 doctor 就绪、显式刷新到达终态、受限查询完成完整遍历，并且你已检查覆盖、证据、单位和限制时，第一个只读工作流就完成了。

生成文件导出是单独的、需要批准的工作流。已发布的 Mac 工具会写入已在 Health.md Mac 版中选择的文件夹；它不接受任意目标参数。

<div class="related">
  <a href="/zh-hans/docs/mcp/"><span>工具目录</span>查看全部已发布的 Mac 工具、精确架构、MCP Apps、分页和安全边界。</a>
  <a href="/zh-hans/docs/configuration/"><span>其他客户端</span>在已发布的 Mac 集成与明确标注的便携预览之间做出选择。</a>
  <a href="/zh-hans/docs/agent-queries/"><span>下一步问题</span>运行指标、睡眠、锻炼、比较、覆盖和证据的类型化工作流。</a>
  <a href="/zh-hans/docs/agents/"><span>信任模型</span>理解加密上下文、请求范围、保留、证据和报告规则。</a>
</div>
