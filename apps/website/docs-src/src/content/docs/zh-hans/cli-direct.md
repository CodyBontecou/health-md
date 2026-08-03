---
title: "iPhone 直连 CLI"
description: "通过手动 IP、Tailscale 或受支持的“附近”传输将 healthmd 与 iPhone 配对，无需运行 Health.md Mac 版即可导出。"
---

直连后端会将 `healthmd` 连接到已打开的 Health.md iPhone 应用，命令无需经过 Health.md Mac 版。iPhone 读取 HealthKit，将结果暂存到受保护的存储空间，再把经过验证的分区传输给 CLI。

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>预览版 · 可移植直连 CLI</strong>
<p>macOS 上已可使用内置的 Swift 直连后端。跨平台 Rust 客户端仍处于 Alpha 阶段，正在等待实体 iPhone 发布质量验证和首个公开软件包；Linux 和 Windows 命令描述的是分阶段推出的工作流。</p>
</div>

## 直连模式支持的功能

- 一次性配对和可信重连；
- 在本地查看可信设备并解除配对；
- 实时检查 iPhone 就绪状态；
- 严格的原始 schema-v7 导出；
- 按选择范围进行规范提取；
- 使用生产导出器生成文件；
- 查看和恢复本地持久作业；
- 明确取消作业；
- 与 CLI 共用可执行文件的 `healthmd mcp serve` stdio 服务器，提供 iPhone 直连类型化查询、指标目录、证据、MCP Apps UI 和 PNG 后备图表。

`healthmd` 命令的直连后端不会模拟 Mac 应用的加密上下文 HTTP 路由。因此，面向 Mac 的 `doctor`、查询、证据和刷新子命令仍会返回 `backend_unsupported`，不会自行切换后端。需要对 iPhone 中的全新数据进行类型化分析时，请使用 `healthmd mcp serve`；也可以运行 `healthmd setup codex`，自动配置 Codex 并完成配对。`healthmd mcp schema [TOOL]` 会在本地输出准确的嵌套 MCP 输入架构和示例。睡眠问题应直接使用 `healthmd_sleep_sessions`，不要把规范 `extract` 输出当作类型化查询 API。

## 要求

- 支持直连的 `healthmd` 二进制文件，以及与之匹配的 Health.md iPhone 版本。
- 配对和启动新命令时，Health.md 必须在 iPhone 前台保持打开。
- 在 iPhone 上启用**设置 > Mac 同步 > Direct CLI 访问**。
- 已授予 HealthKit 和本地网络权限，受保护数据可用，并有可用的导出额度。
- 使用手动 IP 时，计算机地址必须可达，并开放 TCP 端口 `17647`。也可以使用 Tailscale 地址。
- 使用生成文件模式时，必须提供已存在的绝对目标路径。

CLI 充当监听器。iPhone 会连接到 Direct CLI 访问中填写的计算机地址。

## 传输方式支持

| 传输方式 | macOS 内置 Swift 辅助程序 | 可移植 Rust 客户端 |
|---|---:|---:|
| LAN 上的手动 IP | 支持 | macOS、Linux、Windows |
| Tailscale 地址 | 支持 | macOS、Linux、Windows |
| 附近 / MultipeerConnectivity | 支持 | 不支持 |

“附近”模式使用 Apple 的加密 Multipeer 会话，并叠加与手动 IP 相同的 Health.md 应用身份验证和加密。可移植客户端遇到“附近”模式时会返回 `transport_unsupported`。

## 通过手动 IP 完成一次配对

在计算机上启动监听器：

```bash
healthmd direct pair --transport manual-ip
```

该命令会把六位配对码、候选计算机地址和监听端口写入 stderr，将 stdout 保留给最终 JSON 结果。

在 iPhone 上：

1. 打开 **Health.md > 设置 > Mac 同步 > Direct CLI 访问**。
2. 启用 Direct CLI 访问。
3. 选择**手动 IP**。
4. 输入计算机的 LAN 或 Tailscale 地址。
5. 输入端口 `17647`；如果 CLI 使用了其他全局 `--port`，则输入对应端口。
6. 输入配对码并轻点“配对”。
7. 保持应用打开，直到双方都报告成功。

