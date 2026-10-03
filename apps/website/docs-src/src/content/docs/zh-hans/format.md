---
title: "格式自定义"
description: "在不更改采集内容的情况下控制输出格式。选择文件格式及日期、时间和单位规则，自定义 YAML frontmatter，并选择 Markdown 模板。"
---

## 输出格式
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>默认格式。每天一个文件。包含可选的 YAML frontmatter，以及按类别划分的带标题章节。</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>使用结构化 frontmatter 的 Markdown，针对 Obsidian 的 <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> 插件进行了优化。数值属性保持数值类型，日期保持日期类型。</p></div>
<div class="option"><strong>JSON</strong><p>每天一个 JSON 文件。启用“无损健康记录”后，Apple schema-v8 每日摘要可嵌入权威的 <code>healthmd.healthkit_records</code> v1 归档。</p></div>
<div class="option"><strong>CSV</strong><p>每天一个 CSV 文件，表头为 <code>Date,Category,Metric,Value,Unit,Timestamp</code>。兼容性摘要行包含五个字段并省略时间戳列；带时间戳的行和规范记录行包含全部六个字段。</p></div>
</div>

<div class="callout">
<strong>需要精确规范？</strong>
<p style="margin-top:6px;">请参阅基于生产实现的<a href="/zh-hans/docs/reference/export-formats/">格式参考</a>、<a href="/zh-hans/docs/reference/generated/core/csv-row-contracts/">CSV 行规范</a>和完整的可下载示例文件。</p>
</div>

## 日期和时间
<p>选择日期格式（例如 <code>YYYY-MM-DD</code>、<code>MMM d, yyyy</code>）和时间格式（12 小时制、24 小时制）。更改设置时，屏幕底部的预览区域会实时更新。</p>

## 单位制
<p>在<em>公制</em>与<em>英制</em>之间切换。此设置会影响距离（m/km 与 ft/mi）、体重（kg 与 lb）、温度（°C 与 °F）以及少数其他指标。HealthKit 始终以规范单位存储数据；单位转换在导出时进行。</p>

## Frontmatter 字段
<p>轻点<em>Frontmatter 字段</em>可打开专用编辑器：</p>
<ul>
<li>单独切换内置字段（date、weekday、totalSteps 等）</li>
<li>重命名字段——适用于 Obsidian 配置需要不同键名的情况</li>
<li>添加具有固定值的自定义字段（例如 <code>type: health</code>）</li>
<li>添加在导出时解析的占位符字段（例如 <code>weather: {weather}</code>）</li>
</ul>

## Markdown 模板
<p>轻点 <em>Markdown 模板</em>可打开模板编辑器，其中包含多种内置样式（紧凑、章节、详细）以及完全自定义模式。预览区域会显示基于今日数据生成的结果。</p>

## 预览
<p>格式界面底部的实时预览区域会使用当前设置呈现今日数据。这是最快的调整方式——更改一个开关、查看预览，然后重复操作。</p>

## 数据详细程度与配置文件

摘要会生成精简的每日投影。详细时间序列会在指标支持时为 Apple 和 Android 添加所选样本与区间。无损健康记录会添加规范 HealthKit 归档，仅限 Apple，并非 Android 兼容层。

详细程度会随[导出配置文件](/zh-hans/docs/export-profiles/)一同冻结。在配置文件生效时修改它，只会更改该配置文件。

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/export-profiles/"><span>配置文件</span>为每个工作流保存详细程度和格式。</a>
  <a href="/zh-hans/docs/metrics/"><span>内容</span>健康指标——先选择要导出的数据。</a>
  <a href="/zh-hans/docs/individual-tracking/"><span>精细追踪</span>单条记录追踪——完全不同的输出方式（每条记录一个文件）。</a>
  <a href="/zh-hans/docs/daily-notes/"><span>Obsidian</span>每日笔记注入——使用相同的 frontmatter 字段。</a>
  <a href="/zh-hans/docs/reference/export-formats/"><span>规范</span>导出格式——JSON、CSV、Markdown 和 Bases 的精确行为。</a>
</div>
