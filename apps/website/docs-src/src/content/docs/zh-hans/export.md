---
title: "出口"
description: "使用“导出”选项卡检查HealthKit和保管库连接。选择目的地并导出日期范围。"
---

<p>导出选项卡由三个小决定组成：确认准备情况、选择目的地、然后在预览或导出之前选择日期范围。 </p>

## 读取状态徽章
 <div class="options">
 <div class="option"> <strong>健康徽章</strong> <p>绿点表示HealthKit已获得授权。红点表示未授予访问权限。点击以重试 iOS 权限表。每次安装该表仅出现一次。之后，打开设置→隐私和隐私。安全→健康。 </p> </div>
 <div class="option"> <strong>保管库徽章</strong> <p>绿点 = 已选择保管库文件夹。点击以重新选择或更改保管库。标签显示文件夹名称。 </p> </div>
 </div>
 <p>导出<em>操作保持禁用状态</em>直到HealthKit 、输出格式和所选目标准备就绪。这可以防止最常见的故障模式：尝试在没有目的地的情况下导出。 </p>

## 选择导出目标
 <p>导出目标卡决定数据的去向： </p>

<div class="options">
 <div class="option"> <strong>本地iPhone文件夹</strong> <p>直接写入您在此设备上选择的文件夹或Obsidian保管库。 </p> </div>
 <div class="option"> <strong>已连接的 Mac </strong> <p>将捕获的每日数据和准确的设置快照发送到附近的 Mac 应用程序。 iPhone读取HealthKit 。 Mac 渲染选定的格式并写入文件。 </p> </div>
 <div class="option"> <strong> API 端点</strong> <p>将 JSON 信封直接从iPhone发送到用户配置的 HTTP(S) 端点。 <a href="/zh-hans/docs/api-endpoint/">请参阅 API 端点</a> 。 </p> </div>
 </div>

## 选择日期范围
 <p>日期预设涵盖常见路径： </p>

<div class="options">
 <div class="option"> <strong>今天</strong> <p>导出当天。对于测试输出格式很有用。 </p> </div>
 <div class="option"> <strong>昨天</strong> <p>最安全的每日导出选择，因为这一天已经结束。 </p> </div>
 <div class="option"> <strong>所有时间</strong> <p>从Health.md可以找到的最早HealthKit数据回填。 </p> </div>
 <div class="option"> <strong>自定义</strong> <p>选择特定范围的开始日期和结束日期。 </p> </div>
 </div>

## 预览或导出
 <div class="options">
 <div class="option"> <strong>预览</strong> <p>显示写入任何内容之前将生成的文件和内容。 </p> </div>
 <div class="option"> <strong>导出</strong> <p>运行导出，在主屏幕上显示进度，并将结果记录在历史记录中。 </p> </div>
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

保存的配置文件会冻结其设置和运行目标。配置文件感知的计划和自动化历史记录行保留运行时配置文件，而历史记录则保留实际使用的目的地的隐私安全标签。手动导出选项卡行可能会省略配置文件名称。以后的重命名和目标更改不会重写现有历史记录。缺少的配置文件引用将无法关闭，而不是回退。请参阅[导出配置文件](/zh-hans/docs/export-profiles/)。

## 标签栏

<p>屏幕底部的四个选项卡（导出、计划、同步、设置）覆盖了整个应用程序表面区域。其他一切都位于“设置”深处的一两层。 </p>

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
