---
title: "本地智能体与健康上下文"
description: "通过限定范围的 CLI 命令或 iPhone 直连 MCP 将本地智能体接入 Health.md，并保留证据、覆盖范围和缺失状态。"
---

Health.md 为本地编码和自动化智能体提供两种处理 Apple Health 数据的方式：

- 使用 `healthmd` CLI 执行明确的终端命令和规范提取；
- 使用 `healthmd mcp serve` 及其 MCP App 调用类型化工具、原生可视化和经过批准的生成文件导出。

可移植 MCP 服务器直接与前台运行的 iPhone 通信，不依赖 Health.md Mac 版。CLI 可以通过同一直连通道执行原始或规范导出，也可以通过 Mac 应用的环回 API 使用 Mac 索引工作流。HealthKit 始终由 iPhone 读取，`healthmd.health_data` v7 仍是公开来源契约。

```text
local agent -> healthmd mcp serve -> authenticated encrypted port 17647 -> foreground iPhone
local agent -> healthmd CLI -> direct iPhone or optional Mac loopback workflow
```

## 智能体可以做什么

- 在不读取健康数值的情况下检查直连配对和前台 iPhone 的就绪状态；
- 列出规范指标 ID 和类别；
- 从 iPhone 获取精确的指标、来源、日期和详细程度范围；
- 提取规范每日文档或来源记录；
- 查询带证据和覆盖范围的类型化指标序列；
- 构建稳定的睡眠时段和固定睡眠窗口；
- 将锻炼与前后睡眠对齐；
- 列出锻炼并检查覆盖范围；
- 使用明确的聚合方式比较精确周期；
- 创建仅陈述事实的训练证据包；
- 通过有界请求遍历逻辑上无界的语料库；
- 在 MCP Apps 中呈现指标、睡眠、锻炼、比较、覆盖范围和证据视图；
- 将经过批准的生成文件导出到明确指定且已存在的桌面目标位置；
- 检查、恢复或取消持久导出作业。

Health.md 不会诊断、建议治疗、推断因果关系，也不会将结果标为健康、有害、更好或更差。

## 设置本地辅助程序

<div class="availability preview">
<strong>预览版 · 可移植直连设置</strong>
<p>以下步骤使用尚未发布的跨平台软件包。如需使用目前已经可用的工作流，请配置已签名的 Mac <code>healthmd-mcp</code> 辅助程序，具体方法见<a href="/zh-hans/docs/configuration/">配置智能体</a>。</p>
</div>

1. 安装跨平台 Health.md CLI 软件包。
2. 运行 `healthmd setup codex`；它会配置 Codex，并在尚未信任 iPhone 时打开配对流程。
3. 在 iPhone 上的 Health.md 中，前往 Direct CLI 访问完成配对，并让应用保持在前台。
4. 对于 Claude 或手动主机设置，请按照 [Health.md MCP 服务器与 App](/zh-hans/docs/mcp/)中的说明，配置 `healthmd` 的绝对路径，并传入参数 `mcp serve`。
5. 如果设置程序报告配置已更改，请重启主机，然后调用 `healthmd_doctor`。

对于 Mac 用户，Health.md Mac 应用仍可用作可选的安装和技能分发方式，但不是可移植 MCP 的依赖项。

应用中的技能安装程序会在您批准的目录中创建 `healthmd-cli/SKILL.md`，且只替换 Health.md 自己的技能文件夹。该技能介绍有界命令、结构化结果处理、隐私规则，以及结果未知后的安全恢复方法。

如果希望智能体创建符号链接，请使用 Mac 应用中的设置提示。Health.md 本身不会在未提示的情况下修改 shell 启动文件或 `/usr/local/bin`。

## 先检查就绪状态

可移植 MCP 客户端应先调用 `healthmd_doctor`。它会在不读取健康数值的情况下检查本地直连信任和已连接的前台 iPhone，并返回可执行后续操作且不含健康数据的错误。之后，每次类型化 MCP 查询都会向该 iPhone 发出明确的全新请求：只采集请求范围，在设备上执行类型化查询，并返回有界页面。

