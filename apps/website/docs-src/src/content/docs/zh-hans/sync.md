---
title: "Mac 同步"
description: "将 macOS 配套应用用作本地目标位置。iPhone 采集 HealthKit 数据和设置，然后由 Mac 渲染并写入请求的文件。"
---

## 功能介绍
<p>Mac 同步让 Mac 无需读取 HealthKit，即可生成导出文件。iPhone 仍是 Apple Health 数据的可信来源：它会采集所选的每日数据和精确设置快照，然后将该作业传输到 Mac。Mac 使用共享导出器规划路径、渲染所选格式，并将生成的文件写入您选择的目标文件夹。</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Mac 同步导出流程">
    <span><strong>iPhone</strong>采集 HealthKit 数据并生成有效设置的快照。</span>
    <span><strong>本地网络</strong>将带版本的作业传输到附近的 Mac 应用。</span>
    <span><strong>Mac</strong>渲染所选格式并将文件写入所选文件夹。</span>
    <span><strong>知识库</strong>Obsidian、iCloud Drive 或任意本地文件夹接收最终导出。</span>
  </div>
</div>

## 如何启用
<ol>
<li>安装并打开 macOS 应用。</li>
<li>在 Mac 上选择目标文件夹，授予 Health.md 写入权限。</li>
<li>在 iPhone 上打开“同步”标签页，并启用 Mac 连接。</li>
<li>返回 iPhone 的“导出”标签页，选择<em>已连接的 Mac</em>，配置导出，然后轻点“导出”。</li>
</ol>

## 传输内容
<ul>
<li>描述日期范围和有效设置的带版本导出请求</li>
<li>iPhone 采集 HealthKit 数据时的进度和功能消息</li>
<li>经过校验和验证的限定大小帧，其中包含采集的每日数据，以及文件写入作业所需的精确设置快照</li>
<li>结构化的完成、部分完成、失败、拒绝或不可用结果</li>
</ul>
<p>无需账户或远程健康数据云服务。附近同步使用加密的 Multipeer Connectivity；手动 IP/Tailscale 使用经过配对加密的 Network.framework 传输。两台设备必须能够互相连接，且 iPhone 始终是 HealthKit 读取端。</p>

## 适用场景
<div class="options">
<div class="option"><strong>仅限桌面的知识库</strong><p>如果 Obsidian 知识库只存放在 Mac 上，这是将 iPhone HealthKit 数据导出为 Mac 文件的直接方式。</p></div>
<div class="option"><strong>大规模历史数据回填</strong><p>由 iPhone 负责读取 HealthKit 和配置导出，同时将最终文件保存在桌面磁盘上。</p></div>
<div class="option"><strong>本地归档工作流</strong><p>直接写入在 macOS 上备份、版本管理或建立索引的文件夹。</p></div>
</div>

<div class="callout">
<strong>需要本地网络。</strong>
<p style="margin-top:6px;">两台设备必须在附近，并获准使用本地网络。仅使用蜂窝网络的 iPhone 无法发现 Mac 目标位置。如果就绪状态显示“需在 Mac 上处理”，请重新打开 Mac 应用并重新选择目标文件夹。</p>
</div>

## Mac 同步与 Direct CLI 访问相互独立

Mac 同步会将 iPhone 与 Health.md Mac 应用配对，用于目标位置导出和加密的智能体上下文。Direct CLI 访问则通过独立的信任域，将 iPhone 与命令行安装配对。直连模式无需 Mac 应用即可导出原始数据或生成文件，但无法使用 Mac 上的加密查询索引或 MCP。

启用这一独立的 iPhone 设置前，请参阅[直接连接 iPhone 的 CLI](/zh-hans/docs/cli-direct/)。

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/macos/"><span>桌面端</span>macOS 应用 — 在 Mac 上导出、计划和查看历史记录。</a>
  <a href="/zh-hans/docs/scheduling/"><span>工作流</span>计划 — 自动执行定期导出。</a>
  <a href="/zh-hans/docs/cli-direct/"><span>独立信任</span>直接连接 iPhone 的 CLI — 无需通过 Mac 应用路由作业，即可配对 CLI。</a>
  <a href="/zh-hans/docs/reference/connected-mac-iphone-protocol/"><span>协议</span>Mac–iPhone 连接参考 — 功能、请求、有界传输和结果。</a>
</div>
