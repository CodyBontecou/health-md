---
title: "エクスポート"
description: "「エクスポート」タブは主要な操作画面です。HealthKitとVaultの接続状態を確認し、保存先を選択して、指定した日付範囲の1回限りのエクスポートを実行できます。"
---

<p>「エクスポート」タブは、3つの簡単な判断で操作できるよう構成されています。準備状態を確認し、保存先を選び、日付範囲を指定してからプレビューまたはエクスポートを行います。</p>

## ステータスバッジを確認する
<div class="options">
<div class="option"><strong>Healthバッジ</strong><p>緑の点＝HealthKitへのアクセスが許可済み、赤い点＝未許可です。タップするとiOSの権限シートを再表示します（インストール後の初回だけ機能します。それ以降はiOS上で何も起こらないため、「設定」→「プライバシーとセキュリティ」→「ヘルスケア」で変更する必要があります）。</p></div>
<div class="option"><strong>Vaultバッジ</strong><p>緑の点＝Vaultフォルダが選択済みです。タップするとVaultを再選択または変更できます。ラベルにはフォルダ名が表示されます。</p></div>
</div>
<p>HealthKit、出力形式、選択した保存先の準備が整うまで、<em>エクスポート</em>操作は無効のままです。これにより、保存先を指定せずにエクスポートしようとする最も一般的な問題を防ぎます。</p>

## エクスポート先を選択する
<p>「エクスポート先」カードで、データの送信先を指定します。</p>

<div class="options">
<div class="option"><strong>iPhone内のローカルフォルダ</strong><p>このデバイスで選択したフォルダまたはObsidian Vaultに直接書き込みます。</p></div>
<div class="option"><strong>接続中のMac</strong><p>取得した日次データと設定の正確なスナップショットを、近くにあるMacアプリへ送信します。iPhoneがHealthKitを読み取り、Macが選択された形式を生成してファイルを書き込みます。</p></div>
<div class="option"><strong>APIエンドポイント</strong><p>ユーザーが設定したHTTP(S)エンドポイントへ、iPhoneからJSONエンベロープを直接POSTします。<a href="/ja/docs/api-endpoint/">APIエンドポイントを参照</a>してください。</p></div>
</div>

## 日付範囲を選択する
<p>一般的な用途に対応する日付プリセットがあります。</p>

<div class="options">
<div class="option"><strong>今日</strong><p>当日分をエクスポートします。出力形式のテストに便利です。</p></div>
<div class="option"><strong>昨日</strong><p>1日分のデータが完了しているため、日次エクスポートでは最も安全な選択肢です。</p></div>
<div class="option"><strong>全期間</strong><p>Health.mdが検出できる最も古いHealthKitデータからバックフィルします。</p></div>
<div class="option"><strong>カスタム</strong><p>特定の期間について、開始日と終了日を選択します。</p></div>
</div>

## プレビューまたはエクスポート
<div class="options">
<div class="option"><strong>プレビュー</strong><p>何も書き込まずに、生成予定のファイルと内容を表示します。</p></div>
<div class="option"><strong>エクスポート</strong><p>エクスポートを実行し、メイン画面に進行状況を表示して、結果を履歴に記録します。</p></div>
</div>

## 「エクスポート」で実際に行われること
<ol>
<li>範囲内の各日について、選択したサマリープロジェクションを取得します。「ロスレスヘルスレコード」が有効な場合は、対応する正規ソースレコードとクエリ診断も取得します。</li>
<li>選択した形式（Markdown、Bases、JSON、CSV）とテンプレートを適用します。</li>
<li><code>{vault}/{subfolder}/</code>に1日あたり1ファイルを書き込むか、接続中のMacワークフローを通じてファイルを転送するか、バージョン付きJSONエンベロープをAPIエンドポイントへPOSTします。</li>
<li><em>個別トラッキング</em>が有効な場合、ファイルベースのエクスポート先について、選択したエントリごとのMarkdownファイルを正規アーカイブから生成します。</li>
<li><em>デイリーノートへの挿入</em>が有効な場合、選択したサマリーフィールドをデイリーノートに統合します。</li>
</ol>

<p>JSONとCSVでは正規レコードを保持できます。MarkdownとBasesは読みやすさを保ち、アーカイブを埋め込む代わりに、簡潔な取得診断を表示します。正確なスキーマと省略ルールについては、<a href="/ja/docs/reference/">完全なエクスポートリファレンス</a>を参照してください。</p>

## タブバー

<p>画面下部にある「エクスポート」、「スケジュール」、「同期」、「設定」の4つのタブで、アプリのすべての機能を操作できます。その他の項目はすべて、「設定」内の1階層または2階層下にあります。</p>

<div class="callout">
<strong>ロック解除後の動作</strong>
<p style="margin-top:6px;">Full Accessを利用すると、エクスポートの実行回数が無制限になり、スケジュールエクスポート、Macへのエクスポート、ショートカットも利用できます。詳細は<a href="/ja/docs/paywall/">ペイウォールのページ</a>を参照してください。</p>
</div>

## 関連項目

<div class="related">
  <a href="/ja/docs/scheduling/"><span>日常的な利用</span>スケジュール — 自動化して、今後「エクスポート」をタップする必要がないようにします。</a>
  <a href="/ja/docs/api-endpoint/"><span>連携</span>APIエンドポイント — 選択したJSONを独自のサービスへ直接送信します。</a>
  <a href="/ja/docs/format/"><span>カスタマイズ</span>形式のカスタマイズ — 各ファイルの表示方法を変更します。</a>
  <a href="/ja/docs/shortcuts/"><span>高度な操作</span>ショートカット — Siri、自動化、ほかのアプリからエクスポートを実行します。</a>
  <a href="/ja/docs/reference/"><span>リファレンス</span>エクスポートリファレンス — スキーマ、正規レコード、診断、生成例を確認します。</a>
</div>
