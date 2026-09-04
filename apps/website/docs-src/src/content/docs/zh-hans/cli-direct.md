---
title: "手机直连 CLI"
description: "通过手动 IP 或 Tailscale 将 healthmd 与 iPhone 或 Android 手机配对，无需运行 Health.md Mac 版即可导出。"
---

直连后端会将 `healthmd` 连接到 iPhone 或 Android 上已打开的 Health.md 应用，命令无需经过 Health.md Mac 版。手机会读取自身平台的健康数据存储——iPhone 上是 HealthKit，Android 上是 Health Connect——将结果暂存到受保护的存储空间，再把经过验证的分区传输给 CLI。

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>预览版 · 可移植直连 CLI</strong>
<p>macOS 上已可使用内置的 Swift 直连后端，可与 iPhone 配对。使用应用协议 v2 的 Android 属于已公开打包的跨平台 Rust 预览版。当前 iOS 和 Android 版本在新的可移植配对中使用相同的选择器 3 和通用二维码。两个手机平台的基本实体连接均已确认，但使用准确构建版本的完整发布矩阵仍未完成，因此这仍是明确未经资格验证的工作流。</p>
</div>

## 0.1.0-alpha.6 移动端兼容性

此独立表格是明确未经资格验证的预览版所采用的兼容性矩阵。iPhone 和 Android 的基本实体连接均已确认；目前尚无完成并保留完整资格验证矩阵的公开 CLI/移动端组合。

| 移动端来源 | 协议 | 准确 tag-SHA 对应版本／未经验证的兼容性下限 | 可移植 Rust 操作 | 公开状态 |
|---|---|---|---|---|
| 支持导出的 iPhone | 当前选择器 3（旧版 1）/ 应用 v1 | iOS 3.3.0（构建 202609032317）/ iOS 3.0.3 | 状态、原始数据、提取、文件、恢复、取消 | 连接已确认；完整资格验证待完成 |
| 支持查询的 iPhone | 当前选择器 3（旧版 1）/ 应用 v1 + 查询 v3 | iOS 3.3.0（构建 202609032317）/ iOS 3.0.3 | V1 加 19 工具本地 MCP／查询 | 连接已确认；完整资格验证待完成 |
| Android | 当前选择器 3（旧版 2）/ 应用 v2 | Android 1.8.2 (`versionCode 31`) / Android 1.5.4 (`versionCode 25`) | 状态、提供方原生数据、文件、恢复、取消 | 连接已确认；完整资格验证待完成 |
| Android 类型化 MCP 查询 | 不适用 | 尚未实现 | 查询工具要求 iPhone v3 | 不支持 |

## 直连模式支持的功能

- 通过共享选择器 3 完成一次性配对，并与 iPhone（应用协议 v1）或 Android（应用协议 v2）来源进行可信重连；
- 在本地查看可信设备并解除配对；
- 实时检查手机就绪状态；
- 严格的原始导出——iPhone 上为 schema-v8 `healthmd.health_data`，Android 上为提供方原生的 Health Connect 快照；
- 按选择范围进行规范提取（仅限 iPhone）；
- 在两种手机平台上导出生产生成的文件；
- 查看和恢复本地持久作业；
- 明确取消作业；
- 与 CLI 共用可执行文件的 `healthmd mcp serve` stdio 服务器，提供直连类型化查询、指标目录、证据、MCP Apps UI 和 PNG 后备图表（仅限 iPhone）。

`healthmd` 命令的直连后端不会模拟 Mac 应用的加密上下文 HTTP 路由。因此，面向 Mac 的 `doctor`、查询、证据和刷新子命令仍会返回 `backend_unsupported`，不会自行切换后端。需要对 iPhone 中的全新数据进行类型化分析时，请使用 `healthmd mcp serve`；也可以运行 `healthmd setup codex`，自动配置 Codex 并完成配对。`healthmd mcp schema [TOOL]` 会在本地输出准确的嵌套 MCP 输入架构和示例。睡眠问题应直接使用 `healthmd_sleep_sessions`，不要把规范 `extract` 输出当作类型化查询 API。

