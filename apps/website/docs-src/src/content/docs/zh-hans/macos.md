---
title: "macOS 应用"
description: "将 Health.md Mac 版用作 iPhone 导出目标、本地 CLI 和 MCP 主机、加密健康上下文存储、历史记录查看器及文件夹权限管理方。"
---

Health.md Mac 版有两个本地用途：

1. 接收 iPhone 导出作业，并将文件写入您选择的文件夹；
2. 托管本地智能体使用的环回 CLI、查询 API、加密健康上下文和 MCP 适配器。

Apple Health 仍位于 iPhone 上。Mac 应用不会直接读取 HealthKit。

## 主要区域

<div class="options">
<div class="option"><strong>同步</strong><p>显示 Mac 是否可被发现，以及是否已准备好接收 iPhone 导出作业。</p></div>
<div class="option"><strong>目标文件夹</strong><p>存储 Markdown、JSON、CSV、Obsidian Bases、汇总文件、ZIP 和每日笔记输出所需的安全作用域书签。</p></div>
<div class="option"><strong>计划</strong><p>显示 Mac 端计划和就绪状态。HealthKit 数据仍由 iPhone 提供。</p></div>
<div class="option"><strong>历史记录</strong><p>追踪由桌面端写入的文件的导出结果、持久作业进度、错误和重试上下文。</p></div>
<div class="option"><strong>设置</strong><p>显示目标位置状态、加密上下文保留控制和本地 CLI 配置。</p></div>
<div class="option"><strong>菜单栏</strong><p>在 Health.md 保持本地可用时，提供快捷状态、设置和应用访问入口。</p></div>
<div class="option"><strong>CLI</strong><p>安装随附的 <code>healthmd</code> 和 <code>healthmd-mcp</code> 辅助程序、复制设置提示、安装可选的智能体技能，并显示已测试的命令。</p></div>
</div>

## 设置 Mac 目标位置

1. 在 Mac 上安装并打开 Health.md。
2. 在本地磁盘、iCloud Drive 或 Obsidian 知识库中选择目标文件夹。
3. 在 iPhone 的“同步”标签页中启用 Mac 连接。
4. 在 iPhone 上选择“已连接的 Mac”作为导出目标。
5. 配置导出，然后轻点“导出”。

iPhone 会获取 HealthKit 数据和生效的设置快照。当前对等设备会传输有界且经过校验和验证的分区。Mac 使用生产环境导出器写入所请求的文件。

<div class="callout">
<strong>HealthKit 限制。</strong>
<p style="margin-top:6px;">Mac 无法自行查询 Apple Health。新的导出和智能体上下文需要已连接且保持打开的 iPhone 应用。如果存储的覆盖范围足够，则无需重新连接 iPhone 也可运行缓存的加密查询。</p>
</div>

## CLI 和智能体设置

打开 Mac 应用的 **CLI** 区域，可以：

- 查看此应用包内已签名辅助程序的确切路径；
- 复制别名或 `~/.local/bin` 符号链接命令；
- 复制智能体辅助设置提示；
- 将可选的 `healthmd-cli` 技能安装到您选择的目录；
- 查看当前的状态、诊断、提取、查询、睡眠、训练、锻炼、覆盖范围和导出命令；
- 查看常见的就绪状态错误。

未经您的操作，应用绝不会修改 shell 启动文件，也不会安装到系统目录。

从以下命令开始：

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

后端选择请参阅 [Health.md CLI](/zh-hans/docs/cli/)，查询架构请参阅[本地智能体](/zh-hans/docs/agents/)。

## 加密健康上下文

新的查询和证据请求使用专用的上下文获取模式。iPhone 会严格按照请求的指标、来源、日期和详细程度读取数据。此过程不会创建导出文件，也不会更改已保存的导出偏好设置。

Mac 将每个精简归属日的数据分别存储在经过独立身份验证的 AES-256-GCM Blob 中。随机加密密钥存储在仅限本设备、解锁时可用的钥匙串项目中。文件名是随机的，不会透露日期或指标名称。

“设置”会显示已加密的归属日数量和日期范围。保留期限由两个独立操作控制：

- **删除较早的上下文**会删除严格早于所选边界的归属日；
- **删除所有加密上下文**会删除所有上下文文件和专用钥匙串密钥。

上下文保留操作绝不会删除 Apple Health 数据、导出文件、Mac 目标位置书签或已连接提供方的凭据。

## 环回 API 边界

Mac 应用监听 `127.0.0.1` 和 `::1` 的 `17645` 端口，为本地状态、导出、查询、证据、刷新和持久作业提供路由。

无需持有者令牌或智能体注册。应用打开时，任何本地进程均可调用此 API。切勿将该端口暴露、代理或通过隧道转发给其他计算机。

沙盒化的 `healthmd-mcp` 辅助程序仅接受规范的 HTTP 环回端点，并提供不含 shell、任意文件、SQL、URL 获取、资源、提示、根目录或采样功能的工具。

## Direct CLI 访问是独立功能

iPhone 的 **Direct CLI 访问**设置会在支持直接连接的 CLI 与 iPhone 之间建立独立的信任关系。它可绕过 Mac 应用，执行原始导出、规范提取、生成文件、状态查询、恢复和取消操作。

直接模式不使用 Mac 应用的加密查询上下文。便携式 `healthmd mcp serve` 会改为在前台运行的 iPhone 上直接执行新的类型化查询，并使用与配对相同的可执行文件身份。有关配对和平台支持，请参阅 [Direct iPhone CLI](/zh-hans/docs/cli-direct/)。

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/sync/"><span>目标位置</span>Mac 同步：配对 iPhone 和 Mac，以便在本地导出文件。</a>
  <a href="/zh-hans/docs/cli/"><span>终端</span>Health.md CLI：安装辅助程序、选择后端并执行命令。</a>
  <a href="/zh-hans/docs/agents/"><span>本地上下文</span>智能体：限定范围的获取、加密存储、证据和保留设置。</a>
  <a href="/zh-hans/docs/mcp/"><span>工具</span>本地 MCP 服务器：设置、工具目录和沙盒边界。</a>
  <a href="/zh-hans/docs/scheduling/"><span>工作流</span>计划导出：自动执行定期导出。</a>
</div>
