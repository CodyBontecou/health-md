---
title: "Health.md CLI"
description: "选择 Mac 应用或 iPhone 直连后端，安装 healthmd，检查就绪状态，导出文件，提取规范 Apple Health 数据，运行类型化查询并自动执行持久作业。"
---

`healthmd` 命令有两种运行模式。如果需要加密本地查询、MCP 工具，或使用已在 Health.md Mac 版中选择的目标文件夹，请使用 Mac 应用后端。如果希望在不运行 Mac 应用的情况下获取原始数据或生成文件，请使用 iPhone 直连后端。

<div class="callout">
<strong>HealthKit 始终保留在 iPhone 上。</strong>
<p style="margin-top:6px;">两种 CLI 后端都不会从计算机读取 Apple Health。每次获取全新 HealthKit 数据时，都由当前已打开的 Health.md iPhone 应用执行读取；CLI 只接收经过验证的结果或文件。</p>
</div>

## 选择后端

| 功能 | Mac 应用后端 | iPhone 直连后端 |
|---|---|---|
| 内置 Mac 辅助程序的默认后端 | 是 | 否，使用 `--backend direct` 选择 |
| 需要 Health.md Mac 版保持打开 | 是 | 否 |
| 获取新数据时需要在 iPhone 上打开 Health.md | 是 | 是 |
| 文件目标位置 | Mac 应用中选择的文件夹 | 已存在的绝对 `--destination` |
| 严格原始导出 | 支持 | 支持 |
| 规范 `healthmd extract` | 支持 | 支持 |
| 加密上下文、类型化查询和证据 | 支持 | 不支持 |
| `healthmd-mcp` | 支持 | 不支持 |
| 手动 IP 或 Tailscale | Mac 同步或明确的直连模式 | 支持 |
| “附近”直连传输 | 仅内置 Swift 辅助程序 | 可移植 Rust 客户端不支持 |

后端和传输方式绝不会在未提示的情况下回退。直连命令不会为满足查询而切换到 Mac 应用；“附近”连接失败后也不会切换到手动 IP。

## 安装内置 Mac 辅助程序

<div class="availability available">
<strong>现已提供 · Health.md Mac 版</strong>
<p>已发布的 Mac 应用内置经过签名的 Swift CLI 和 MCP 辅助程序。</p>
</div>

Health.md Mac 版包含经过签名的 `healthmd` 和 `healthmd-mcp` 辅助程序。打开 Mac 应用并选择 **CLI**，即可查看当前安装副本的路径、设置命令、智能体提示和可选的智能体技能安装程序。

应用包的常规路径为：

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

可在单个 shell 会话中设置别名：

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

也可以在用户拥有的 bin 目录中创建持久符号链接：

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

如果 shell 尚未包含 `~/.local/bin`，请将它添加到 `PATH`：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

