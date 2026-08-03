---
title: "文件夹与知识库"
description: "选择 Markdown 文件的存放位置，并为导出文件指定子文件夹名称。这里的知识库可以是任意 iOS 文件夹——Obsidian、「文件」、iCloud Drive 或第三方文件提供方均可使用。"
---

## 此处“知识库”的含义
<p>无论您是否使用 Obsidian，应用都会将所选文件夹统称为<em>知识库</em>。如果使用 Obsidian，请选择 Obsidian 知识库根目录。否则，可选择任意文件夹，例如 iCloud Drive 中的 <code>Documents/Health</code>、某个“我的 iPhone”文件夹等。</p>

## 文件夹选择器的工作方式
<p>轻点知识库行会打开 iOS 标准文稿选择器（<code>UIDocumentPickerViewController</code>）。选择文件夹后，iOS 会返回一个<em>安全作用域 URL</em>——这是一个长期有效的访问句柄，让应用在后续启动时无需再次询问即可继续访问该文件夹。应用会将其作为书签存储在 <code>UserDefaults</code> 中。</p>

## 子文件夹名称
<p>选择知识库后，系统会提示您为导出文件所在的子文件夹命名。默认名称为 <code>Health</code>。您选择的名称将成为所有导出文件路径的前缀：</p>

<div class="doc-diagram folder-tree" aria-label="Health.md 导出文件夹结构示例">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← 您在 Health.md 中指定的名称</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>之后可在<em>设置 → Obsidian 知识库</em>中更改子文件夹。现有文件不会被移动。</p>

## 跨应用使用方式
<div class="options">
<div class="option"><strong>Obsidian</strong><p>选择 Obsidian 知识库根目录，并将子文件夹设置为 <code>Health</code> 等名称，导出文件便会作为文件夹显示在知识库目录树中。</p></div>
<div class="option"><strong>iCloud Drive</strong><p>选择 iCloud Drive 中的文件夹。文件会自动同步到您的所有 Apple 设备。</p></div>
<div class="option"><strong>我的 iPhone</strong><p>选择您在“文件”→“我的 iPhone”中创建的文件夹。文件仅保存在本地，不会同步。</p></div>
<div class="option"><strong>第三方提供方</strong><p>Dropbox、Google Drive、Working Copy 等均可使用——只要提供“文件”App 扩展，工作方式就相同。</p></div>
</div>

<div class="callout">
<strong>iOS 特性。</strong>
<p style="margin-top:6px;">如果 iOS 撤销了安全作用域书签（这种情况很少见，通常只会在底层文件夹被删除或移动后发生），导出将开始失败。解决方法是在<em>设置</em>中重新选择知识库。</p>
</div>

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/onboarding/"><span>上一页</span>入门设置——首次选择知识库的位置。</a>
  <a href="/zh-hans/docs/export/"><span>下一页</span>将导出文件写入新知识库。</a>
  <a href="/zh-hans/docs/format/"><span>自定义</span>格式自定义——设置子文件夹中文件的写入方式。</a>
</div>
