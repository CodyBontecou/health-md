---
title: "出口"
description: "立即或按计划导出 Apple Health 数据。在归档中查看准备情况，在立即导出中选择范围，并为每个自动化设置目标位置。"
---

<p>iPhone 上的 Health.md 有三个标签：<strong>归档</strong>、<strong>自动化</strong>和<strong>设置</strong>，另有一个圆形的<strong>立即导出</strong>按钮。在 iPad 上，这些标签会移到侧边栏。</p>

## 在归档中查看准备情况
<p><strong>归档</strong>日历显示每个自动化已覆盖的健康数据日期。如果有问题阻止导出，顶部的<strong>需要关注</strong>卡片会说明原因。</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.md 显示的是 App 的设置状态，并不代表已确认每个类别的读取权限。HealthKit 不会透露被拒绝的读取权限。请在 Apple Health 中检查类别。结果为空可能意味着访问被拒绝，或者没有数据。<a href="/zh-hans/docs/troubleshooting/">排查缺失数据</a>。</p></div>
<div class="option"><strong>文件夹</strong><p>在<strong>设置 → 文件夹</strong>中选择或重新选择文件夹。如果移动文件夹后 iOS 失去了访问权限，Health.md 会请你重新选择。不会删除任何内容。</p></div>
</div>

## 为自动化选择导出目标位置
<p>每个自动化都有自己的目标位置。打开<strong>自动化</strong>，选择一个自动化，然后打开<strong>输出</strong>。</p>

<div class="options">
<div class="option"><strong>本地文件夹</strong><p>直接写入你在此设备上选择的文件夹或 Obsidian 仓库。</p></div>
<div class="option"><strong>已连接的 Mac</strong><p>将获取的每日数据和设置的精确快照发送到附近的 Mac App。iPhone 读取 HealthKit；Mac 生成所选格式并写入文件。</p></div>
<div class="option"><strong>API 端点</strong><p>从 iPhone 直接将 JSON 信封 POST 到你配置的 HTTP(S) 端点。<a href="/zh-hans/docs/api-endpoint/">查看 API 端点</a>。</p></div>
<div class="option"><strong>Agent Data 网关</strong><p>将每个导出的文件原样上传到网关的接收端点。</p></div>
</div>

## 在立即导出中选择范围
<p>轻点<strong>立即导出</strong>；如果有多个自动化，请先选择一个，然后选择范围。</p>

<div class="options">
<div class="option"><strong>昨天</strong><p>这一天已经结束，因此最适合每日导出。</p></div>
<div class="option"><strong>7 天 / 30 天</strong><p>截至昨天的最近一周或一个月。30 天及以上时会先请你确认。</p></div>
<div class="option"><strong>自定义</strong><p>为特定范围选择开始日期和结束日期。</p></div>
</div>
<p><strong>将写入</strong>会显示目标位置，以及导出涵盖的大致文件数和天数。<strong>仅日期范围摘要</strong>只写入一个摘要文件，而不是每日文件。“今天”和“全部时间”仍可在<strong>自动化 → 所有导出设置</strong>中使用。</p>

## 预览或导出
<div class="options">
<div class="option"><strong>预览</strong><p>在写入任何内容之前，显示将生成的文件及其内容。</p></div>
<div class="option"><strong>导出</strong><p>运行导出，在标签栏上方显示进度和取消按钮，并将结果记录到历史和归档日历中。</p></div>
</div>

## 选择数据详细级别

<div class="options">
 <div class="option"> <strong>摘要</strong> <p>紧凑的每日总计和汇总，用于阅读、笔记和仪表板。 </p> </div>
 <div class="option"> <strong>详细时间序列</strong> <p>选定的带时间戳的样本和间隔。当所选指标公开合适的细节时，此级别在 Apple 和 Android 上均可用。 </p> </div>
 <div class="option"> <strong>无损健康记录</strong> <p>规范的HealthKit源记录存档。此级别仅限 Apple。 Android 不会将Health Connect记录转换为HealthKit存档。 </p> </div>
 </div>

## “导出”实际执行的操作
 <ol>
 <li>对于范围内的每一天，捕获选定的摘要预测。添加详细时间序列的兼容样本。并且，对于无损健康记录，添加规范源记录和查询诊断。 </li>
 <li>应用您选择的格式（ Markdown 、Bases、JSON 或 CSV）和模板。 </li>
 <li>每天将一个文件写入<code>{vault}/{subfolder}/</code> ，通过连接的 Mac 工作流程传输文件，或将版本化的 JSON 信封发布到 API 端点。 </li>
 <li>如果<em>个体跟踪</em>已打开，则从基于文件的目标的规范存档中派生选定的每条目Markdown文件。 </li>
 <li>如果<em>每日笔记注入</em>处于启用状态，请将选定的汇总字段合并到每日笔记中。 </li>
 </ol>

<p> JSON 和 CSV 可以保留规范记录。 Markdown和 Bases 保持可读并公开紧凑的捕获诊断，而不是嵌入存档。有关确切的架构和省略规则，请参阅<a href="/zh-hans/docs/reference/">完整导出参考</a> 。 </p>

## 停止、取消并重试

停止或取消只会结束当前的尝试。已完成的文件和日期保持已完成状态，而未解决的日期仍可重试。取消计划的尝试不会禁用其重复计划。

## 简介和值得信赖的历史

已保存的配置方案会在运行时固定设置和目标位置。支持配置方案的计划运行和自动化历史记录行会保留运行时的配置方案，历史记录还会保留实际使用的目标位置的隐私友好标签。手动导出行可能省略配置方案名称。之后重命名或更改目标位置不会改写已有历史。如果引用的配置方案不存在，操作会失败，而不会改用其他设置。请参阅[导出配置方案](/zh-hans/docs/export-profiles/)。

<div class="callout">
 <strong>解锁行为。 </strong>
 <p style="margin-top:6px;">启用订阅的iPhone / iPad和Google Play手机版本需要有效试用、订阅、终身或保留永久访问权限才能导出和安排。当地自由出口补贴已不复存在。 Mac 配套和F-Droid包含访问版本保留其记录的异常。 <a href="/zh-hans/docs/paywall/">请参阅付费专区页面</a>了解 Apple 购买详情。 </p>
 </div>

## ＃＃ 有关的

<div class="related">
 <a href="/zh-hans/docs/export-profiles/"> <span>可重复设置</span>导出配置文件，保存独立设置、目的地、计划和稳定的自动化 ID。 </a>
 <a href="/zh-hans/docs/scheduling/"> <span>日常使用</span>计划，自动执行此操作，这样您就再也不用点击导出了。 </a>
 <a href="/zh-hans/docs/api-endpoint/"> <span>集成</span> API Endpoint，将选定的 JSON 直接发送到您自己的服务。 </a>
 <a href="/zh-hans/docs/format/"> <span>自定义</span>格式自定义，更改每个文件的外观。 </a>
 <a href="/zh-hans/docs/shortcuts/"> <span>电源</span> Shortcuts ，触发从Siri 、自动化或其他应用程序的导出。 </a>
 <a href="/zh-hans/docs/reference/"> <span>参考</span>导出参考、模式、规范记录、诊断和生成的示例。 </a>
 </div>