## 要求

- 支持直连的 `healthmd` 二进制文件，以及与之匹配的 Health.md 版本：iPhone（应用协议 v1）或 Android（应用协议 v2）。Android 配对需要可移植 Rust 客户端；内置 macOS 辅助程序只能与 iPhone 配对。
- 配对和启动新命令时，Health.md 必须在手机前台保持打开。
- 在 iPhone 上启用**设置 > Mac 同步 > Direct CLI 访问**，或在 Android 上启用**设置 → Direct CLI**。
- 已授予平台健康权限（HealthKit 或 Health Connect），受保护数据可用，本地网络权限已授予，并有可用的导出额度。
- 使用手动 IP 时，计算机地址必须可达，并开放 TCP 端口 `17647`。也可以使用 Tailscale 地址。
- 使用生成文件模式时，必须提供已存在的绝对目标路径。

CLI 充当监听器。手机会连接到 Direct CLI 访问中填写的计算机地址。

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

可移植 Rust 客户端会显示一个 iOS/Android 通用二维码，并把共享的 20 位代码、候选计算机地址、监听端口以及供旧版 iOS 使用的六位备用代码写入 stderr。内置 macOS 辅助程序仍只显示旧版六位 iPhone 代码。stdout 始终保留给最终 JSON 结果。

在 iPhone 上：

1. 打开 **Health.md > 设置 > Mac 同步 > Direct CLI 访问**并启用访问。
2. 轻点**扫描配对二维码**并扫描通用二维码；完成这次明确的应用内扫描后，配对会立即开始。
3. 无法扫描时，选择**手动 IP**并输入地址、端口和共享的 20 位代码。旧版 CLI 仍可使用六位代码。
4. 保持应用打开，直到双方都报告成功。

## 配对 Android 手机

1. 在 Android 手机上打开 **Health.md > 设置 → Direct CLI**。
2. 轻点**扫描配对二维码**并扫描通用二维码；完成这次明确的应用内扫描后，配对会立即开始。
3. 没有摄像头或权限时，可手动输入地址、端口和同一个共享 20 位代码。
4. 保持应用打开；在活动的直连会话期间，Android 会运行一个由用户启动且可见的数据同步前台服务。

一次性代码绝不会通过网络发送或持久保存。配对后，Keychain 或 Android Keystore 会保护重连信任。

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

这些命令只读取或修改本地信任，不会联系手机。在 iPhone 上，可使用**忘记已配对的 CLI**删除另一端的配对；在 Android 上，请在**设置 → Direct CLI**中移除配对。

如果信任了多台手机，请明确选择目标安装：

```bash
healthmd --backend direct --device DEVICE_UUID status
```

仅当本地信任已损坏或属于被替换的安装时，才使用 `healthmd direct reset-trust --confirm`。该命令会删除所有本地直连配对。重新配对前，也请在手机上忘记这些配对。

## 检查实时就绪状态

```bash
healthmd --backend direct --transport manual-ip status
```

直连状态响应只报告连接和安全状态，不包含健康数值。可移植客户端会在 `source` 下报告数据来源，其 `platform` 为 `ios` 或 `android`；内置辅助程序则提供下方的 `iphone` 字段。开始作业前，请检查以下字段（以 iPhone 来源为例）：

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

Android 来源会报告 `platform: "android"`，并提供 `app_active`、`protected_data_available`、`export_in_progress` 及其可用的原始产品，以替代上述 iPhone 触发标志。

## 严格原始导出（iPhone）

请选择一种日期范围选择器：

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

省略 `--output` 时，经过验证的 JSON 会流式写入 stdout。对于敏感或大型响应，写入输出文件更安全。

