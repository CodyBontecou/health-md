---
title: 配置智能体
description: 选择 Health.md MCP 或 CLI 接口，配置 Codex、Claude 或其他本地客户端，并连接已配对的 iPhone，无需通过云服务传输 HealthKit 数据。
---

已发布的 Mac 应用包含两个经过签名的本地辅助程序：用于类型化智能体工具的 `healthmd-mcp`，以及用于显式 CLI 工作流的 `healthmd`。另一个可直接通过 iPhone 使用 MCP 的跨平台 CLI 已作为明确未经资格验证的公开预览版打包；首个稳定版仍必须完成实体设备发布质量验证。

<div class="callout">
<strong>HealthKit 数据始终保留在 iPhone 上。</strong>
<p style="margin-top:6px;">配置仅允许本地客户端访问 Health.md 的限定接口。它不会让电脑或智能体直接访问 HealthKit，也不会将您的源数据库上传到 Health.md 云端。</p>
</div>

## 选择接口

| 目标 | 首选方式 | 后续阅读 |
|---|---|---|
| 让 Codex 或 Claude 在 Mac 上查询健康数据并生成图表 | 通过 stdio 使用内置 `healthmd-mcp` | [MCP 服务器与工具](/zh-hans/docs/mcp/) |
| 在 Mac 脚本中导出规范 JSON 或生成文件 | 内置 `healthmd` CLI | [CLI](/zh-hans/docs/cli/) |
| 不运行 Mac 应用，直接连接已打开的 iPhone | 可移植直连 CLI（**预览版**） | [直接访问 iPhone](/zh-hans/docs/cli-direct/) |
| 基于精确的请求和响应封装进行开发 | 环回 API 或公开契约 | [环回 API](/zh-hans/docs/agent-api/) |
| 解析架构、记录、证据或生成的测试样例 | 版本化参考文档 | [数据契约](/zh-hans/docs/reference/) |

后端和传输方式均需明确选择；Health.md 不会在 iPhone 直连失败时静默回退到 Mac 应用。

## 通过 Mac 应用使用 Codex

<div class="availability available">
<strong>现已可用 · 已签名的 Mac 辅助程序</strong>
<p>安装 Health.md Mac 版，打开其 <strong>CLI</strong> 界面；如果应用未安装在 <code>/Applications</code> 中，请复制界面中显示的内置 MCP 路径。</p>
</div>

将独立签名的 `healthmd-mcp` 辅助程序添加到 `~/.codex/config.toml`：

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

重启 Codex，调用 `healthmd_doctor`，使用 `healthmd_metrics` 确定 ID，通过更新工具明确获取一个小范围，然后使用 `healthmd_metric_chart` 等类型化工具查询该范围。内置服务器提供 21 个工具，包括 Mac 就绪状态、加密上下文刷新作业、证据和可视化。

## 在 Mac 上使用 Claude Desktop 或 Claude Code

将内置辅助程序添加到 Claude Desktop 的 MCP 配置，或受信任的 Claude Code `.mcp.json`：

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

更改配置后重启客户端。项目范围的配置仍需授予工作区信任并明确批准服务器。当工具需要最新 HealthKit 数据时，请保持 Mac 和 iPhone 应用处于打开状态。

## 在 Mac 上使用任意 stdio MCP 客户端

配置一个本地进程：

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

主机负责管理 stdin 和进程生命周期。请勿将辅助程序作为普通交互式命令启动，也不要使用会改变 JSON-RPC 输出的 shell 对其进行包装。使用 MCP `tools/list` 查看已安装应用提供的确切架构。

## 可移植直连设置

<div class="availability preview">
<strong>公开预览版 · 尚未取得稳定版资格</strong>
<p>跨平台 Rust CLI、<code>healthmd setup codex</code>、同一二进制文件中的 <code>healthmd mcp serve</code>，以及 Linux/Windows 直连配对均已作为明确未经资格验证的公开预览版打包。</p>
</div>

在 macOS 或 Linux 上使用 <code>brew install CodyBontecou/tap/healthmd</code> 安装。之后，`healthmd setup codex` 会以幂等方式配置 Codex 并启动 iPhone 直连配对。请使用发布证据中指定的准确移动端构建；软件包发布并不能证明移动端兼容性。[iPhone 直连 CLI](/zh-hans/docs/cli-direct/)页面介绍了传输和协议行为。

## 显式 CLI 工作流

对于规范数据提取或面向文件的自动化，请直接调用 `healthmd`，而不是让 MCP 主机传输大型源数据正文：

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

内置 Mac 辅助程序与独立跨平台 CLI 的可用功能和命令语法有所不同。将命令复制到无人值守的自动化流程前，请先阅读 [Health.md CLI](/zh-hans/docs/cli/)。

## 可移植配对与就绪状态

<div class="availability preview">
<strong>预览版 · 可移植直连工作流</strong>
<p>以下是当前公开软件包中提供的可移植工作流。内置 Mac MCP 路径仍会使用 Mac 应用现有的 iPhone 连接。</p>
</div>

MCP 和 CLI 直连工作流需要先与 iPhone 上的 Health.md 完成一次受信任配对。配对使用经过身份验证的加密通道，并在 macOS、Linux 或 Windows 上使用原生凭据存储。

1. 在 iPhone 上的 Health.md 中启用 **Direct CLI 访问**。
2. 通过 `healthmd setup codex` 或 `healthmd direct pair` 启动配对。
3. 在 iPhone 上批准限定范围的配对请求。
4. 启动查询或导出时，请保持 Health.md 在前台运行。
5. 执行较大任务前，在 MCP 中调用 `healthmd_doctor`，或在可移植 CLI 中运行 `healthmd status`。

有关 Manual IP、Tailscale、端口、受信任设备、前台运行和恢复的详细信息，请参阅[直接访问 iPhone](/zh-hans/docs/cli-direct/)。

## 配置边界

本地智能体配置**不会**授予以下权限：

- 任意读取或写入 HealthKit；
- 任意访问文件系统；
- 通过 MCP 使用任意 URL、shell 命令、提示词、根目录或采样；
- 隐藏缺失数据、覆盖范围、单位、证据或限制；
- 在没有相应批准的情况下恢复、取消任务或覆盖生成的文件。

要获得完整结果，请检查请求范围、覆盖情况、遍历过程、限制和源架构，而不仅是进程是否成功。

## 继续阅读

<div class="related">
  <a href="/zh-hans/docs/mcp/"><span>工具接口</span>查看 21 个已发布的 Mac 工具、预览版中的 19 个可移植工具、MCP Apps、架构、分页、导出和沙盒边界。</a>
  <a href="/zh-hans/docs/agent-queries/"><span>首次查询</span>运行类型化指标、睡眠、锻炼、比较、覆盖范围和证据工作流。</a>
  <a href="/zh-hans/docs/cli-extract/"><span>规范数据</span>提取选定的 schema-v8 文档和源记录，无需在聊天中传输大型数据正文。</a>
  <a href="/zh-hans/docs/reference/"><span>契约</span>浏览版本化数据结构、字段清单、生成的测试样例和集成方案。</a>
</div>
