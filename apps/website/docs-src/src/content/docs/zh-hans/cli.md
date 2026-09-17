---
title: "Health.md CLI"
description: "在 macOS、Linux 或 Windows 上安装独立的 healthmd CLI，直接与 iPhone 或 Android 设备配对，检查就绪状态，导出数据，运行查询并管理持久作业。无需 Mac 应用。"
---

独立版 `healthmd` CLI 可在 macOS、Linux 和 Windows 上运行，直接与 iPhone（协议 v1）或 Android（协议 v2）上已打开的 Health.md 应用配对。它完全不需要 Health.md Mac 版，没有后端选择，也绝不会从计算机读取 Apple Health 或 Health Connect。

<div class="callout">
<strong>健康数据保留在手机上。</strong>
<p style="margin-top:6px;">CLI 绝不会从计算机读取 Apple Health 或 Health Connect。每次新的平台健康读取都由 iPhone 或 Android 上当前打开的 Health.md 应用完成。CLI 接收经过验证的结果或文件。</p>
</div>

## 安装独立 CLI

<div class="availability preview">
<strong>公开预览版 · 尚未获得合格稳定版认定</strong>
<p>跨平台 Rust CLI 已公开发布，但其精确的移动矩阵仍在等待实机发布认定。</p>
</div>

在 macOS 或 Linux 上，使用 <code>brew install CodyBontecou/tap/healthmd</code> 安装预览版。请使用发布证据中指定的精确移动构建版本；软件包的发布并不能证明移动兼容性。

独立 Rust CLI 可在 macOS、Linux 和 Windows 上运行，使用 Manual IP 或 Tailscale 直连，不需要 Mac 应用。它通过协议 v1 与 iPhone 来源配对，通过协议 v2 与 Android 来源配对，并带有自动化的 Swift↔Rust 与 Kotlin↔Rust 兼容性关卡。协议兼容性已经实现；在首个合格稳定版发布之前，仍需完成实机发布 QA。每个版本都附带带校验和的归档、PowerShell 安装程序以及 `cargo install healthmd-cli --locked`。

可移植客户端在三个桌面平台上支持 iPhone 和 Android 的配对、状态、原始导出、生成文件目标、恢复和取消。规范提取与类型化 MCP 查询是 iPhone 功能。Android 原始快照保留其提供商原生的 Health Connect 契约，而不是转换为 HealthKit 形式的数据。Android 类型化查询尚未实现。生成文件导出时，手机将目标视为不透明标签；接收方 CLI 会在主机文件系统下验证并持久绑定它。Android 协议 v2 在每个 CLI 操作系统上提交文件目标，并将每个生成作业限制为 4,096 个文件。

## 命令索引

| 命令 | 用途 |
|---|---|
| `healthmd status` | 检查实时就绪状态或某个本地持久作业 |
| `healthmd export` | 写入生成文件或返回严格的原始 JSON |
| `healthmd extract` | 获取选定的规范 `healthmd.health_data` 对象（iPhone） |
| `healthmd query` | 运行固定的类型化查询操作（iPhone） |
| `healthmd resume` | 恢复不可变的持久导出作业 |
| `healthmd cancel` | 请求显式取消 |
| `healthmd direct ...` | 配对、列出和移除手机的直连信任 |
| `healthmd mcp ...` | 提供或检查固定的 MCP 工具面 |
| `healthmd setup codex` | 一步完成 Codex 配置和 iPhone 配对 |

直连命令与 iPhone（协议 v1）或 Android（协议 v2）来源配对。规范 `extract` 和所有类型化查询命令都是 iPhone 功能；Android 直连来源返回提供商原生的 Health Connect 原始快照和生成文件。