无需启动 MCP stdio 循环即可验证 CLI：

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` 返回 `healthmd.cli_doctor` JSON，其中包含 Mac、加密上下文和 iPhone 的就绪状态，不会输出健康数值。

## 可移植 CLI 状态

<div class="availability preview">
<strong>预览版 · 尚无公开软件包</strong>
<p>跨平台 Rust CLI 仍在等待实体 iPhone 发布质量验证和首个合格软件包。</p>
</div>

独立 Rust CLI 正以 `0.1.0-alpha.1` 版本开发。它可在 macOS、Linux 和 Windows 上运行，默认通过手动 IP 或 Tailscale 直连，不需要 Mac 应用。协议兼容性和跨语言测试样例已经实现，但在首次公开发布前，仍需完成实体 iPhone 发布质量验证和公开打包。

正式版本发布前，请使用内置 Mac 辅助程序。不要依赖尚未发布的 Homebrew、crates.io、GitHub 安装程序或下载 URL。

可移植客户端在三个平台上都支持原始导出、规范提取、配对、状态、恢复、取消和生成文件目标位置。使用协议 v1 导出文件时，iPhone 会将目标位置视为不透明的目标标签，接收端 CLI 则会验证该标签，并将其持久绑定到主机文件系统中的目标位置。

## 命令索引

| 命令 | 用途 | 后端 |
|---|---|---|
| `healthmd status` | 检查实时就绪状态或一项本地持久作业 | 两者 |
| `healthmd doctor` | 说明 Mac、加密上下文和 iPhone 就绪状态 | Mac 应用 |
| `healthmd metrics list` | 返回可查询指标的规范目录 | Mac 应用 |
| `healthmd extract` | 获取所选的规范 `healthmd.health_data` 对象 | 两者 |
| `healthmd query` | 获取并查询所选类型化指标 | Mac 应用 |
| `healthmd sleep sessions` | 返回一等的睡眠时段和固定窗口 | Mac 应用 |
| `healthmd training align` | 将锻炼与前后睡眠对齐 | Mac 应用 |
| `healthmd workouts` | 列出带证据的类型化锻炼 | Mac 应用 |
| `healthmd coverage` | 检查日期和指标覆盖范围或缺失状态 | Mac 应用 |
| `healthmd compare` | 使用调用方指定的聚合方式比较精确周期 | Mac 应用 |
| `healthmd evidence training` | 构建仅陈述事实的训练证据包 | Mac 应用 |
| `healthmd export` | 写入生成文件或返回严格原始 JSON | 两者 |
| `healthmd resume` | 恢复不可变的持久导出作业 | 两者 |
| `healthmd cancel` | 明确请求取消 | 两者 |
| `healthmd agent ...` | 调用底层环回查询与作业 API | Mac 应用 |
| `healthmd direct ...` | 配对、列出和删除 iPhone 直连信任 | 直连 |

## 首次使用 Mac 应用后端

1. 如果要写入文件，请在 Mac 上打开 Health.md 并选择目标文件夹。
2. 在已配对的 iPhone 上打开 Health.md，等待 Mac 建立连接。
3. 检查就绪状态。
4. 请求大量历史记录前，先运行一个小范围命令。

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

全新查询只会获取提供的指标、来源、日期，以及摘要或无损详情，不会更改 iPhone 中已保存的导出设置。

## 文件导出与原始导出

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

目前没有日历日数量上限。`--all` 会要求 iPhone 查找所选来源记录中最早可用的一条，固定解析后的日期范围，再通过有界分区处理。可用存储空间和某个异常密集的日期仍是实际限制。

`--raw` 会临时请求规范无损来源记录，但不会更改 iPhone 偏好设置。它不会写入生成文件，也不包含已连接提供方的辅助记录。

## 规范提取还是派生查询？

需要与来源结构一致的数据时，请使用 `extract`：

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

需要类型化且与证据关联的视图时，请使用查询命令：

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7 是公开来源契约。查询、证据、作业和回执架构描述传输或派生视图，不能替代来源架构。

## 机器可读行为

默认情况下，命令会把版本化 JSON 写入 stdout 或明确的 `--output` 路径。规范提取可选择 JSONL；高级查询可选择有意简化且有损的表格。不含健康数据的进度可以写入 stderr。`--help` 使用纯文本。命令开始前的参数错误会以纯文本写入 stderr，并以 2 退出。

进程成功退出不足以证明健康数据完整。请检查：

- 外层状态；
- 请求范围状态；
- 每日和每项查询的结果；
- 缺失区间；
- `next_cursor` 或遍历回执；
- 来源架构和版本；
- 限制和警告。

完全为空的结果表示 Health.md 已表示请求范围，但没有找到观测值。它不等同于零、缺失、失败、跳过或不支持。

## 安全自动化

请使用自动化主机的进程超时，并为不应提示的命令关闭 stdin。在安装了 GNU `timeout` 的系统上：

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

超时、Ctrl-C、进程退出、网络中断和 iOS 后台时间耗尽都不会取消持久作业。请检查作业 ID 并恢复同一作业，不要启动重复作业。

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

只有 iPhone 确认后，取消才进入终止状态。

## 隐私规则

原始和无损输出可能包含精确时间戳、路线、临床记录、药物、情绪条目、ECG 数值、溯源信息和附件。请优先写入输出文件，而不是输出到终端。不要把载荷粘贴到问题报告、智能体记录、CI 日志或 shell 跟踪中。

本地查询 API 没有持有者令牌、注册、访问配置或授权数据库。能否访问环回地址就是完整的访问边界。Mac 应用打开时，任何本地进程都能使用该 API，因此切勿代理端口 `17645`，也不要将其暴露给其他计算机。

## 后续指南

<div class="related">
  <a href="/zh-hans/docs/cli-direct/"><span>无需 Mac 应用</span>iPhone 直连 CLI：配对、传输方式、原始与文件导出、后台行为和平台支持。</a>
  <a href="/zh-hans/docs/cli-extract/"><span>来源数据</span>规范提取：选择指标、对象、详细程度、JSON Pointer、JSONL 和回执。</a>
  <a href="/zh-hans/docs/cli-jobs/"><span>自动化</span>持久作业：超时、恢复、取消、部分结果和安全脚本。</a>
  <a href="/zh-hans/docs/agents/"><span>智能体</span>本地智能体工作流：加密上下文、直连范围、类型化命令和证据。</a>
  <a href="/zh-hans/docs/mcp/"><span>MCP</span>配置沙盒化 stdio 辅助程序并检查工具边界。</a>
  <a href="/zh-hans/docs/reference/api-and-cli/"><span>契约</span>API 与 CLI 参考：精确路由、架构、响应和生成的测试样例。</a>
</div>