使用 Mac 环回后端的 CLI 用户仍可运行 `healthmd doctor`，查看 `healthmd.cli_doctor` v1 就绪状态、加密上下文覆盖范围和后续操作。

## 每个请求都携带完整范围

Health.md 不使用已保存的访问配置、调用方注册、授权记录或 CLI 凭据。每个请求都必须提供所需的完整数据范围：

- 指标 ID 或类别；
- Apple Health 及可选提供方的来源选择器；
- 精确日期或全部可用日期；
- 摘要或无损详情；
- 查询操作；
- 有界分页控制。

全新获取会根据当前目录验证范围，将其与持久作业一并保存，并在不更改已保存导出偏好设置的情况下应用到 iPhone。

没有明确获取选择的请求会被拒绝，而不会继承用户的常规导出设置。

## 授权边界

可移植 MCP 使用已配对的直连协议：原生凭据存储、双方握手记录身份验证、加密数据包、重放保护，以及从前台 iPhone 到计算机明确地址的连接。可选的 Mac 查询 API 则只监听 IPv4 和 IPv6 环回地址，并验证对等方确为环回连接。

使用可选 Mac 环回模式时，只要 Health.md 已打开，任何能够访问端口 `17645` 的本地进程都能发出相同的查询请求。请将本机访问权限视为查询权限：

- 不要将端口绑定或代理到 LAN 接口；
- 不要通过隧道转发到其他计算机；
- 不要在前面部署 HTTP 反向代理；
- 不要为 MCP 配置非环回 URL；
- 检查哪些本地智能体可以执行辅助程序。

为保持兼容，原有的配置和活动路由会返回 `410 removed_endpoint`。

## 规范数据与派生视图

智能体需要与来源结构一致的数据，或大型且经过验证的原始或规范正文时，请使用 `healthmd extract`：

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

需要派生视图或主机内可视化时，请使用查询命令或 MCP 工具：

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

两者有意区分：

| 接口 | 契约角色 |
|---|---|
| `healthmd.health_data` v7 | 公开的每日来源文档 |
| `healthmd.healthkit_records` v1 | 无损每日文档中的规范来源记录归档 |
| `healthmd.extract_receipt` | 提取范围和完成状态元数据 |
| `healthmd.query_context_day` v1 | 可丢弃的加密索引记录 |
| `healthmd.query_response` v1 | 分页的类型化派生结果 |
| `healthmd.evidence_packet` v1 | 与来源证据关联的事实证据包 |
| 作业和遍历回执 | 传输、持久性和完成状态元数据 |

投影或类型化结果绝不会冒充完整的每日来源文档。

## 获取全新数据

高级查询默认获取全新数据：

```bash
healthmd query --category Sleep --last 14
```

Health.md 会创建专用的加密上下文请求。该请求不会写入导出文件，也不会消耗文件导出额度。iPhone 读取明确范围，构建确定性的精简归属日，并发送有界且可恢复的分区。Mac 会先提交每个加密日，再发送确认。

全新获取的完成状态会针对本次刷新开始后替换的 Blob，检查请求的每项指标、来源或提供方以及每个归属日。较早的缓存值或其他提供方的数据无法掩盖获取失败。

仅包含提供方的请求可以跳过 HealthKit。提供方历史记录会使用提供方原生游标遍历，而不会施加固定的结果总量上限。

## Mac 加密上下文

Mac 会为每个归属日分别存储一代独立加密的数据。随机 256 位密钥以仅限本设备、解锁时可用的项目形式存储在钥匙串中。

- 每日 Blob 和清单使用 AES-256-GCM；
- 文件名是随机 UUID，不包含日期或指标名称；
- 归属日期和索引条目均经过加密；
- 文件权限仅限所有者，并排除在备份之外；
- 提交时先写入新的不可变代，再替换加密清单；
- 如果密钥缺失、身份验证失败、日期格式错误或清单明显不匹配，读取会以失败方式安全关闭。

存储没有预设的指标总数、天数、历史记录或结果上限。命令仍保持有界，因为它们每次只解密一天并对结果分页。

