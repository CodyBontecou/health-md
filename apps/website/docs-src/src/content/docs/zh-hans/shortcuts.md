---
title: "快捷指令与 App Intents"
description: "八个 App Intent 可让您通过 Siri、快捷指令 App、专注模式过滤器、自动化及其他支持 App Intent 的宿主触发导出、获取摘要和切换计划。"
---

## 可用 Intent
<div class="options">
<div class="option"><strong>导出昨天的健康数据</strong><p>无需参数的快捷指令。适合“只导出昨天的数据，不要再提示”的快速操作。使用与手动导出相同的引擎。</p></div>
<div class="option"><strong>导出指定日期的健康数据</strong><p>接受一个<em>日期</em>参数。忽略具体时间。适用于日历驱动的自动化。</p></div>
<div class="option"><strong>导出指定日期范围的健康数据</strong><p>接受<em>开始日期</em>和<em>结束日期</em>参数，包含首尾两天。适用于补录历史数据。</p></div>
<div class="option"><strong>导出最近 N 天的健康数据</strong><p>接受<em>天数</em>参数（1–366），截止到昨天，默认为 7。适合“每周日导出最近 7 天数据”之类的自动化。</p></div>
<div class="option"><strong>获取指定日期的健康摘要</strong><p>返回包含步数、活动消耗热量、睡眠和心率的结构化快照，不会向知识库写入任何内容。可在快捷指令中将这些值传递给其他 App。</p></div>
<div class="option"><strong>获取上次导出状态</strong><p>返回最近一次已记录导出的时间戳、成功状态、天数及失败原因。设备锁定时发起的请求会保持待处理状态，直到重试，因此待处理期间不会作为当前状态返回。</p></div>
<div class="option"><strong>开启或关闭计划导出</strong><p>接受一个布尔参数。可用于暂停计划（例如开启度假专注模式时），之后再恢复。</p></div>
<div class="option"><strong>导出健康数据</strong><p>通用导出操作，使用 App 内“导出”弹窗上次保存的日期范围。此操作较少使用；指定日期范围的变体通常更清晰。</p></div>
</div>

## 如何找到这些 Intent
<p>在 iOS 或 macOS 上打开快捷指令 App。轻点 <em>+</em> 按钮创建快捷指令，然后搜索“Health.md”或上述任一 Intent 标题。它们位于<em>健康</em>类别下。</p>
<p>大多数 Intent 都设置了 <code>openAppWhenRun = false</code>，因此可在后台执行，不会启动 App，也不会闪现界面。它们可用于自动化、专注模式过滤器、“嘿 Siri”接力和操作按钮。</p>

<div class="callout">
<strong>锁定时运行不会解锁 HealthKit。</strong>
<p style="margin-top:6px;">iPhone 锁定时，Apple 会保护 HealthKit 数据，并在<a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">锁定约十分钟后撤销 App 的访问权限</a>。<em>允许锁定时运行</em>可让快捷指令启动操作，但无法绕过 HealthKit 数据保护。快捷指令中的 Health.md App 内容权限也无法绕过此限制。</p>
<p>如果 HealthKit 不可用，Health.md 会保留请求的日期并标记为待处理，同时发送<em>健康数据导出需要处理</em>通知。解锁 iPhone 后，轻点通知或打开 Health.md 进行重试。iPhone 保持锁定时，无法保证完全无人值守的导出。</p>
</div>

<a id="recipe-nightly-export-with-confirmation"></a>
## 示例：每日导出并确认
<ol>
<li><strong>个人自动化</strong> → <em>特定时间</em> → 选择您通常会使用已解锁 iPhone 的时间，例如上午 8:00。</li>
<li>添加<em>导出昨天的健康数据</em> Intent。</li>
<li>添加<em>获取上次导出状态</em> Intent。</li>
<li>使用结果执行<em>显示通知</em>。</li>
</ol>
<p><strong>待处理状态说明：</strong><em>获取上次导出状态</em>会读取最近一条已记录的导出历史。如果本次运行因 HealthKit 数据锁定而失败，在重试待处理请求前，它可能仍会显示上一次导出。对于待处理任务，应以 Health.md 自身的恢复通知为准。</p>

## 示例：一次性补录历史数据
<ol>
<li>创建快捷指令。</li>
<li>添加<em>导出指定日期范围的健康数据</em>，将开始日期设为 2024-01-01，结束日期设为 2024-12-31。</li>
<li>从快捷指令运行。它会逐日处理全年数据，每天写入一个文件。完整年份可能需要几分钟。</li>
</ol>

## 示例：度假期间暂停计划
<ol>
<li><strong>专注模式过滤器</strong>：开启<em>度假</em>专注模式时，运行<em>开启或关闭计划导出</em>，并将“已启用”设为 false。</li>
<li>关闭专注模式时再次运行，并将“已启用”设为 true。</li>
</ol>

<div class="callout">
<strong>需要授权。</strong>
<p style="margin-top:6px;">Intent 会沿用 App 内的 HealthKit 权限和知识库选择。如果尚未在此设备上至少打开并完成一次 App 设置，Intent 将失败并显示明确错误。</p>
</div>

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/scheduling/"><span>来源</span>计划导出——切换 Intent 对应的 App 内功能。</a>
  <a href="/zh-hans/docs/export/"><span>来源</span>导出——日期范围 Intent 对应的 App 内功能。</a>
</div>
