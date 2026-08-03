---
title: "個別エントリトラッキング"
description: "必要に応じて、タイムスタンプ付きエントリごとに1つのファイルをエクスポートします。ワークアウト、血圧測定、気分の記録などが、それぞれタイムスタンプを含むファイル名のMarkdownファイルになります。"
---

## 使用する場面
<p>日次エクスポートでは、サマリーを含むファイルが1日につき1つ作成されます。<em>個別トラッキング</em>は、<em>特定のイベントを1件だけ参照</em>したい場合に使用します。たとえば、日記から特定のワークアウトへリンクしたり、気分のエントリから週次レビューへバックリンクしたりできます。</p>

<p>これは日次エクスポートの代わりではなく、追加で行われます。両方をオンにすると、両方の種類のファイルが作成されます。</p>

## 2段階の設定
<p>設定UIは意図的に2段階になっています。</p>
<ol>
<li><strong>マスタースイッチ</strong>機能全体をオンにします。</li>
<li><strong>指標ごとの選択</strong>個別ファイルを作成する<em>指標</em>を選びます。ほとんどの場合、心拍数の測定ごとにファイルを作成する必要はありません（1日10,000件）が、ワークアウトごとには必要です（1日約1件）。</li>
</ol>

## クイックアクション
<div class="options">
<div class="option"><strong>推奨指標を有効にする</strong><p>気分、症状、ワークアウト、血圧、血糖値という実用的な初期設定です。1エントリにつき1ファイルが適している指標です。</p></div>
<div class="option"><strong>すべての指標を有効にする</strong><p>すべてを対象にします。1日に数千個のファイルが作成される可能性があるため、注意してください。</p></div>
<div class="option"><strong>すべての指標を無効にする</strong><p>マスタースイッチは変更せず、指標ごとの選択をすべて解除します。</p></div>
</div>

## フォルダ構造
<div class="options">
<div class="option"><strong>エントリフォルダ</strong><p>個別ファイルの保存先となる、Vaultからの相対パスです。デフォルト：<code>entries</code>。</p></div>
<div class="option"><strong>カテゴリ別に整理</strong><p>オンの場合、エントリはカテゴリのサブフォルダ（<code>entries/workouts/</code>、<code>entries/symptoms/</code>）に保存されます。オフの場合、すべてのエントリが1つのフラットなフォルダに保存されます。</p></div>
</div>

## ファイル名テンプレート
<p>デフォルト：<code>{date}_{time}_{metric}</code>。使用できるプレースホルダ：<code>{date}</code>、<code>{time}</code>、<code>{metric}</code>、<code>{category}</code>。出力例：</p>

<div class="doc-diagram folder-tree" aria-label="個別エントリのファイルツリー例">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>

<p>正規のソースに基づくエントリでは、設定したファイル名の末尾に、選択した指標と小文字のHealthKit UUIDが追加されます。これにより、再実行しても同じソースレコードのパスが安定し、同じ分に発生したイベントの名前衝突を防げます。UUIDのない互換エントリでは、従来の短いファイル名の動作が維持されます。</p>

<div class="callout">
<strong>注意</strong>
<p style="margin-top:6px;"><em>ヘルス指標</em>で1つ以上の指標を有効にしたカテゴリだけが、ここに表示されます。まずそちらで指標を有効にしてから、個別エントリとしてトラッキングするかを選択してください。パスを前提とした自動化を構築する前に、<a href="/ja/docs/reference/individual-entry-tracking/">ソースレコードの同一性に関するコントラクト</a>と、生成された<a href="/ja/docs/reference/generated/individual/filename-path-matrix/">ファイル名マトリクス</a>を確認してください。</p>
</div>

## 関連項目

<div class="related">
  <a href="/ja/docs/metrics/"><span>前提</span>ヘルス指標 — 先に指標を有効にします。</a>
  <a href="/ja/docs/format/"><span>出力</span>形式 — エントリファイルにも適用されます。</a>
  <a href="/ja/docs/daily-notes/"><span>別の方法</span>デイリーノートへの挿入 — 指標をノートに関連付ける別の方法です。</a>
  <a href="/ja/docs/reference/individual-entry-tracking/"><span>コントラクト</span>個別エントリリファレンス — UUIDによる同一性、frontmatter、特殊エントリ、互換性フォールバック。</a>
</div>
