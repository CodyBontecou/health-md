---
title: "导出"
description: "“导出”标签页是主要操作界面。它会显示 HealthKit 和知识库是否已连接，供您选择目标位置，并按所选日期范围执行一次性导出。"
---

<p>“导出”标签页将操作分为三个简单步骤：确认准备状态、选择目标位置，然后选择日期范围并预览或导出。</p>

## 查看状态标记
<div class="options">
<div class="option"><strong>健康标记</strong><p>绿点 = HealthKit 已授权。红点 = 未授权。轻点可重新打开 iOS 权限窗口（每次安装后仅首次有效；此后 iOS 不会执行任何操作，您需要前往“设置”→“隐私与安全性”→“健康”中修复）。</p></div>
<div class="option"><strong>知识库标记</strong><p>绿点 = 已选择知识库文件夹。轻点可重新选择或更改知识库。标签会显示文件夹名称。</p></div>
</div>
<p>在 HealthKit、输出格式和所选目标位置全部准备就绪之前，<em>导出</em>操作将保持禁用状态。这可避免最常见的失败情况：未选择目标位置便尝试导出。</p>

## 选择导出目标
<p>“导出目标”卡片决定数据的去向：</p>

<div class="options">
<div class="option"><strong>iPhone 本地文件夹</strong><p>直接写入您在此设备上选择的文件夹或 Obsidian 知识库。</p></div>
<div class="option"><strong>已连接的 Mac</strong><p>将采集的每日数据和完整的设置快照发送到附近的 Mac 应用。iPhone 读取 HealthKit；Mac 按所选格式渲染数据并写入文件。</p></div>
<div class="option"><strong>API 端点</strong><p>直接从 iPhone 向用户配置的 HTTP(S) 端点 POST JSON 封装。<a href="/zh-hans/docs/api-endpoint/">参阅 API 端点</a>。</p></div>
</div>

## 选择日期范围
<p>日期预设涵盖常见使用场景：</p>

<div class="options">
<div class="option"><strong>今天</strong><p>导出当天的数据，适合测试输出格式。</p></div>
<div class="option"><strong>昨天</strong><p>最稳妥的每日导出选项，因为当天数据已完整。</p></div>
<div class="option"><strong>所有时间</strong><p>从 Health.md 能找到的最早 HealthKit 数据开始回填。</p></div>
<div class="option"><strong>自定义</strong><p>选择开始和结束日期，导出指定范围。</p></div>
</div>

## 预览或导出
<div class="options">
<div class="option"><strong>预览</strong><p>在写入任何内容之前，显示将生成的文件及其内容。</p></div>
<div class="option"><strong>导出</strong><p>执行导出，在主界面显示进度，并将结果记录到历史中。</p></div>
</div>

## 选择数据详细程度

<div class="options">
<div class="option"><strong>摘要</strong><p>精简的每日总计与汇总，适合阅读、笔记和仪表盘。</p></div>
<div class="option"><strong>详细时间序列</strong><p>所选带时间戳的样本和区间。只要指标能提供相应细节，Apple 和 Android 均支持此级别。</p></div>
<div class="option"><strong>无损健康记录</strong><p>规范的 HealthKit 来源记录归档。此级别仅限 Apple；Android 不会把 Health Connect 记录转换为 HealthKit 归档。</p></div>
</div>

## “导出”实际执行的操作
<ol>
<li>针对范围内的每一天采集所选摘要；“详细时间序列”会增加兼容样本，“无损健康记录”还会增加规范来源记录和查询诊断信息。</li>
<li>应用所选格式（Markdown、Obsidian Bases、JSON 或 CSV）和模板。</li>
<li>每天向 <code>{vault}/{subfolder}/</code> 写入一个文件、通过已连接的 Mac 工作流传输文件，或向 API 端点 POST 带版本的 JSON 封装。</li>
<li>如果启用了<em>单条记录追踪</em>，则为文件型目标从规范归档中派生所选的单条 Markdown 文件。</li>
<li>如果启用了<em>每日笔记注入</em>，则将所选摘要字段合并到每日笔记中。</li>
</ol>

<p>JSON 和 CSV 可以保留规范记录。Markdown 和 Obsidian Bases 保持易读，并提供精简的采集诊断信息，而不会嵌入归档。有关确切的数据结构和省略规则，请参阅<a href="/zh-hans/docs/reference/">完整导出参考</a>。</p>

## 停止、取消和重试

停止或取消只会结束当前尝试。已完成的文件和日期会保留，未解决的日期仍可重试。取消某次计划运行不会禁用其重复计划。

## 配置文件与可信历史

已保存的配置文件会冻结本次运行的设置和目标。配置文件感知的计划运行和自动化会在历史记录中保留运行时配置文件；历史还会保存实际目标的隐私安全标签。手动导出记录可能省略配置文件名称。之后更改名称或目标不会改写现有历史。缺失的配置文件引用会以安全方式失败。请参阅[导出配置文件](/zh-hans/docs/export-profiles/)。

## 标签栏

<p>屏幕底部的四个标签页——导出、计划、同步和设置——涵盖了应用的全部功能。其他所有功能均位于“设置”内一到两层的位置。</p>

<div class="callout">
<strong>解锁规则。</strong>
<p style="margin-top:6px;">在 Apple 平台上，免费额度由 10 次手动或计划导出操作共用。Full Access 会移除此上限，并解锁 Mac 目标工作流和“快捷指令”。Android 则提供 10 次免费手动操作，计划功能需要一次性终身购买。有关 Apple 购买详情，请参阅<a href="/zh-hans/docs/paywall/">付费墙页面</a>。</p>
</div>

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/export-profiles/"><span>配置文件</span>保存独立的目标、设置、计划和自动化 ID。</a>
  <a href="/zh-hans/docs/scheduling/"><span>日常使用</span>计划——自动执行导出，无需再手动轻点“导出”。</a>
  <a href="/zh-hans/docs/api-endpoint/"><span>集成</span>API 端点——将所选 JSON 直接发送到您自己的服务。</a>
  <a href="/zh-hans/docs/format/"><span>自定义</span>格式自定义——更改每个文件的呈现方式。</a>
  <a href="/zh-hans/docs/shortcuts/"><span>高级功能</span>快捷指令——通过 Siri、自动化或其他应用触发导出。</a>
  <a href="/zh-hans/docs/reference/"><span>参考</span>导出参考——数据结构、规范记录、诊断信息和生成示例。</a>
</div>
