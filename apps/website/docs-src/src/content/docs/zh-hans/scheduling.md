---
title: "计划导出"
description: "按您选择的时间每天或每周自动运行导出。使用 iOS 后台任务；设备锁定时，将通过计划的本地通知作为备用方式。"
---

## “计划”标签页
<p>这是状态页面，而非设置面板。您可以一目了然地查看：</p>
<ul>
<li>计划导出是开启还是关闭</li>
<li>下一次计划运行的时间（如有）</li>
<li>上次运行的结果</li>
</ul>
<p>一个按钮——<em>设置计划</em>（或<em>管理计划</em>）——即可打开详细设置页面。</p>

## 计划设置
<div class="options">
<div class="option"><strong>启用计划导出</strong><p>页面顶部的总开关。关闭后，不会在后台运行，也不会发送通知。</p></div>
<div class="option"><strong>频率</strong><p>每天、每周或每月。每天导出昨天的数据；每周导出过去 7 天的数据；每月导出过去 30 天的数据。</p></div>
<div class="option"><strong>时间</strong><p>小时和分钟。iOS 仅将其视为参考时间，并不保证准时运行——请参阅下方的限制说明。</p></div>
</div>

## 导出历史
<p>“计划”页面底部的列表会记录每次计划运行及其结果。轻点某一行可查看详情。运行失败时会显示<em>重试</em>按钮，用于重新导出对应的日期范围。</p>

## iOS 计划任务的实际运行方式
<div class="doc-diagram">
  <div class="flow-steps" aria-label="计划导出的备用流程">
    <span><strong>1. 目标时间</strong>Health.md 请求 iOS 在您选择的时间前后唤醒应用。</span>
    <span><strong>2. 后台尝试</strong>如果设备可用，iOS 会运行后台应用刷新任务。</span>
    <span><strong>3. 锁定时的备用方式</strong>如果 HealthKit 不可用，Health.md 会发送通知。</span>
    <span><strong>4. 轻点完成</strong>打开通知后，应用即可读取 HealthKit 并执行导出。</span>
  </div>
</div>

<div class="callout">
<strong>您需要了解的 iOS 限制。</strong>
<p style="margin-top:6px;">设备锁定时无法读取 HealthKit 数据。计划导出通过 <code>BGAppRefreshTask</code> 运行，iOS 会根据使用模式择机安排任务，因此您设置的时间只是目标时间，并非保证时间。如果设备在计划时间处于锁定状态，应用会发送本地通知作为备用方式；轻点通知即可执行导出。</p>
</div>
<ul>
<li>计划时间并不精确。iOS 可能提前或延后运行任务；如果设备没电或断开连接，也可能跳过任务。</li>
<li>如果手机每天大致在同一时间连接电源并处于解锁状态，计划导出的运行效果最佳。</li>
<li>如果导出因设备锁定而失败，请轻点通知；应用将获取 HealthKit 访问权限并执行导出。</li>
</ul>

## 编程控制
<p>您可以通过快捷指令中的<em>开启或关闭计划导出</em>意图来开启或关闭计划。示例请参阅<a href="/zh-hans/docs/shortcuts/">快捷指令</a>。</p>

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/export/"><span>手动</span>导出——用于一次性导出指定日期范围。</a>
  <a href="/zh-hans/docs/shortcuts/"><span>自动化</span>快捷指令——通过自动化开启或关闭计划。</a>
  <a href="/zh-hans/docs/sync/"><span>跨设备</span>Mac 同步——也可在 Mac 上设置计划。</a>
</div>