```bash
# 就绪状态与本地信任
healthmd status
healthmd direct devices

# 平台原生原始导出；省略 --output 可将验证过的 JSON/NDJSON 流式输出到 stdout
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# 通过与 MCP 相同的操作注册表进行类型化查询（iPhone）
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# 限定范围的规范提取（iPhone）
healthmd extract --category Sleep --last 7 --output sleep.json

# 在所有 CLI 操作系统上生产生成文件
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# 持久操作
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### 可移植的基于配置文件的文件导出

独立直连 CLI 可以按稳定 ID 解析两个受支持手机平台上保存的配置文件。配置文件提供冻结的输出设置；计算机目标仍需显式指定：

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID` 不能与 `--use-device-settings` 或指标/类别选择器组合使用，未知 ID 会安全失败而不是使用当前设置。请在 iPhone 或 Android 上的**设置 → 导出配置文件 → 配置文件 ID** 处复制该 ID。自动化和目标行为详见[导出配置文件](/zh-hans/docs/export-profiles/)。

可移植直连客户端无需 MCP 封装即可调用任何受支持的 iPhone 类型化操作：

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## 内置 Mac 辅助程序

Health.md Mac 版在应用内附带其自己的已签名 Swift 辅助程序 `healthmd` 和 `healthmd-mcp`。该辅助程序是 Mac 应用的功能，而不是独立 CLI 的后端：默认情况下，它与正在运行的 Mac 应用的回环服务器通信，提供加密本地查询、MCP 工具以及已在 Health.md Mac 版中选择的目标文件夹；它还提供可用 `--backend direct` 选择的兼容直连 iPhone 模式。两个客户端绝不会静默切换模式。

<div class="availability available">
<strong>现已推出 · Health.md Mac 版</strong>
<p>已签名的 Swift CLI 和 MCP 辅助程序随已发布的 Mac 应用一起提供。</p>
</div>

打开 Mac 应用并选择 **CLI**，即可查看所安装副本的路径、设置命令、代理提示以及可选的代理技能安装程序。

应用捆绑包的常规路径为：

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

在单次 shell 会话中使用别名：

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

或在用户拥有的 bin 目录中创建持久符号链接：

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

如果 shell 尚未包含 `~/.local/bin`，请将其加入 `PATH`：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

在不启动 MCP stdio 循环的情况下验证辅助程序：

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` 返回包含 Mac、加密上下文和 iPhone 就绪状态的 `healthmd.cli_doctor` JSON。它不会打印健康数值。

### 内置辅助程序的命令

| 命令 | 用途 |
|---|---|
| `healthmd export --iphone ...` | 通过 Mac 应用写入生成文件或返回严格的原始 JSON |
| `healthmd status` | 检查 Mac/iPhone 就绪状态或某个持久作业 |
| `healthmd doctor` | 说明 Mac、加密上下文和 iPhone 的就绪状态 |
| `healthmd metrics list` | 返回规范的可查询指标目录 |
| `healthmd query` | 获取并查询选定的类型化指标 |
| `healthmd sleep sessions` | 返回一级睡眠时段和固定窗口 |
| `healthmd training align` | 将锻炼与前后的睡眠对齐 |
| `healthmd workouts` | 列出带证据的类型化锻炼 |
| `healthmd coverage` | 检查日期和指标覆盖或缺失情况 |
| `healthmd compare` | 使用调用方选择的聚合比较精确期间 |
| `healthmd evidence training` | 构建事实性训练证据包 |
| `healthmd resume` / `healthmd cancel` | 管理持久作业 |
| `healthmd agent ...` | 调用低级回环查询和作业 API |
| `healthmd --backend direct ...` | 辅助程序的兼容直连 iPhone 模式 |

在辅助程序的直连模式下，Mac 上下文查询、证据、doctor、指标和刷新子命令会返回 `backend_unsupported`，而不是切换到 Mac 应用。

### 首个 Mac 应用工作流

1. 如果计划写入文件，请在 Mac 上打开 Health.md 并选择目标文件夹。
2. 在已配对的 iPhone 上打开 Health.md，等待与 Mac 建立连接。
3. 检查就绪状态。
4. 在请求较长的历史记录之前，先运行一个小命令。

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

新查询只获取所提供的指标、来源、日期以及摘要或无损细节。它们不会更改 iPhone 上已保存的导出设置。

### 内置辅助程序的文件与原始导出

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings
```

