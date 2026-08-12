---
title: "Health.md MCP 服务器与 App"
description: "使用 Codex 或 Claude 运行限定范围的 Apple Health 分析、呈现原生图表，并通过本地沙盒化 MCP App 启动持久 Health.md 导出。"
---

Health.md Mac 版内置经过签名的 `healthmd-mcp` stdio 辅助程序。Codex、Claude 和其他 MCP 主机可通过它查询事实性 Apple Health 数据、呈现可视化内容、刷新加密本地上下文，并通过已打开的 Mac 应用执行经过批准的持久导出。

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>现已提供 · Health.md Mac 版</strong>
<p>内置服务器提供 21 个固定工具。它本身不会读取 HealthKit、导出文件夹、安全作用域书签或任意文件。</p>
</div>

<div class="availability preview">
<strong>预览版 · 可移植直连 MCP</strong>
<p>面向 macOS、Linux 和 Windows 的独立 19 工具 <code>healthmd mcp serve</code> 拓扑已经实现，但尚未公开打包。其不使用云服务的 <code>serve-read-only</code> 入口在本地配对后只提供 13 个就绪状态和查询工具。本页仅适用于可移植版本的命令均标记为预览版。</p>
</div>

## 要求

- 已安装并打开 Health.md Mac 版。
- 更新工具或导出启动新的 HealthKit 工作时，已连接 iPhone 上的 Health.md 保持打开。
- 支持 stdio 的本地 MCP 主机。
- **Health.md Mac 版 → CLI** 中显示的已签名辅助程序路径。

辅助程序的常规路径为 `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`。支持的 MCP 核心协议版本为 `2024-11-05`、`2025-03-26`、`2025-06-18` 和 `2025-11-25`。不要把 `healthmd-mcp` 当作普通交互式命令启动；stdin 和进程生命周期由 MCP 主机管理。

## Codex 设置

将内置辅助程序添加到 `~/.codex/config.toml`：

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

重启 Codex，调用 `healthmd_doctor`，使用 `healthmd_metrics` 确定 ID，通过更新工具明确获取一个小而精确的范围，然后使用 `healthmd_metric_chart` 查询该范围。不支持交互式 MCP Apps 的主机仍会收到精确 JSON 和标准 PNG 图表。

## Claude 设置

在 Claude Desktop 的 MCP 配置或受信任的 Claude Code `.mcp.json` 中使用以下本地 stdio 条目：

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

编辑配置后，请重启 Claude Desktop。Claude 项目配置需要工作区信任和明确的服务器批准。

宣告支持稳定 MCP Apps 扩展的 Claude Desktop 版本会在界面中直接呈现 Health.md 交互式视图。Claude Code 和其他以文本为主的客户端则会保留 JSON 和图像后备内容。

## 可移植直连 MCP 预览版

独立版本发布后，`healthmd setup codex` 会与前台运行的 iPhone 配对，并安全创建使用同一二进制文件的 `healthmd mcp serve` 条目。该拓扑通过端口 `17647` 使用经过身份验证和加密的手动 IP 或 Tailscale 传输、原生凭据存储，以及按请求明确发起的 iPhone 读取。Linux 还需要一个已解锁的 Secret Service 提供方；Windows 使用 Credential Manager。

在 `healthmd-cli/v<version>` 版本发布前，不要依赖尚未公开的软件包或安装程序 URL。分阶段配对和传输契约见 [iPhone 直连 CLI](/zh-hans/docs/cli-direct/)。

## 原生 MCP App 可视化

Health.md 实现稳定的 `io.modelcontextprotocol/ui` 协商，并使用 `text/html;profile=mcp-app`。

主机宣告支持该 MIME 类型后，服务器会提供：

- `ui://healthmd/query-visualization-v1`；
- 标准 `resources/list` 和 `resources/read` 方法；
- 分析工具和导出回执工具上的 `_meta.ui.resourceUri`；
- 经过验证的 `structuredContent`，以及内容完全一致的 JSON 文本。

该视图是自包含的 HTML5 资源，不使用网络、远程脚本、远程字体、存储或嵌套框架。其 CSP 中的连接、资源、框架和基础域名列表均为空。它遵循标准的初始化、工具结果、主题、大小调整、取消和销毁生命周期。

它可以呈现：

- 带单位和明确缺失数据断点的指标折线图；
- 使用调用方指定聚合方式的周期比较；
- 睡眠时段和阶段时长摘要；
- 锻炼，以及锻炼与睡眠的事实时间关系；
- 覆盖范围、缺失区间、证据和限制；
- 全部页面的遍历回执；
- 持久导出进度、目标位置和作业回执。

即使主机不支持 MCP Apps，这些工具仍可使用。`healthmd_metric_chart` 会为支持图像的主机添加 `image/png` 内容，同时以文本形式保留完整 JSON。

## 可用工具

