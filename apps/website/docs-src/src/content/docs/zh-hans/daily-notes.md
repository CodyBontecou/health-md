---
title: "每日笔记注入"
description: "将所选健康指标合并到现有每日笔记（即您在 Obsidian 或其他 Markdown 应用中编写的笔记）的 YAML frontmatter，并可选择合并到正文中。"
---

## 功能说明
<p>如果您使用每日笔记（例如 <code>Daily/2026-04-28.md</code>），请开启此功能。每次导出时，应用都会将所选指标<em>合并</em>到这些笔记的 YAML frontmatter 中，而不会改动笔记的其他内容。</p>

<div class="doc-diagram merge-preview" aria-label="Health.md 合并前后的每日笔记 frontmatter">
<div class="merge-card">
<strong>导出前</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card">
<strong>导出后</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre>
</div>
</div>

<p>您还可以选择让应用将 Markdown 章节（睡眠、活动、心脏等）注入笔记正文。这些章节由<em>应用管理</em>，每次导出时都会被完整替换。您自己编写的标题不会受到影响。</p>

## 位置
<div class="options">
<div class="option"><strong>文件夹</strong><p>每日笔记文件夹相对于知识库的路径。默认为 <code>Daily</code>。留空则使用知识库根目录。例如：<code>Daily</code>、<code>Journal/Daily</code>。</p></div>
<div class="option"><strong>文件名</strong><p>不含扩展名的笔记文件名格式。默认值 <code>{date}</code> 会解析为 <code>2026-04-28</code>。</p></div>
</div>

## 文件名占位符
<p>可以混合使用：</p>
<ul>
<li><code>{date}</code> — 完整 ISO 日期（<code>2026-04-28</code>）</li>
<li><code>{year}</code>、<code>{month}</code>、<code>{day}</code></li>
<li><code>{weekday}</code> — 星期简称（<code>Tue</code>）</li>
<li><code>{monthName}</code> — 月份全称（<code>April</code>）</li>
<li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li>
</ul>
<p>示例：<code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>。字段下方的预览行会实时显示解析后的路径。</p>

## 选项
<div class="options">
<div class="option"><strong>笔记不存在时创建</strong><p>如果某个日期的每日笔记不存在，则新建一篇。若您使用 Obsidian Templater 或类似插件创建每日笔记，请保持关闭。</p></div>
<div class="option"><strong>注入指标分区</strong><p>同时将睡眠、活动、心脏等标题写入笔记正文。这些内容由应用管理，每次导出时都会完整替换。默认关闭。</p></div>
</div>

## 注入哪些指标
<p>注入您在<em>健康指标</em>中选择的所有指标。此处没有单独的选择器。更改健康指标选择后，每日笔记注入会自动采用新的设置。</p>

## Frontmatter 预览
<p>每日笔记注入界面底部会实时预览即将合并的 frontmatter。更改指标选择或格式自定义中的 frontmatter 字段时，预览会同步更新。</p>

<div class="callout">
<strong>合并方式。</strong>
<p style="margin-top:6px;">如果现有每日笔记已有 frontmatter，应用会保留您的键，仅添加或更新由应用管理的键。应用管理的正文分区会用 HTML 注释包裹，因此重复导出不会产生重复内容。</p>
</div>

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/metrics/"><span>前置条件</span>健康指标 — 选择要注入的内容。</a>
  <a href="/zh-hans/docs/format/"><span>格式</span>Frontmatter 字段编辑器 — 重命名键并添加自定义字段。</a>
  <a href="/zh-hans/docs/individual-tracking/"><span>精细追踪</span>单条记录追踪 — 按事件追踪的替代方式。</a>
</div>