当前没有日历天数上限。`--all` 会让 iPhone 找到所选来源最早的可用记录，固定解析出的范围，并通过有界分区进行处理。可用存储空间和异常密集的一天仍是实际限制。

`--raw` 会在不更改 iPhone 偏好的情况下临时请求规范无损源记录。它不写入生成文件，也不包含已连接提供商的附属数据。

## 规范提取还是派生查询？

需要源形态的数据时使用 `extract`：

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

需要与证据关联的类型化视图时使用查询命令。独立 CLI 提供固定的类型化操作；内置 Mac 辅助程序还提供以下高级命令：

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8 是 Apple 的公开源契约。查询、证据、作业和回执架构描述的是传输或派生视图，它们不会替代源架构。规范提取是 iPhone 功能；Android 直连来源改为通过原始导出公开提供商原生的 Health Connect 快照。

## 机器可读行为

默认情况下，命令在 stdout 或显式 `--output` 路径上使用带版本的 JSON。规范提取可以选择 JSONL 输出，高级查询可以选择有意有损的表格。不含健康数值的进度可以使用 stderr。`--help` 为纯文本。命令启动前的参数错误以退出码 2 在 stderr 上输出纯文本。

进程成功退出并不足以证明健康数据完整。请检查：

- 外层状态。
- 请求范围的状态。
- 每天和每次查询的结果。
- 缺失区间。
- `next_cursor` 或遍历回执。
- 源架构和版本。
- 限制与警告。

完全为空的结果表示 Health.md 已表示请求的范围且未找到观测数据。它与零、缺失、失败、跳过或不受支持并不相同。

## 安全自动化

使用自动化主机的进程超时，并对不应提示输入的命令保持 stdin 关闭。在带有 GNU `timeout` 的系统上：

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

超时、Ctrl-C、进程退出、网络断开和耗尽的 iOS 后台时间都不会取消持久作业。请检查作业 ID 并恢复它，而不是启动重复作业。

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

只有 iPhone 确认后，取消才成为最终状态。

## 隐私规则

原始和无损输出可能包含精确的时间戳、路线、临床记录、药物、情绪条目、心电图数值、来源信息和附件。请优先使用输出文件而不是终端输出。不要将载荷粘贴到问题报告、代理转录、CI 日志或 shell 跟踪中。

内置 Mac 辅助程序的本地查询 API 没有持有者令牌、注册、访问配置文件或授权数据库。回环可达性就是它的完整访问边界。Mac 应用打开期间，任何本地进程都可以使用它；切勿将端口 `17645` 代理或暴露给另一台机器。

## 后续指南

<div class="related">
  <a href="/zh-hans/docs/cli-direct/"><span>无需 Mac 应用</span>直连手机 CLI：与 iPhone 或 Android 配对，查看传输方式、原始与文件导出、后台行为和平台支持。</a>
  <a href="/zh-hans/docs/cli-extract/"><span>源数据</span>规范提取：选择指标、对象、细节、JSON 指针、JSONL 和回执。</a>
  <a href="/zh-hans/docs/cli-jobs/"><span>自动化</span>持久作业：超时、恢复、取消、部分结果和安全脚本。</a>
  <a href="/zh-hans/docs/agents/"><span>代理</span>本地代理工作流：加密上下文、直连范围、类型化命令和证据。</a>
  <a href="/zh-hans/docs/mcp/"><span>MCP</span>配置沙箱化的 stdio 辅助程序并查看其工具边界。</a>
  <a href="/zh-hans/docs/reference/api-and-cli/"><span>契约</span>API 和 CLI 参考：精确路由、架构、响应和生成的夹具。</a>
</div>
