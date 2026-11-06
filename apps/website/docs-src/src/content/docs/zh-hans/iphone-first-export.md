---
title: "首次从 iPhone 导出"
description: "授权访问 Apple Health，选择“文件”目标位置，预览 Health.md 输出，执行一次小范围的首次 iPhone 导出，并验证写入的文件。"
---

按照本指南先完成一次小范围、可验证的导出，再调整指标、格式或自动化设置。Health.md 只读取 iOS 已授权的 Apple Health 类别，并将生成的文件写入您选择的文件夹。

<div class="availability available">
<strong>现已推出 · iPhone 版 Health.md</strong>
<p>导出需要有效的试用、订阅或 Lifetime 访问权限。计划和其他自动化可以稍后再设置。</p>
</div>

## 开始之前

开始之前，请确认你已准备好：

- 在存有 Apple Health 数据的 iPhone 上安装 [App Store 中的 Health.md](https://apps.apple.com/app/health-md/id6757763969)
- 至少一个 Apple Health 类别的读取权限
- “文件”中一个可写入的文件夹（iCloud 云盘、我的 iPhone 或 Obsidian 仓库）

保留默认指标和 Markdown 格式。选择**昨天**作为一天的范围。

## 1. 完成 iPhone 设置

Health.md 的设置共 5 步。任何一步都不会阻止你继续；Apple Health 访问和文件夹都可以跳过，稍后再设置。

首次启动时，轻点**连接 Apple Health**。允许你需要的健康类别，查看示例输出，在“文件”中选择一个文件夹，然后继续到最后一步。

设置完成后，App 会打开**归档**。如果 Apple Health 或文件夹需要处理，顶部的**需要关注**卡片会说明需要修复的内容。

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="以原始大小打开设置截图">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Health.md 设置第 1 步（共 5 步），显示三个步骤和连接 Apple Health 按钮。" />
  </a>
  <figcaption>设置会在请求访问前说明 Health.md 读取什么，以及文件保存在哪里。此截图的界面保持为英文。</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="以原始大小打开立即导出截图">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Health.md 立即导出面板，已选择昨天，显示仅日期范围摘要开关、一天一个文件的将写入摘要和导出按钮。" />
  </a>
  <figcaption>立即导出会在开始前显示将要写入的内容。此参考截图的界面同样为英文。</figcaption>
</figure>
</div>

## 2. 选择一次小规模导出

轻点标签栏旁的圆形**立即导出**按钮。然后：

1. 选择**昨天**。
2. 保持**仅日期范围摘要**关闭。
3. 确认**将写入**显示了你的文件夹，以及一天大约一个文件。

默认自动化使用默认指标选择和 **Markdown**。如需更改，请打开**自动化**，选择该自动化，然后打开**指标**或**格式**。这次导出成功后，再添加 CSV、JSON 或 Obsidian Bases。范围越短，越容易发现权限、空数据和文件夹问题。

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/zh-hans/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="以原始大小打开指标选择截图">
    <img src="/docs/assets/docs/zh-hans/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Health.md 指标页面，显示已启用指标数量、推荐/全选/取消全选按钮、搜索栏和带数量的类别。" />
  </a>
  <figcaption>指标总数因 App 版本和权限而异。此本地化截图显示 219 个指标中已启用 217 个。</figcaption>
</figure>

## 3. 写入前先预览

在**立即导出**中轻点**预览**。预览需要 Apple Health 访问权限，但不需要可写入的文件夹。

在测试文件夹之前，先用预览检查 Apple Health 权限问题。

确认预览显示：

- 你请求的日期
- 预期的指标名称和单位
- 缺失或不可用的值，而不是错误的零
- 你选择的格式和文件名结构

如果需要更改指标或格式，请关闭预览并修改自动化设置。

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/zh-hans/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="以原始大小打开导出预览截图">
    <img src="/docs/assets/docs/zh-hans/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Health.md 导出预览，显示睡眠时间窗口、一天 Markdown 的估算、汇总周期、目标文件夹和将生成的文件名。" />
  </a>
  <figcaption>此示例使用示例健康数据。</figcaption>
</figure>

## 4. 导出并检查

轻点**导出昨天**。如果设置不完整，Health.md 会指出 Apple Health 或文件夹缺少的要求。

导出完成后：

1. 在结果中查看已写入、已跳过和失败的文件。该日期会出现在**归档**日历中。
2. 在“文件”App 中打开所选文件夹。
3. 打开一个生成的文件，检查日期、单位和前置元数据是否正确。
4. 保留结果详情，以备需要排查问题。

日历上的已覆盖日期只是摘要。轻点某个日期，可查看当天每个自动化的状态。

<div class="callout">
<strong>所选日期没有数据？</strong>
<p style="margin-top:6px;">请选择有活动或睡眠数据的日期，然后检查 Apple Health 权限和指标选择。范围为空并不是写入失败。</p>
</div>

## 后续步骤

<div class="related">
  <a href="/zh-hans/docs/metrics/"><span>选择数据</span>搜索 Apple Health 指标，并调整类别或特殊权限。</a>
  <a href="/zh-hans/docs/format/"><span>设置输出</span>配置格式、日期、单位、frontmatter、模板和文件名。</a>
  <a href="/zh-hans/docs/scheduling/"><span>自动化</span>验证一次手动导出后，再设置重复计划导出。</a>
  <a href="/zh-hans/docs/folder-vault/"><span>修复目标位置</span>了解“文件”提供方、文件夹访问权限和恢复方法。</a>
</div>