内置 Mac 服务器提供 21 个固定工具：13 个就绪状态/查询工具、四个生成文件作业工具和四个加密上下文更新作业工具。包含 19 个工具的可移植预览版保留 13 个就绪状态/查询工具和四个导出工具，用两个直连配对工具替换 Mac 更新作业，并直接在前台 iPhone 上运行类型化查询。

### 就绪状态与发现

| 工具 | 用途 |
|---|---|
| `healthmd_status` | 检查 Mac 应用、上下文、iPhone 和导出就绪状态 |
| `healthmd_doctor` | 诊断内置辅助程序和 Mac 环回拓扑 |
| `healthmd_capabilities` | 列出直连查询、证据、导出、架构和分页能力 |
| `healthmd_metrics` | 列出规范指标 ID、类别、单位和要求 |

### 分析与可视化

| 工具 | 用途 |
|---|---|
| `healthmd_metric_chart` | 查询指标序列并呈现带覆盖范围和单位的原生图表 |
| `healthmd_sleep_sessions` | 列出并可视化稳定的睡眠时段和生理指标覆盖范围 |
| `healthmd_training_alignment` | 显示锻炼与前后睡眠的事实时间关系 |
| `healthmd_workouts` | 列出并可视化锻炼 |
| `healthmd_coverage` | 检查指标和日期的覆盖范围及缺失状态 |
| `healthmd_compare_periods` | 使用明确的聚合语义比较精确周期 |
| `healthmd_training_evidence` | 创建仅陈述事实的训练证据包 |
| `healthmd_query` | 发送精确的 `healthmd.query_request`，并可选择遍历分页 |
| `healthmd_evidence_packet` | 发送精确的证据请求，并可选择遍历分页 |

### 生成文件导出

| 工具 | 用途 |
|---|---|
| `healthmd_export_files` | 通过 Mac 应用执行持久导出，写入应用中选择的文件夹 |
| `healthmd_export_job_status` | 检查导出进度和目标位置回执 |
| `healthmd_export_job_resume` | 恢复完全相同且不可变的持久导出作业 |
| `healthmd_export_job_cancel` | 明确取消导出作业 |

导出、恢复和取消工具被标记为可能产生破坏性影响的写入。当前 Claude 主机要求用户明确交互，因为所配置的导出模式可能更新或覆盖生成文件。上方 Codex 配置也会对这些工具发出批准提示，作为额外保护。

### 加密上下文获取作业 · 仅限内置 Mac 版本

| 工具 | 用途 |
|---|---|
| `healthmd_refresh` | 从 iPhone 获取经过批准的范围，并写入可丢弃的 Mac 加密上下文 |
| `healthmd_job_status` | 在不读取健康数值的情况下检查刷新进度 |
| `healthmd_job_resume` | 恢复完全相同且已接受的刷新作业 |
| `healthmd_job_cancel` | 明确取消已接受的刷新作业 |

### 查看完整查询结构

MCP `tools/list` 包含日期、指标、来源、分页、周期范围、聚合方式和高级 `healthmd.query_request` 的完整嵌套 JSON Schema。类型化工具也包含具体示例。智能体应直接调用与任务匹配的类型化工具，而不是查看通用 shell 帮助。尤其是睡眠问题应使用 `healthmd_sleep_sessions`；`healthmd extract` 生成的是另一种规范来源数据投影。

可移植预览版无需打开网络监听器或联系 iPhone，即可在本地查看相同架构。对于已发布的 Mac 辅助程序，请使用 MCP tools/list。

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

最小睡眠调用采用以下结构（请为实际请求确定包含首尾两天的日期）：

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

规范睡眠指标和无损时段详情会由 `healthmd_sleep_sessions` 自动提供。

## 分析数据并绘制图表

先调用 `healthmd_doctor`，并使用 `healthmd_metrics` 确定指标 ID。在已发布的 Mac 拓扑中，类型化查询工具读取加密的 Mac 上下文；它们不会隐式联系 iPhone。若需要当前数据，请使用明确的日期、指标和来源调用更新工具，等待持久作业完成，再绘制相同范围：

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

将该对象传给 `healthmd_metric_chart`。交互式视图使用单位安全的小多图；缺失或部分数据点会让折线中断，而不会变成零。

已发布的 Mac 类型化工具评估加密的本地上下文，并返回包含覆盖范围、缺失状态、证据和限制的有界页面。只有明确更新才会联系已连接且在前台运行的 iPhone，并替换请求的上下文范围。可移植预览版则直接在已配对且在前台运行的 iPhone 上评估每个类型化请求。

## 执行生成文件导出

先在 Health.md Mac 版中选择并保留一个可写目标文件夹。主机显示完整参数并获得用户批准后，调用 `healthmd_export_files`：

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

要获取完整历史记录，请使用 `date_selection: "all_available"`，并省略 `date_range`。可选的 `metric_ids`、`categories` 或 `all_metrics` 会缩小 iPhone 获取范围，但不会更改已保存的设置。只有提供其中一种选择时，`detail_level` 才适用。`all_metrics` 不能与明确的指标或类别列表组合。

