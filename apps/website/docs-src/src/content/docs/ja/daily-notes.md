---
title: "デイリーノートへの挿入"
description: "選択したヘルス指標を、Obsidianやその他のMarkdownアプリで作成している既存のデイリーノートのYAML frontmatterと、任意で本文へ統合します。"
---

## 機能の概要
<p>デイリーノート（例：<code>Daily/2026-04-28.md</code>）を作成している場合、この機能をオンにすると、エクスポートするたびに選択した指標が各ノートのYAML frontmatterへ<em>統合</em>されます。ノートのその他の内容には影響しません。</p>

<div class="doc-diagram merge-preview" aria-label="Health.mdによる統合前後のデイリーノートのfrontmatter">
<div class="merge-card">
<strong>統合前</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card">
<strong>エクスポート後</strong>
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

<p>必要に応じて、Markdownのセクション（Sleep、Activity、Heartなど）をノート本文に挿入することもできます。これらのセクションは<em>アプリが管理</em>し、エクスポートするたびに適切に置き換えられます。ご自身で記述した見出しは変更されません。</p>

## 保存場所
<div class="options">
<div class="option"><strong>フォルダ</strong><p>デイリーノートフォルダへのVault相対パスです。デフォルトは<code>Daily</code>です。Vaultのルートを対象にする場合は空欄にします。例：<code>Daily</code>、<code>Journal/Daily</code>。</p></div>
<div class="option"><strong>ファイル名</strong><p>拡張子を除いたノートファイル名のパターンです。デフォルトの<code>{date}</code>は<code>2026-04-28</code>に展開されます。</p></div>
</div>

## ファイル名のプレースホルダ
<p>自由に組み合わせて使用できます。</p>
<ul>
<li><code>{date}</code> — 完全なISO日付（<code>2026-04-28</code>）</li>
<li><code>{year}</code>、<code>{month}</code>、<code>{day}</code></li>
<li><code>{weekday}</code> — 曜日の短縮名（<code>Tue</code>）</li>
<li><code>{monthName}</code> — 月の完全名（<code>April</code>）</li>
<li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li>
</ul>
<p>例：<code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>。フィールドの下にあるプレビュー行で、展開後のパスをリアルタイムに確認できます。</p>

## オプション
<div class="options">
<div class="option"><strong>ノートがない場合は作成</strong><p>指定した日付のデイリーノートが存在しない場合、新しいノートを作成します。Obsidian Templaterなどのプラグインでデイリーノートを作成している場合は、オフのままにしてください。</p></div>
<div class="option"><strong>指標セクションを挿入</strong><p>Sleep、Activity、Heartなどの見出しもノート本文に書き込みます。アプリが管理し、エクスポートするたびに適切に置き換えられます。デフォルトではオフです。</p></div>
</div>

## 挿入される指標
<p><em>ヘルス指標</em>で選択した指標が挿入されます。ここに個別の選択画面はありません。指標の選択を変更すると、デイリーノートへの挿入にも反映されます。</p>

## frontmatterのプレビュー
<p>「デイリーノートへの挿入」画面の下部には、統合予定のfrontmatterのライブプレビューがあります。指標の選択や、形式のカスタマイズにあるfrontmatterフィールドを変更すると、プレビューも更新されます。</p>

<div class="callout">
<strong>統合の仕組み</strong>
<p style="margin-top:6px;">既存のデイリーノートにfrontmatterがある場合、アプリはユーザーのキーを保持し、アプリが管理するキーだけを追加または更新します。アプリが管理する本文セクションはHTMLコメントで囲まれるため、再実行しても同じ結果になります。</p>
</div>

## 関連項目

<div class="related">
  <a href="/ja/docs/metrics/"><span>前提条件</span>ヘルス指標 — 挿入する内容を選択します。</a>
  <a href="/ja/docs/format/"><span>形式</span>フロントマターフィールドエディタ — キー名の変更やカスタムフィールドの追加を行います。</a>
  <a href="/ja/docs/individual-tracking/"><span>詳細</span>個別トラッキング — イベントごとに記録する別の方法です。</a>
</div>