此索引可以随时丢弃。规范导出始终是权威来源。

## 保留与删除

Health.md 不会按照隐式保留计划删除查询上下文。Mac 上的“设置”会显示已存储的归属日数量和日期范围。

可使用：

- **删除较早的上下文**：删除严格早于所选边界的归属日期；
- **删除所有加密上下文**：删除所有加密代和专用钥匙串密钥。

即使密钥或密文损坏，仍可执行完整删除。删除密钥会对任何未删除的残留密文实现加密擦除。

删除查询上下文不会删除导出文件、已连接提供方的凭据或 Apple Health 数据。

## 类型化值与缺失状态

查询值带有类型标签。结果可以包含数量和规范单位、时长、有符号计数、字符串、类别、布尔值、UTC 时间戳、日历日期、嵌套数组，或未来新增的未知类型化载荷。

缺失数据会明确保留：

- `complete_empty` 表示该范围内没有匹配的观测值；
- `partial` 表示只完成了请求范围的一部分；
- `failed`、`unsupported`、`skipped` 和 `cancelled` 保留各自含义；
- `not_requested`、`legacy_unavailable`、`redacted` 和 `not_synchronized` 彼此不同。

Health.md 绝不会将缺失值转换为数值零。真实的零会编码为可用的类型化值。

## 证据与中性表述

结果会将事实关联到来源证据，例如：

- 每日摘要键；
- 规范 HealthKit UUID；
- 外部身份；
- 查询清单结果；
- 完整性警告；
- 部分失败。

解析证据时，会同时检查证据 ID、定位器、来源架构、来源版本和来源摘要。

周期比较的方向只会是 `increased`、`decreased`、`unchanged` 或 `not_comparable`。训练对齐报告时间戳和间隔，而不声称存在因果效应。证据包报告已存观测值和覆盖范围，而不下医学结论。

智能体应在回答中保留这些限制：明确说明数据缺失情况，不把相关性描述成因果关系，并将医疗问题交由合格的临床专业人员处理。

## 有界分页与完整逻辑访问

查询页面使用 `max_items`、`max_bytes` 和不透明的 `next_cursor`。已存天数、锻炼、指标或结果项目总量没有契约层面的上限。

游标受完整性保护，并与语义查询和加密语料库版本绑定。Health.md 会拒绝：

- 被修改的游标；
- 用于其他查询的游标；
- 语料库更改前签发的游标；
- 自动遍历期间重复出现的游标。

使用 `--all-pages` 或 MCP `all_pages: true` 执行有界自动遍历。如果单次调用达到总安全上限，请缩小范围或手动分页。

## 智能体结果报告清单

总结结果时，应报告：

- 使用的命令或工具；
- 请求的精确日期、指标、来源和详细程度；
- 全新、缓存或复用已有覆盖范围的模式；
- 分别报告请求范围状态和语料库状态；
- 分页或遍历是否完成；
- 所有引用数值的单位和来源证据；
- 缺失区间、限制和不相关跳过项；
- 作业暂停或可恢复时的作业 ID。

除非用户明确要求这些值并了解披露内容，否则不要包含原始记录、路线、临床文本、药物详情、情绪条目或附件。

## 选择集成方式

<div class="related">
  <a href="/zh-hans/docs/agent-queries/"><span>CLI 手册</span>类型化智能体查询：指标、睡眠时段、训练对齐、锻炼、覆盖范围、比较和证据。</a>
  <a href="/zh-hans/docs/mcp/"><span>工具协议</span>Codex 和 Claude 设置、17 个可移植工具、MCP App 图表、导出、分页和沙盒边界。</a>
  <a href="/zh-hans/docs/agent-api/"><span>底层接口</span>环回查询 API：路由、直接请求 JSON、游标和持久获取作业。</a>
  <a href="/zh-hans/docs/cli-extract/"><span>来源对象</span>规范提取：所选 schema-v7 文档、记录、投影和回执。</a>
  <a href="/zh-hans/docs/reference/evidence-packets/"><span>契约</span>精简查询与证据包：类型化值、覆盖范围、操作和确定性 ID。</a>
</div>
