---
title: "健康指标"
description: "从 Health.md 当前的 Apple Health 指标目录中选择。您可以搜索、一次切换整个类别，或深入设置单个指标。"
---

<div class="callout">
<strong>Android 说明。</strong>
<p style="margin-top:6px;">本页介绍 Apple Health 指标选择器和生成的 HealthKit 数据参考。Android 应用提供 106 项 Health Connect 指标；有关 Health Connect 设置和平台特定行为，请参阅 <a href="/zh-hans/docs/android/">Android 指南</a>。</p>
</div>

## 布局
<div class="options">
<div class="option"><strong>计数标题</strong><p>实时显示已启用的指标和类别数量。长按可将确切的选择状态复制到剪贴板。</p></div>
<div class="option"><strong>所有指标已启用</strong><p>用于开启或关闭所有类别的总开关。适合作为起点——先全部开启，再禁用您不需要的指标。</p></div>
<div class="option"><strong>搜索</strong><p>实时筛选指标名称和标识符。可以尝试搜索“heart”“sleep”“vo2”。</p></div>
</div>

## 类别
<p>选择器将常规摘要和来源记录定义分为睡眠、活动、心脏、呼吸、生命体征、身体测量、行动能力、骑行、营养、正念、生殖健康、症状、药物、专业记录和锻炼等类别。每一行都会显示开启或关闭状态，以及该类别中已启用定义的实时数量。由生产实现生成的<a href="/zh-hans/docs/reference/generated/core/metric-catalog/">指标目录</a>是当前清单的权威来源。</p>

<p>轻点一个类别可查看其中的指标。每个指标都有独立开关和 HealthKit 标识符。圆点颜色表示 HealthKit 当前是否在此设备上存有该指标的数据。</p>

## 选择范围
<p>您的指标选择会影响<em>所有功能</em>：</p>
<ul>
<li>每日导出——文件中只包含已启用的指标</li>
<li>单条记录追踪——只有已启用的指标会生成单条记录文件</li>
<li>每日笔记注入——只有已启用的指标会合并到 frontmatter</li>
<li>快捷指令——日期范围导出使用相同的指标选择</li>
</ul>

<div class="callout">
<strong>建议。</strong>
<p style="margin-top:6px;">建议从少量指标开始。启用睡眠、活动和心脏，然后运行一次导出并查看文件效果，再逐步添加更多类别。添加指标比在包含大量无关指标的 50 行文件中筛选内容更高效。</p>
</div>

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/reference/"><span>参考</span>导出参考——涵盖每项 Apple 指标、键名、单位、来源记录定义和导出结构。</a>
  <a href="/zh-hans/docs/android/"><span>Android</span>Android 应用——Health Connect 设置、指标、目标位置和自动化。</a>
  <a href="/zh-hans/docs/format/"><span>方法</span>格式——更改所选指标的写入方式。</a>
  <a href="/zh-hans/docs/individual-tracking/"><span>精细追踪</span>单条记录追踪——同时为每条带时间戳的记录生成一个文件。</a>
  <a href="/zh-hans/docs/daily-notes/"><span>Obsidian</span>每日笔记注入——将这些指标写入每日笔记。</a>
</div>