配对码会在 10 分钟后过期，绝不会通过网络发送或持久保存。

需要时可以改用其他端口：

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

后续执行状态、导出、恢复和取消命令时，请继续明确使用同一端口。

## 通过“附近”配对

“附近”模式仅适用于内置 Swift 辅助程序：

```bash
healthmd direct pair --transport nearby
```

在 iPhone 的 Direct CLI 访问中选择“附近”，输入显示的配对码，并让两台设备保持打开，直至完成配对。如果“附近”操作失败，系统不会自行切换到手动 IP。

## 可信设备

直连配对建立的信任关系独立于 Health.md Mac 应用的同步关系。

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

这些命令只读取或修改本地信任，不会联系 iPhone。在 iPhone 上，可使用**忘记已配对的 CLI**删除另一端的配对。

如果信任了多台 iPhone，请明确选择目标安装：

```bash
healthmd --backend direct --device DEVICE_UUID status
```

仅当本地信任已损坏或属于被替换的安装时，才使用 `healthmd direct reset-trust --confirm`。该命令会删除所有本地直连配对。重新配对前，也请在 iPhone 上忘记这些配对。

## 检查实时就绪状态

```bash
healthmd --backend direct --transport manual-ip status
```

直连状态响应只报告连接和安全状态，不包含健康数值。开始作业前，请检查以下字段：

| 字段 | 就绪值 |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | 启动新作业时为 `true` |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | 原始导出和提取可用时为 `true` |
| `iphone.can_trigger_exports` | 生成文件可用时为 `true` |

直连状态中的目标位置始终保持未选择。文件模式只使用命令明确提供的 `--destination`。

## 严格原始导出

请选择一种日期范围选择器：

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

省略 `--output` 时，经过验证的 JSON 会流式写入 stdout。对于敏感或大型响应，写入输出文件更安全。

严格原始导出返回 `healthmd.raw_result` v1，其中包含普通 schema-v7 `healthmd.health_data` 每日数据及其规范来源归档。它会临时请求无损详情，但不会更改 iPhone 中已保存的设置。CLI 会先验证精确日期、配置、架构、归档、清单、摘要链、最终正文摘要和完成状态，再公开结果。

完全为空的日期也属于成功。请求的数据如果存在缺失、部分完成、失败、取消、不支持或跳过，则会产生 `partial_success` 和非零退出状态；只有明确使用 `--allow-partial` 时例外。

## 规范提取

直连提取使用相同的持久原始传输，但返回所选的来源结构数据，而不是传输封装：

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

在读取 HealthKit 前，指标、类别、来源和详细程度选择就会发送到 iPhone。对象选择器、JSON Pointer、JSONL 和回执的说明见[规范提取](/zh-hans/docs/cli-extract/)。

## 生产导出器生成的文件

直连文件模式会要求 iPhone 运行 Health.md 的生产导出器，然后把生成的文件传输到明确指定的计算机目标位置。

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

目标位置必须已存在、使用绝对路径，且路径解析过程中不能经过符号链接。直连模式绝不会猜测目标位置，也不会使用 Mac 应用的书签。`--output` 用于原始或提取输出；`--destination` 用于生成文件。

默认情况下，请求会保留已保存的格式、Health 子文件夹、文件名、模板、写入模式、每日笔记注入和“仅每日笔记”设置，并为本次作业停用周期汇总和仅摘要模式。可重复的 `--metric` 或 `--category` 选项与 `--detail` 只会替换本次作业的指标和详细程度范围。`--use-iphone-settings` 会复用所有已保存设置，不能与这些选择器组合使用。

iPhone 可以暂存 JSON、CSV、Markdown、ZIP、数据字典、周期汇总、单条记录、每日笔记和提供方辅助文件。CLI 会先验证每个相对路径、字节数、摘要、文件清单、目标身份和请求指纹，再提交文件。它会拒绝路径遍历、符号链接祖先、根目录变更、路径冲突和摘要变化。覆盖操作采用原子写入；追加和 Markdown 合并使用持久计划，重放时不会重复内容。