请检查：

- `status` 和持久 `state`；
- `job_id`；
- 已处理天数、总天数和进度；
- 写入的文件或每日笔记；
- 经过验证的桌面目标位置；
- 已提交的分区和字节数；
- 暂停或失败原因，以及到期时间。

等待超时或 MCP 连接关闭都不会取消持久作业。结果未知时，请先检查 `healthmd_export_job_status`，再决定是否恢复。只有明确取消才会终止作业。

原始和规范来源传输可能包含数 GB 的路线、临床文本、附件和来源记录。Health.md 有意不把这些正文放入 MCP 对话。需要与来源结构一致的输出时，请使用经过验证的流式 CLI：

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

MCP 分析始终是派生的事实视图；生成文件导出仍通过生产导出器使用公开 `healthmd.health_data` 契约。

## 分页与完整性

查询和证据工具会在支持时提供 `all_pages: true`。辅助程序会跟随不透明游标，检测循环并限制总字节数和页数，同时在 `healthmd.mcp_query_pages` v1 下保留每个版本化响应。如果自动遍历达到上限，成功的部分结果封装会将 `receipt.traversal_complete` 设为 `false`，并返回精确的 `receipt.next_cursor`，以便无损继续。iPhone 会在前台无操作时保留分页精简快照十分钟，并在遍历结束或应用进入后台时将其清除。单次请求设有 366,000 天和 64 MiB 编码精简上下文保护；`query_scope_too_large` 表示应把日期或指标 ID 拆分到多次调用中，而不是逻辑历史记录不可用。页面会对缺失区间和来源描述符列表设置边界，并提供明确的计数、截断字段和限制。

传输成功不代表数据完整。务必检查：

- 请求范围状态和语料库状态；
- 覆盖范围和缺失区间；
- 限制和证据；
- `next_cursor` 或遍历回执；
- 不相关跳过项；
- 来源架构和版本。

MCP App 会显示这些字段，而不是将其隐藏。自动遍历达到安全上限时，请缩小范围或手动继续。

## 安全与隐私边界

辅助程序不提供提示、根目录、采样、shell、SQL、任意文件读取、任意 URL 获取、HealthKit 写入、环回 HTTP 服务或远程 MCP 端点。它唯一的 MCP 资源是内置 App 文档。生成文件写入是固定且受批准控制的操作。已发布的 Mac 辅助程序使用 Health.md Mac 版中选择的文件夹；可移植预览版要求提供明确、已存在的目标位置，并在传输前完成验证和持久绑定。

直连信任信息存储在钥匙串、Secret Service 或 Windows Credential Manager 中。配对使用现有的身份验证加密协议；iPhone 必须位于前台，并明确连接到计算机的 LAN 或 Tailscale 地址。查询页面受协商的字节数和项目数限制，自动遍历全部页面还设有额外的总字节数和页数上限。无界原始正文只通过经过验证的流式 CLI 路径处理。

Health.md 报告带单位、溯源信息、覆盖范围和缺失状态的事实观测值。它不会诊断、建议治疗、推断因果关系，也不会把变化方向称为更好或更差。

## 故障排除

| 现象 | 处理方法 |
|---|---|
| 主机无法启动辅助程序 | 使用已安装的 `healthmd` 或 `.exe` 绝对路径，并传入参数 `mcp serve` |
| 在终端中运行时辅助程序一直等待 | 这是预期行为；MCP 主机必须通过 stdin 发送 JSON-RPC |
| `healthmd_not_paired` | 运行 `healthmd direct pair`，并在 iPhone 上完成配对 |
| `healthmd_unavailable` | 解锁 iPhone 并将 Health.md 置于前台，启用 Direct CLI 访问，再连接到计算机 |
| `query_scope_too_large` | 将日期或指标 ID 拆分到多次调用中；仍可通过多个请求访问完整逻辑语料库 |
| 没有交互式图表 | 更新主机；服务器仍会返回精确 JSON 和 PNG 指标图表后备内容 |
| 导出目标位置不可用 | Mac：在 Health.md 中重新选择已保存的文件夹。可移植预览版：创建并传入已存在、使用绝对路径且不经过符号链接的桌面目录。 |
| 等待导出时超时 | 恢复前先按 ID 检查持久导出作业 |
| 结果包含 `next_cursor` | 设置 `all_pages: true`，或手动继续游标 |

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/agents/"><span>架构</span>本地智能体、加密上下文、请求范围和证据。</a>
  <a href="/zh-hans/docs/agent-queries/"><span>分析</span>指标、睡眠、锻炼、比较和覆盖范围的类型化查询手册。</a>
  <a href="/zh-hans/docs/cli-extract/"><span>来源数据</span>对大型来源结构结果执行经过验证的规范提取。</a>
  <a href="/zh-hans/docs/reference/evidence-packets/"><span>契约</span>类型化值、缺失状态、证据和证据包身份。</a>
</div>
