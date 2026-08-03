---
title: "首次从 iPhone 导出"
description: "授权访问 Apple Health，选择“文件”目标位置，预览 Health.md 输出，执行一次小范围的首次 iPhone 导出，并验证写入的文件。"
---

按照本指南先完成一次小范围、可验证的导出，再调整指标、格式或自动化设置。Health.md 只读取 iOS 已授权的 Apple Health 类别，并将生成的文件写入您选择的文件夹。

<div class="availability available">
<strong>现已提供 · Health.md iPhone 版</strong>
<p>首次导出可使用免费额度。之后可以再配置计划导出和其他付费功能。</p>
</div>

## 开始之前

您需要：

- 在包含 Apple Health 数据的 iPhone 上安装 Health.md；
- 授予至少一个 Apple Health 类别的读取权限；
- 一个可写入的“文件”目标位置，例如 iCloud Drive、“我的 iPhone”或 Obsidian 知识库。

为了尽快完成首次导出，请保留默认指标和 Markdown 输出。先选择**昨天**或其他一天的日期范围，而不是导出全部历史数据。

## 1. 完成 iPhone 设置

首次启动时，轻点**开始设置**并完成七个入门步骤。授权您需要的健康数据类别，查看示例输出，在“文件”中选择文件夹，然后继续到**准备就绪**。出现解锁步骤时，您可以选择使用免费额度继续。

如果您已经完成入门设置，请打开**导出**标签页，确认 Apple Health 和本地文件夹均已准备就绪。如果目标位置缺失或无法访问，请使用文件夹控件重新选择。

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="以完整尺寸打开英文入门设置截图">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="英文版 Health.md 入门欢迎界面，显示第 1/7 步和 Start Setup 按钮。" />
  </a>
  <figcaption>此入门设置截图使用英文界面。Start Setup 会在请求访问权限前介绍本地归档、计划笔记和文件夹模式。</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="以完整尺寸打开英文设置未完成截图">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="英文版 Health.md 导出标签页，其中 Health 未连接，可选择 Choose Folder，已选择 Local iPhone Folder，并显示日期范围按钮。" />
  </a>
  <figcaption>此设置截图也使用英文界面。就绪状态标记会明确指出尚未完成的健康数据和文件夹设置。此模拟器截图特意展示两项要求均未完成的状态。</figcaption>
</figure>
</div>

## 2. 选择小范围导出

在“导出”标签页中：

1. 选择**iPhone 本地文件夹**作为目标位置。
2. 选择**昨天**或自定义一天的日期范围。
3. 首次导出时保留默认指标选择。
4. 保持选中 **Markdown**。基本导出成功后，您可以再添加 CSV、JSON 或 Obsidian Bases。

较短的日期范围更便于判断权限、空类别和目标位置问题，也能避免将耗时较长的首次请求误认为导出失败。

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/zh-hans/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="以完整尺寸打开指标选择截图">
    <img src="/docs/assets/docs/zh-hans/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="“健康指标”界面显示 219 项指标中已启用 217 项，标准指标开关已打开，并显示搜索框及可展开的睡眠、活动和心脏类别。" />
  </a>
  <figcaption>指标总数取决于已安装的应用版本和授权情况。这张本地化截图显示 219 项指标中已启用 217 项，并已启用标准指标；首次导出不必启用到这一数量。</figcaption>
</figure>

## 3. 写入前预览

轻点**预览**。预览需要 Apple Health 访问权限，但不要求本地文件夹可写，因此可用于区分读取权限问题与“文件”写入问题。

请检查预览是否显示：

- 请求的日期；
- 预期的指标名称和单位；
- 明确标注的缺失或不可用值，而不是虚构的零值；
- 所选格式和文件名结构。

如果需要调整日期、指标或格式，请返回“导出”标签页。

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/zh-hans/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="以完整尺寸打开导出预览截图">
    <img src="/docs/assets/docs/zh-hans/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="简体中文 Health.md 导出预览界面，显示 1 天日期范围、4 种每日格式、约 2.5 MB 预计输出、215 个源数据日、每周/每月/每年汇总周期、iPhone: TestVault 目标位置和四个生成文件。" />
  </a>
  <figcaption>预览将输出检查与实际写入分开。此可复现的本地化截图使用示例健康数据，并显示 iPhone: TestVault 目标位置，以及 CSV、JSON、Markdown 和 Obsidian Bases 四种输出。</figcaption>
</figure>

## 4. 导出并验证

轻点**导出数据**。如果设置尚未完成，Health.md 会指出缺失的健康数据或文件夹要求，而不会在未提示的情况下开始部分写入。

完成后：

1. 查看应用内结果，确认已写入、已跳过或失败的文件。
2. 打开“文件”应用，前往您选择的文件夹。
3. 打开一个生成的文件，确认其中的日期、单位和 frontmatter。
4. 排查问题时请保留结果详情；不要仅凭按钮恢复空闲状态就判断导出成功。

<div class="callout">
<strong>所选日期没有数据？</strong>
<p style="margin-top:6px;">请选择一个确定包含活动或睡眠数据的日期，然后检查健康数据授权和指标选择。已授权日期范围内没有数据，与传输或写入失败是不同的问题。</p>
</div>

## 后续步骤

<div class="related">
  <a href="/zh-hans/docs/metrics/"><span>选择数据</span>搜索 Apple Health 指标，并调整类别或特殊权限。</a>
  <a href="/zh-hans/docs/format/"><span>设置输出</span>配置格式、日期、单位、frontmatter、模板和文件名。</a>
  <a href="/zh-hans/docs/scheduling/"><span>自动化</span>验证一次手动导出后，再设置重复计划导出。</a>
  <a href="/zh-hans/docs/folder-vault/"><span>修复目标位置</span>了解“文件”提供方、文件夹访问权限和恢复方法。</a>
</div>