iPhone 严格原始导出返回 `healthmd.raw_result` v1，其中包含普通 schema-v8 `healthmd.health_data` 每日数据及其规范来源归档。它会临时请求无损详情，但不会更改 iPhone 中已保存的设置。CLI 会先验证精确日期、配置、架构、归档、清单、摘要链、最终正文摘要和完成状态，再公开结果。

完全为空的日期也属于成功。请求的数据如果存在缺失、部分完成、失败、取消、不支持或跳过，则会产生 `partial_success` 和非零退出状态；只有明确使用 `--allow-partial` 时例外。

## 提供方原生原始导出（Android）

可移植 Rust 客户端默认即使用直连模式，因此 Android 原始导出命令可以省略 `--backend` 标志：

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider` 指定唯一且明确的提供方，默认为 `health_connect`。`--raw-format` 默认为 NDJSON，这是大型快照推荐采用的格式；内存中的 JSON 验证上限为 64 MiB。指标选择支持 `--metric` 和 `--all-metrics`，但不支持规范提取或生成文件选择器——这些仍是 iPhone 功能。

Android 原始快照保持其 Health Connect 提供方原生契约，绝不会转换为 HealthKit 形态的 `healthmd.health_data` 每日数据，相关但不同的统计指标也保持各自独立的身份。

## 规范提取

直连提取使用相同的持久原始传输，但返回所选的来源结构数据，而不是传输封装。这是 iPhone 专属功能：

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

在读取 HealthKit 前，指标、类别、来源和详细程度选择就会发送到 iPhone。对象选择器、JSON Pointer、JSONL 和回执的说明见[规范提取](/zh-hans/docs/cli-extract/)。

手机应用保持前台运行时，可信直连会话可在短暂断开后，通过次数和延迟均有界的尝试自动重连。这不会唤醒后台应用，也不承诺能访问后台应用；如果应用已不在前台，请重新打开 Health.md 后再恢复。

## 生产导出器生成的文件

直连文件模式会要求手机运行 Health.md 的生产导出器，然后把生成的文件传输到明确指定的计算机目标位置。

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

iPhone 协议 v1 和 Android 协议 v2 的生成文件目标都支持所有 CLI 操作系统——macOS、Linux 和 Windows。Android 会将每个生成作业限制在最多 4,096 个文件。

Android 协议 v2 的文件作业从设备上已保存的选择或 `--profile PROFILE_ID` 获取输出设置，并拒绝 CLI 的指标、类别和详细程度选择器。在两个手机平台上，`--profile` 都用于解析固定的输出设置，而必需的 `--destination` 仍明确指定电脑文件夹。
有关稳定 ID 和安全失败，请参阅 [导出配置文件](/zh-hans/docs/export-profiles/).

## 前台与后台行为

配对和启动新作业时，手机应用必须位于前台。Direct CLI 访问不会把手机变成无人值守的导出服务器，也无法按需唤醒应用。

在 iPhone 上，如果导出已建立连接后应用进入后台，Health.md 会申请有限的 iOS 后台执行时间。导出可能在这段时间内完成；如果 iOS 终止后台执行，连接会关闭，持久作业则会暂停。请重新打开 Health.md，并恢复同一作业。

在 Android 上，活动的直连会话会运行一个由用户启动且可见的数据同步前台服务。请在配对和启动新作业时让应用保持前台。

在 iPhone 上，执行直连作业时显示的全局活动横幅包含采集和传输阶段、已完成天数、字节进度，以及暂停或完成状态，但不会显示健康数值。

当手机应用保持在前台时，受信任的直连会话可在短暂断开后自动重连。重试延迟会逐步增加，但设有较短的上限。这不会唤醒后台应用，也不保证能够访问后台应用；如果 Health.md 已不在前台，请在恢复前重新打开它。

120 秒的有限等待窗口会在用户解锁手机并打开 Health.md 时保留同一请求。使用 `--wake-timeout SECONDS` 调整；`0` 可禁用。MCP 使用 `HEALTHMD_WAKE_TIMEOUT`。已发布的 alpha.6 二进制文件仅等待。后续官方构建会通过 Health.md 的纯通知唤醒服务，向已注册的 iPhone 发送一次尽力而为的 APNs 通知；Android 和未注册的 iPhone 仍仅等待。通知可以恢复用户在场状态，但绝不会授权读取 HealthKit，也不会通过 Worker 发送健康范围。

## 持久恢复与取消

直连作业会在创建七天后到期。超时、Ctrl-C、进程终止、断开连接和后台时间耗尽都不会取消作业。

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

恢复作业会保留原始日期、设置、目标位置、请求指纹、设备和分区提交边界。恢复文件作业时，不能改用其他目标位置。

取消会记录持久请求，但只有在已配对的手机确认后才成为终止状态。如果手机不可用，状态会保持为 `cancellation_pending`。请重新打开同一台手机，再次执行取消。

## 安全模型

- 当前可移植配对使用临时密钥协商，以及与一个 iOS/Android 共享的高熵 20 位（约 66 比特）代码绑定的选择器 3 握手记录证明。旧版 Apple 选择器 1 和 Android 选择器 2 流程保持逐字节兼容。
- 二维码交接只允许通过应用内明确启用的扫描器接收，并仅接受规范的私有 LAN/Tailscale 地址；打开外部自定义网址不能授权配对。
- 重连时会验证随机保存的密钥和两端安装身份。
- 每次连接都会派生新的密钥和 nonce。
- 消息和二进制帧使用 ChaCha20-Poly1305，并检查单调递增的序列号。
- 分区使用 SHA-256 清单和链式摘要边界。
- iPhone 端信任信息存储在钥匙串中；Android 的重连信任由 Keystore 保护。
- 可移植客户端使用钥匙串、Secret Service 或 Windows Credential Manager 存储信任信息，绝不会回退到明文。
- 暂存区和恢复日志位于应用私有存储中，并在平台支持时排除备份。

无论使用本地网络还是 Tailscale，手动 IP 传输始终经过加密。Tailscale 也会保护网络路径，但不能替代 Health.md 自身的应用身份验证。

## 常见错误

| 错误 | 处理方法 |
|---|---|
| `direct_not_paired` | 将此 CLI 安装与目标移动数据源配对。 |
| `direct_device_selection_required` | 通过 `--device` 指定目标可信设备。 |
| `direct_trust_invalid` | 保留诊断信息。只有无法恢复时才重置信任。 |
| `direct_iphone_unavailable` | 检查应用前台状态、访问开关、地址、端口、权限，以及 LAN 或 Tailscale 的可达性。 |
| `direct_export_paused` | 检查作业，重新打开已配对的手机，再恢复作业。 |
| `direct_cancellation_pending` | 重新打开已配对的手机，再次执行取消。 |
| `transport_unsupported` | 在可移植客户端中使用手动 IP 或 Tailscale。 |
| `backend_unsupported` | 查询、证据、doctor、指标或 MCP 请使用 Mac 应用后端。 |
| `invalid_direct_raw_response` | 不要使用输出，并保留验证诊断信息。 |
| `invalid_direct_file_receipt` | 不要手动修复文件。请检查并恢复作业。 |
| `job_expired` | 七天的状态有效期已结束。开始新作业前先确认。 |

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/cli/"><span>概览</span>Health.md CLI：安装内置辅助程序并选择正确的后端。</a>
  <a href="/zh-hans/docs/android/"><span>Android</span>Health.md Android 版：Health Connect 来源、文件夹目标位置和设备端自动化。</a>
  <a href="/zh-hans/docs/cli-extract/"><span>数据</span>规范提取：选择并输出与来源结构一致的 Health.md 数据（iPhone）。</a>
  <a href="/zh-hans/docs/cli-jobs/"><span>可靠性</span>持久作业与自动化：恢复、取消、部分结果和脚本。</a>
  <a href="/zh-hans/docs/reference/connected-mac-iphone-protocol/"><span>协议</span>Mac–iPhone 连接参考：能力、有界传输和结果状态。</a>
</div>
