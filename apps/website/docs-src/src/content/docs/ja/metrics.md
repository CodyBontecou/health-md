---
title: "ヘルス指標"
description: "Health.mdが現在対応しているApple Health指標カタログから選択します。検索、カテゴリ全体の一括切り替え、指標ごとの詳細な制御が可能です。"
---

<div class="callout">
<strong>Androidに関する注意</strong>
<p style="margin-top:6px;">このページでは、Apple Healthの指標選択画面と、生成されたHealthKitデータリファレンスについて説明します。Androidアプリでは106個のHealth Connect指標を利用できます。Health Connectの設定とプラットフォーム固有の動作については、<a href="/ja/docs/android/">Androidガイド</a>をご覧ください。</p>
</div>

## レイアウト
<div class="options">
<div class="option"><strong>件数ヘッダー</strong><p>有効な指標とカテゴリの数をリアルタイムで表示します。長押しすると、正確な選択状態をクリップボードにコピーできます。</p></div>
<div class="option"><strong>すべての指標を有効化</strong><p>すべてのカテゴリを一括でオンまたはオフにするマスタートグルです。まずすべてをオンにしてから、不要なものを無効にする使い方に便利です。</p></div>
<div class="option"><strong>検索</strong><p>指標名と識別子をリアルタイムで絞り込みます。「heart」「sleep」「vo2」などを試してください。</p></div>
</div>

## カテゴリ
<p>選択画面では、通常のサマリーとソースレコード定義が、睡眠、アクティビティ、心臓、呼吸、バイタル、身体測定、モビリティ、サイクリング、栄養、マインドフルネス、リプロダクティブヘルス、症状、服薬、特殊レコード、ワークアウトなどのカテゴリに分類されています。各行にはオン／オフ状態と、そのカテゴリ内で有効になっている定義数がリアルタイムで表示されます。本番環境から生成された<a href="/ja/docs/reference/generated/core/metric-catalog/">指標カタログ</a>が、現在の正規一覧です。</p>

<p>カテゴリをタップすると、そのカテゴリの指標を詳しく確認できます。各指標には個別のトグルとHealthKit識別子があります。ドットの色は、このデバイスのHealthKitにその指標のデータが現在存在するかどうかを示します。</p>

## 選択の適用範囲
<p>指標の選択は、<em>すべて</em>に反映されます。</p>
<ul>
<li>日次エクスポート — 有効な指標だけがファイルに含まれます</li>
<li>個別トラッキング — 有効な指標だけにエントリごとのファイルが作成されます</li>
<li>デイリーノートへの挿入 — 有効な指標だけがfrontmatterにマージされます</li>
<li>ショートカット — 日付範囲のエクスポートでも同じ選択が使われます</li>
</ul>

<div class="callout">
<strong>ヒント</strong>
<p style="margin-top:6px;">最初は対象を絞りましょう。睡眠、アクティビティ、心臓を有効にして、エクスポートを実行し、ファイルの内容を確認します。その後でカテゴリを追加してください。不要な指標が並ぶ50行のファイルから整理するより、必要なものを後から追加するほうが効率的です。</p>
</div>

## 関連項目

<div class="related">
  <a href="/ja/docs/reference/"><span>リファレンス</span>エクスポートリファレンス — Apple Healthの全指標、キー、単位、ソースレコード定義、エクスポート構造。</a>
  <a href="/ja/docs/android/"><span>Android</span>Androidアプリ — Health Connectの設定、指標、出力先、自動化。</a>
  <a href="/ja/docs/format/"><span>方法</span>形式 — 選択した指標のエクスポート方法を変更します。</a>
  <a href="/ja/docs/individual-tracking/"><span>詳細</span>個別トラッキング — タイムスタンプ付きエントリごとにファイルも作成します。</a>
  <a href="/ja/docs/daily-notes/"><span>Obsidian</span>デイリーノートへの挿入 — これらの指標をデイリーノートに追加します。</a>
</div>
