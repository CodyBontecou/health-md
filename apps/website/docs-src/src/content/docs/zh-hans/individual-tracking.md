---
title: "单条记录追踪"
description: "可选择为每条带时间戳的记录分别写入一个文件——每次锻炼、每次血压测量和每条情绪记录都会生成独立的 Markdown 文件，并在文件名中包含时间戳。"
---

## 适用场景
<p>每日导出会为每天生成一个包含摘要的文件。<em>单条记录追踪</em>适用于需要<em>引用单个事件</em>的场景——例如从日记笔记链接到某次特定锻炼，或在每周回顾中反向链接某条情绪记录。</p>

<p>它是每日导出的补充，而非替代。两者同时启用时，会同时生成这两类文件。</p>

## 两步设置
<p>设置界面采用明确的两步流程：</p>
<ol>
<li><strong>总开关。</strong>全局开启此功能。</li>
<li><strong>按指标选择。</strong>选择<em>哪些</em>指标需要生成单独文件。大多数人不希望每条心率读数都生成文件（每天 10,000 条），但会希望每次锻炼都生成一个文件（每天约 1 个）。</li>
</ol>

## 快捷操作
<div class="options">
<div class="option"><strong>启用建议的指标</strong><p>合理的默认选项：情绪、症状、锻炼、血压和血糖。这些指标最适合为每条记录生成一个文件。</p></div>
<div class="option"><strong>启用所有指标</strong><p>启用全部指标。请谨慎使用——每天可能生成数千个文件。</p></div>
<div class="option"><strong>禁用所有指标</strong><p>清除按指标选择，但不会关闭总开关。</p></div>
</div>

## 文件夹结构
<div class="options">
<div class="option"><strong>条目文件夹</strong><p>单独文件的知识库相对路径。默认值：<code>entries</code>。</p></div>
<div class="option"><strong>按类别整理</strong><p>开启后，条目会存放在对应的类别子文件夹中（<code>entries/workouts/</code>、<code>entries/symptoms/</code>）。关闭后，所有条目都存放在同一个平面文件夹中。</p></div>
</div>

## 文件名模板
<p>默认值：<code>{date}_{time}_{metric}</code>。可用占位符：<code>{date}</code>、<code>{time}</code>、<code>{metric}</code>、<code>{category}</code>。输出示例：</p>

<div class="doc-diagram folder-tree" aria-label="单条记录文件树示例">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>

<p>规范的来源记录条目会在配置的文件名后附加所选指标和小写 HealthKit UUID。这样可确保同一来源记录在重复运行时保持稳定，并避免同一分钟内发生文件名冲突。不含 UUID 的兼容条目则保留较短的旧版文件名行为。</p>

<div class="callout">
<strong>注意。</strong>
<p style="margin-top:6px;">这里只显示已在<em>健康指标</em>中启用至少一个指标的类别。请先在那里启用指标，再返回此处选择是否为其启用单条记录追踪。在基于路径构建自动化之前，请参阅<a href="/zh-hans/docs/reference/individual-entry-tracking/">来源记录标识契约</a>和生成的<a href="/zh-hans/docs/reference/generated/individual/filename-path-matrix/">文件名矩阵</a>。</p>
</div>

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/metrics/"><span>前提条件</span>健康指标——请先启用指标。</a>
  <a href="/zh-hans/docs/format/"><span>输出</span>格式——同样适用于条目文件。</a>
  <a href="/zh-hans/docs/daily-notes/"><span>替代方案</span>每日笔记注入——将指标附加到笔记的另一种方式。</a>
  <a href="/zh-hans/docs/reference/individual-entry-tracking/"><span>契约</span>单条记录参考——UUID 标识、frontmatter、专用条目和兼容性回退。</a>
</div>
