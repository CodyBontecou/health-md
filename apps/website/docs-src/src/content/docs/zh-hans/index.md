---
title: 从 Health.md 开始。
description: 导出 Apple Health 或 Health Connect 数据，将已签名的 Mac 辅助程序连接到本地智能体，并基于 Health.md 的版本化契约进行构建。
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">现已推出 · 已签名的 Mac 辅助程序</p>
    <p>从手机导出健康数据，通过已签名的 Mac 辅助程序连接本地智能体，或基于版本化契约进行构建。HealthKit 读取操作始终在 iPhone 本地完成，Health Connect 读取操作始终在 Android 本地完成。</p>
    <div class="docs-command" aria-label="Health.md 随附的就绪状态命令"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">安装在其他位置？请从 <strong>Health.md Mac 版 → CLI</strong> 复制随附辅助程序的路径。</p>
    <div class="docs-actions">
      <a class="docs-button" href="/zh-hans/docs/iphone-first-export/">首次从 iPhone 导出</a>
      <a class="docs-button-secondary" href="/zh-hans/docs/configuration/">连接智能体</a>
      <a class="docs-button-secondary" href="/zh-hans/docs/reference/">浏览契约</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="选择一个 Health.md 目标">
  <a href="/zh-hans/docs/iphone-first-export/"><span>01 · 导出</span><strong>从 iPhone 开始</strong>授权 Apple Health、选择文件夹、预览输出，然后执行首次导出。</a>
  <a href="/zh-hans/docs/configuration/"><span>02 · 查询</span><strong>连接本地智能体</strong>通过已签名的 Mac MCP 辅助程序连接 Codex、Claude 或其他 stdio 客户端。</a>
  <a href="/zh-hans/docs/reference/"><span>03 · 构建</span><strong>使用稳定契约</strong>集成架构、记录、证据、生成的测试样例和精确封装。</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>个随附的 Mac MCP 工具</span></div>
<div><strong>4</strong><span>种导出格式</span></div>
<div><strong>v7</strong><span>公共导出架构</span></div>
<div><strong>0</strong><span>次必需的 Health.md 云端中转</span></div>
</div>

<p class="docs-section-kicker">现已推出 · macOS</p>

## 五分钟完成本地智能体快速入门

在 Mac 上打开 Health.md，然后在已配对的 iPhone 上打开 Health.md 并等待连接。随附的辅助程序会在不返回健康数值的情况下检查就绪状态、列出睡眠指标，并执行单日查询：

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

就绪的 `doctor` 结果使用 `healthmd.cli_doctor` 架构，并会在设置未完成时提供后续操作。若使用 Codex 或 Claude，请继续阅读[配置智能体](/zh-hans/docs/configuration/)，并将客户端指向单独的已签名 `healthmd-mcp` 辅助程序。

<p class="docs-section-kicker">按目标选择</p>

## 配置与连接

<div class="related">
  <a href="/zh-hans/docs/configuration/"><span>现已推出 · Mac</span>配置 — 将 Codex、Claude 或其他 stdio 客户端连接到已签名的 MCP 辅助程序。</a>
  <a href="/zh-hans/docs/mcp/"><span>现已推出 · Mac</span>MCP 服务器与应用 — 探索 21 个随附工具、呈现私密可视化内容，并了解便携预览版。</a>
  <a href="/zh-hans/docs/cli/"><span>现已推出 · Mac</span>Health.md CLI — 安装随附的辅助程序、检查就绪状态、查询数据，并区分便携预览版。</a>
  <a href="/zh-hans/docs/agents/"><span>架构</span>智能体上下文 — 了解请求范围、本地信任、加密上下文、证据、保留策略和隐私。</a>
</div>

<p class="docs-section-kicker">日常操作</p>

## 查询、提取与自动化

<div class="related">
  <a href="/zh-hans/docs/agent-queries/"><span>类型化查询</span>查询指标、睡眠时段、锻炼、对比、覆盖情况和事实证据。</a>
  <a href="/zh-hans/docs/cli-direct/"><span>预览 · 便携 CLI</span>直接访问 iPhone — 在独立软件包发布前，了解手动 IP 或 Tailscale 配对。</a>
  <a href="/zh-hans/docs/cli-extract/"><span>源数据</span>规范提取 — 获取选定的架构 v7 每日数据、来源记录、投影或 JSONL。</a>
  <a href="/zh-hans/docs/cli-jobs/"><span>可靠运行</span>持久作业 — 安全处理超时、结果未知、恢复、取消和部分结果。</a>
  <a href="/zh-hans/docs/agent-api/"><span>底层接口</span>环回 API — 使用精确的查询、证据、游标、刷新和持久作业路由。</a>
  <a href="/zh-hans/docs/reference/integration-recipes/"><span>模式</span>集成方案 — 解析并验证 Health.md 输出，同时保持契约的严格性。</a>
</div>

<p class="docs-section-kicker">稳定接口</p>

## 数据契约与结构

<div class="related">
  <a href="/zh-hans/docs/reference/"><span>契约导航</span>导出参考 — 浏览架构、指标、格式、记录和互操作性测试样例。</a>
  <a href="/zh-hans/docs/reference/api-and-cli/"><span>自动化</span>API 与 CLI 契约 — 查看封装、路由、退出行为和生成的示例。</a>
  <a href="/zh-hans/docs/reference/evidence-packets/"><span>智能体结果</span>查询与证据 — 类型化值、覆盖范围、缺失状态、操作和确定性标识。</a>
  <a href="/zh-hans/docs/reference/daily-records/"><span>架构 v7</span>每日记录 — 了解公开来源文档及其归属规则。</a>
  <a href="/zh-hans/docs/shared-metric-registry/"><span>词汇表</span>指标注册表 — 使用稳定的跨平台指标 ID、类别、单位和配置元数据。</a>
  <a href="/zh-hans/docs/reference/generated/"><span>机器可读</span>生成的构件 — 查看规范字段、测试样例、消息清单和 CLI 契约。</a>
</div>

<p class="docs-section-kicker">产品工作流</p>

## 应用与导出

<div class="related">
  <a href="/zh-hans/docs/iphone-first-export/"><span>从这里开始 · iPhone</span>首次导出 — 授权 Apple Health、选择文件夹、预览输出并验证写入的文件。</a>
  <a href="/zh-hans/docs/android/"><span>Android</span>Health Connect — 选择文档提供方文件夹并配置平台自动化。</a>
  <a href="/zh-hans/docs/export/"><span>文件</span>导出 — 以 Markdown、CSV、JSON 或 Obsidian Bases 格式导出明确的日期范围。</a>
  <a href="/zh-hans/docs/format/"><span>结构</span>格式自定义 — 控制单位、日期、frontmatter、文件名和写入行为。</a>
  <a href="/zh-hans/docs/scheduling/"><span>后台</span>计划导出 — 了解每日和每周导出行为及平台限制。</a>
  <a href="/zh-hans/docs/shortcuts/"><span>自动化</span>快捷指令与 App Intents — 通过 Apple 工作流触发导出、摘要和状态检查。</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">文档结构更新于 2026-08-02</p>
