---
title: "形式のカスタマイズ"
description: "収集する内容を変更せずに出力形式を調整します。ファイル形式、日付／時刻／単位の表記を選び、YAML frontmatterをカスタマイズして、Markdownテンプレートを指定できます。"
---

## 出力形式
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>デフォルトです。1日あたり1ファイルを生成します。YAML frontmatter（任意）と、カテゴリごとに見出しのあるセクションで構成されます。</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Obsidianの<a href="https://help.obsidian.md/Plugins/Bases">Bases</a>プラグイン向けに最適化された、構造化frontmatter付きのMarkdownです。数値プロパティは数値、日付は日付として保持されます。</p></div>
<div class="option"><strong>JSON</strong><p>1日あたり1つのJSONファイルを生成します。ロスレスヘルスレコードが有効な場合、Appleスキーマv8の日次サマリーに、正規の<code>healthmd.healthkit_records</code> v1アーカイブを埋め込むことができます。</p></div>
<div class="option"><strong>CSV</strong><p>1日あたり1つのCSVファイルを、ヘッダー<code>Date,Category,Metric,Value,Unit,Timestamp</code>で生成します。互換性サマリー行は5つのフィールドを含み、timestamp列を省略します。timestamp付きの行と正規レコード行は、6つすべてのフィールドを含みます。</p></div>
</div>

<div class="callout">
<strong>正確な仕様が必要ですか？</strong>
<p style="margin-top:6px;">本番実装に基づく<a href="/ja/docs/reference/export-formats/">形式リファレンス</a>、<a href="/ja/docs/reference/generated/core/csv-row-contracts/">CSV行の仕様</a>、完全なダウンロード可能フィクスチャを参照してください。</p>
</div>

## 日付と時刻
<p>日付形式（例：<code>YYYY-MM-DD</code>、<code>MMM d, yyyy</code>）と時刻形式（12時間制、24時間制）のピッカーがあります。設定を変更すると、画面下部のプレビューブロックがリアルタイムに更新されます。</p>

## 単位系
<p><em>メートル法</em>と<em>ヤード・ポンド法</em>を切り替えます。距離（m/kmとft/mi）、体重（kgとlb）、温度（°Cと°F）などに影響します。HealthKitでは常に標準単位で保存され、エクスポート時に変換されます。</p>

## frontmatterフィールド
<p><em>フロントマターフィールド</em>をタップすると、専用エディタが開きます。</p>
<ul>
<li>組み込みフィールド（date、weekday、totalStepsなど）を個別にオン／オフにする</li>
<li>フィールド名を変更する — Obsidianの設定で別のキーが必要な場合に便利です</li>
<li>静的な値を持つカスタムフィールドを追加する（例：<code>type: health</code>）</li>
<li>エクスポート時に展開されるプレースホルダーフィールドを追加する（例：<code>weather: {weather}</code>）</li>
</ul>

## Markdownテンプレート
<p><em>Markdownテンプレート</em>をタップするとテンプレートエディタが開きます。複数の組み込みスタイル（Compact、Sections、Detailed）と、完全なカスタムモードがあります。プレビューブロックには、当日のデータを使用した結果が表示されます。</p>

## プレビュー
<p>「形式」画面の下部にあるライブプレビューブロックでは、現在の設定を使って当日のデータを表示します。設定をすばやく調整するには、項目を変更してプレビューを確認する操作を繰り返します。</p>

## データ詳細とプロファイル

概要はコンパクトな日次プロジェクションを生成します。詳細な時系列は、指標が対応する場合にAppleとAndroidで選択したサンプルと区間を追加します。ロスレスヘルスレコードは正規HealthKitアーカイブを追加するApple限定機能で、Android互換レイヤーではありません。

詳細レベルは[エクスポートプロファイル](/ja/docs/export-profiles/)と一緒に固定されます。有効なプロファイルで変更しても、そのプロファイルだけが変わります。

## 関連項目

<div class="related">
  <a href="/ja/docs/export-profiles/"><span>プロファイル</span>ワークフローごとに詳細レベルと形式を保存します。</a>
  <a href="/ja/docs/metrics/"><span>対象</span>ヘルス指標 — まずデータを選択します。</a>
  <a href="/ja/docs/individual-tracking/"><span>詳細</span>個別トラッキング — エントリごとのファイルを生成する、別の出力方法です。</a>
  <a href="/ja/docs/daily-notes/"><span>Obsidian</span>デイリーノートへの挿入 — 同じfrontmatterフィールドを使用します。</a>
  <a href="/ja/docs/reference/export-formats/"><span>仕様</span>エクスポート形式 — JSON、CSV、Markdown、Basesの正確な動作を確認します。</a>
</div>
