---
title: "API 端点"
description: "将所选 Apple Health JSON 直接从 iPhone 发送到您自己的 HTTP(S) 端点。"
---

<p>API 端点是一种导出目标，适合希望将 Health.md 数据发送到自有服务器、Webhook、数据库、仪表板或自动化流程的用户。iPhone 仍负责读取 Apple Health；与写入文件不同，它会将 JSON POST 到您配置的端点。</p>

<div class="callout">
<strong>隐私提醒。</strong>
<p style="margin-top:6px;">此目标会有意将所选健康数据发送到您输入的 URL。请使用您控制或信任的端点，优先使用 HTTPS，并且只选择您的服务确实需要的指标。</p>
</div>

## 设置目标位置

<ol>
<li>在 iPhone 上打开 Health.md。</li>
<li>前往<strong>导出</strong>。</li>
<li>在<strong>导出目标</strong>中选择<strong>API 端点</strong>。</li>
<li>输入 URL，例如 <code>https://api.example.com/healthmd/ingest</code>。</li>
<li>可选：输入持有者令牌。Health.md 会将其存储在钥匙串中。</li>
<li>轻点<strong>完成</strong>，选择日期范围和指标，再轻点<strong>导出</strong>。</li>
</ol>

<p>如果输入普通令牌，Health.md 会以 <code>Authorization: Bearer &lt;token&gt;</code> 形式发送。如果该值已经以 <code>Bearer </code> 或 <code>Basic </code> 开头，Health.md 会原样发送。</p>

## 载荷结构

<p>每次导出操作会发送一个 POST。正文是独立版本化的 <code>healthmd.api_export</code> 封装，其中包含采用公开 schema-v7 的 <code>healthmd.health_data</code> 每日记录。API 封装 v1 携带每日记录；v2 还可以携带提供方辅助记录，而无需更改每日记录架构。</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>请求范围内保留的完整每日 schema-v7 对象，包括查询清单可作为证据的完整空记录。</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>在每日文档得以保留前便处理失败的日期。</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p><code>records</code> 内的每日架构版本。它与 API 封装版本分别演进。</p></div>
<div class="option"><strong>提供方辅助记录</strong><p>启用已连接的提供方时，v2 可按条件包含使用自身架构和身份规则的外部记录。</p></div>
</div>

<p>可查看由生产实现生成的完整 <a href="/docs/reference/generated/automation/api-export-v1.json">API v1 封装</a>和 <a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">API v2 提供方辅助记录封装</a>。<a href="/zh-hans/docs/reference/api-and-cli/">API 与 CLI 契约</a>记录了每个字段、版本边界和接受规则。</p>

## 端点要求

<div class="options">
<div class="option"><strong>方法</strong><p>接受 <code>POST</code>。</p></div>
<div class="option"><strong>内容类型</strong><p>接受 <code>application/json</code>。</p></div>
<div class="option"><strong>成功</strong><p>安全接收载荷后，返回任意 <code>2xx</code> 状态。</p></div>
<div class="option"><strong>失败</strong><p>拒绝请求时返回 <code>4xx</code> 或 <code>5xx</code>。如果响应内容可用，Health.md 会显示简短预览。</p></div>
</div>

<p>为确保可靠接收，请让端点按日期保持幂等。用户更改指标或修复服务器错误后，可能会重复导出相同日期范围。</p>

## 建议

<ul>
<li>上传长时间范围的历史数据前，先用一天的数据测试。</li>
<li>如果来源完整性很重要，请保持启用“无损健康记录”；对于密集路线、临床文档、ECG 或附件，请缩小日期范围。</li>
<li>存储任何载荷前，先在服务器端验证令牌。</li>
<li>使用 <code>records[].date</code> 作为每日主键。</li>
<li>返回简洁的错误正文；Health.md 只显示简短预览。</li>
</ul>

## 故障排除

| 问题 | 通常表示 | 解决方法 |
|---|---|---|
| API 目标尚未就绪 | URL 为空或无效 | 重新打开 API 端点设置，并输入有效的 HTTP(S) URL。 |
| HTTP 401 或 403 | 令牌缺失或被拒绝 | 更新令牌或服务器身份验证规则。 |
| HTTP 404 | URL 路径错误 | 检查服务器上的路由。 |
| HTTP 413 | 载荷过大 | 减少导出天数；只有接收方不需要规范来源记录时，才使用仅摘要输出。 |
| 部分日期缺失 | 这些日期没有已启用的 HealthKit 数据 | 检查 <code>failed_date_details</code> 和指标选择。 |

## 相关内容

<div class="related">
  <a href="/zh-hans/docs/export/"><span>来源</span>导出——选择目标位置和日期范围，并运行手动导出。</a>
  <a href="/zh-hans/docs/reference/api-and-cli/"><span>架构</span>API 与 CLI 参考——精确封装、版本、失败行为和生成示例。</a>
  <a href="/zh-hans/docs/format/"><span>输出</span>格式自定义——JSON、CSV、Markdown、单位和字段。</a>
</div>