macOS 和 Linux 支持生成文件目标位置。协议 v1 会在 Windows 上拒绝此模式；Windows 直连用户仍可使用原始导出和提取。

## 前台与后台行为

配对和启动新作业时，iPhone 应用必须位于前台。Direct CLI 访问不会把 iOS 变成无人值守的导出服务器，也无法按需唤醒应用。

如果导出已建立连接后应用进入后台，Health.md 会申请有限的 iOS 后台执行时间。导出可能在这段时间内完成；如果 iOS 终止后台执行，连接会关闭，持久作业则会暂停。请重新打开 Health.md，并恢复同一作业。

执行直连作业时，iPhone 会显示全局活动横幅，其中包含采集和传输阶段、已完成天数、字节进度，以及暂停或完成状态，但不会显示健康数值。

## 持久恢复与取消

直连作业会在创建七天后到期。超时、Ctrl-C、进程终止、断开连接和后台时间耗尽都不会取消作业。

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

恢复作业会保留原始日期、设置、目标位置、请求指纹、设备和分区提交边界。恢复文件作业时，不能改用其他目标位置。

取消会记录持久请求，但只有在 iPhone 确认后才成为终止状态。如果 iPhone 不可用，状态会保持为 `cancellation_pending`。请重新打开同一台 iPhone，再次执行取消。

## 安全模型

- 配对使用临时 Curve25519 密钥协商，以及与六位配对码绑定的握手记录证明。
- 重连时会验证随机保存的密钥和两端安装身份。
- 每次连接都会派生新的密钥和 nonce。
- 消息和二进制帧使用 ChaCha20-Poly1305，并检查单调递增的序列号。
- 分区使用 SHA-256 清单和链式摘要边界。
- iPhone 端信任信息存储在钥匙串中。
- 可移植客户端使用钥匙串、Secret Service 或 Windows Credential Manager 存储信任信息，绝不会回退到明文。
- 暂存区和恢复日志位于应用私有存储中，并在平台支持时排除备份。

无论使用本地网络还是 Tailscale，手动 IP 传输始终经过加密。Tailscale 也会保护网络路径，但不能替代 Health.md 自身的应用身份验证。

## 常见错误

| 错误 | 处理方法 |
|---|---|
| `direct_not_paired` | 将此 CLI 安装与 iPhone 配对。 |
| `direct_device_selection_required` | 通过 `--device` 指定目标可信设备。 |
| `direct_trust_invalid` | 保留诊断信息。只有无法恢复时才重置信任。 |
| `direct_iphone_unavailable` | 检查应用前台状态、访问开关、地址、端口、权限，以及 LAN 或 Tailscale 的可达性。 |
| `direct_export_paused` | 检查作业，重新打开 iPhone，再恢复作业。 |
| `direct_cancellation_pending` | 重新打开已配对的 iPhone，再次执行取消。 |
| `transport_unsupported` | 在可移植客户端中使用手动 IP 或 Tailscale。 |
| `backend_unsupported` | 查询、证据、doctor、指标或 MCP 请使用 Mac 应用后端。 |
| `invalid_direct_raw_response` | 不要使用输出，并保留验证诊断信息。 |
| `invalid_direct_file_receipt` | 不要手动修复文件。请检查并恢复作业。 |
| `job_expired` | 七天的状态有效期已结束。开始新作业前先确认。 |

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/cli/"><span>概览</span>Health.md CLI：安装内置辅助程序并选择正确的后端。</a>
  <a href="/zh-hans/docs/cli-extract/"><span>数据</span>规范提取：选择并输出与来源结构一致的 Health.md 数据。</a>
  <a href="/zh-hans/docs/cli-jobs/"><span>可靠性</span>持久作业与自动化：恢复、取消、部分结果和脚本。</a>
  <a href="/zh-hans/docs/reference/connected-mac-iphone-protocol/"><span>协议</span>Mac–iPhone 连接参考：能力、有界传输和结果状态。</a>
</div>
