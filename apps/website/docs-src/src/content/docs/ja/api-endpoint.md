---
title: "APIエンドポイント"
description: "選択したApple HealthのJSONを、iPhoneから独自のHTTP(S)エンドポイントへ直接送信します。"
---

<p>APIエンドポイントは、Health.mdのデータを独自のサーバー、Webhook、データベース、ダッシュボード、または自動処理へ送信したいユーザー向けのエクスポート先です。Apple Healthの読み取りは引き続きiPhoneで行われますが、ファイルへ書き込む代わりに、設定したエンドポイントへJSONをPOSTします。</p>

<div class="callout">
<strong>プライバシーに関する注意</strong>
<p style="margin-top:6px;">この出力先を使用すると、選択したヘルスデータが入力したURLへ意図的に送信されます。ご自身が管理または信頼するエンドポイントを使用し、HTTPSを優先して、サービスが実際に必要とする指標だけに限定してください。</p>
</div>

## 出力先を設定する

<ol>
<li>iPhoneでHealth.mdを開きます。</li>
<li><strong>エクスポート</strong>に移動します。</li>
<li><strong>エクスポート先</strong>で<strong>APIエンドポイント</strong>を選択します。</li>
<li><code>https://api.example.com/healthmd/ingest</code>のようなURLを入力します。</li>
<li>任意でBearerトークンを入力します。Health.mdはトークンをキーチェーンに保存します。</li>
<li><strong>完了</strong>をタップし、日付範囲と指標を選択してから<strong>エクスポート</strong>をタップします。</li>
</ol>

<p>通常のトークンを入力した場合、Health.mdは<code>Authorization: Bearer &lt;token&gt;</code>として送信します。値がすでに<code>Bearer </code>または<code>Basic </code>で始まっている場合は、入力どおりに送信します。</p>

## ペイロードの構造

<p>Health.mdは、エクスポート操作ごとに1回POSTします。本文は、独立してバージョン管理された<code>healthmd.api_export</code>エンベロープで、公開スキーマv7の<code>healthmd.health_data</code>日次レコードを含みます。APIエンベロープv1は日次レコードを格納します。v2では、日次レコードのスキーマを変更せずに、プロバイダのサイドカーも追加できます。</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>リクエストした範囲について保持された、完全な日次スキーマv7オブジェクトです。クエリマニフェストがエビデンスとなる、完全だが空のレコードも含みます。</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>日次ドキュメントを保持できる前に処理が失敗した日付です。</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p><code>records</code>内の日次スキーマのバージョンです。APIエンベロープのバージョンとは独立して更新されます。</p></div>
<div class="option"><strong>プロバイダサイドカー</strong><p>接続済みプロバイダが有効な場合に含まれる、独自のスキーマと識別規則を持つ条件付きのv2外部レコードです。</p></div>
</div>

<p>本番環境で生成された完全な<a href="/docs/reference/generated/automation/api-export-v1.json">API v1エンベロープ</a>と<a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">API v2プロバイダサイドカーエンベロープ</a>を確認できます。<a href="/ja/docs/reference/api-and-cli/">APIとCLIのコントラクト</a>には、すべてのフィールド、バージョン境界、受け入れ規則が記載されています。</p>

## エンドポイントの要件

<div class="options">
<div class="option"><strong>メソッド</strong><p><code>POST</code>を受け入れます。</p></div>
<div class="option"><strong>コンテンツタイプ</strong><p><code>application/json</code>を受け入れます。</p></div>
<div class="option"><strong>成功</strong><p>ペイロードを安全に受け入れた後、いずれかの<code>2xx</code>ステータスを返します。</p></div>
<div class="option"><strong>失敗</strong><p>リクエストを拒否する場合は<code>4xx</code>または<code>5xx</code>を返します。利用可能な場合、Health.mdはレスポンスの短いプレビューを表示します。</p></div>
</div>

<p>確実に取り込めるよう、エンドポイントを日付単位で冪等にしてください。指標を変更した後やサーバーエラーを修正した後に、ユーザーが同じエクスポート範囲を再実行することがあります。</p>

## ヒント

<ul>
<li>長期間のバックフィルをアップロードする前に、1日分でテストしてください。</li>
<li>ソースの完全性が重要な場合は「ロスレスヘルスレコード」を有効にしたままにしてください。経路、臨床文書、心電図、添付ファイルが多い場合は日付範囲を短くします。</li>
<li>ペイロードを保存する前に、サーバー側でトークンを検証してください。</li>
<li>日単位の主キーには<code>records[].date</code>を使用してください。</li>
<li>簡潔なエラー本文を返してください。Health.mdが表示するのは短いプレビューだけです。</li>
</ul>

## トラブルシューティング

| 問題 | 通常考えられる原因 | 対処方法 |
|---|---|---|
| API出力先を使用できない | URLが空か無効 | APIエンドポイントの設定を開き直し、有効なHTTP(S) URLを入力します。 |
| HTTP 401または403 | トークンがないか拒否された | トークンまたはサーバーの認証規則を更新します。 |
| HTTP 404 | URLパスが誤っている | サーバー上のルートを確認します。 |
| HTTP 413 | ペイロードが大きすぎる | エクスポートする日数を減らします。受信側が正規ソースレコードを必要としない場合に限り、サマリーのみの出力を使用します。 |
| 一部の日付がない | その日付について有効なHealthKitデータがない | <code>failed_date_details</code>と指標の選択を確認します。 |

## 関連ページ

<div class="related">
  <a href="/ja/docs/export/"><span>ソース</span>エクスポート — 出力先と日付範囲を選択し、手動エクスポートを実行します。</a>
  <a href="/ja/docs/reference/api-and-cli/"><span>スキーマ</span>APIとCLIのリファレンス — 正確なエンベロープ、バージョン、失敗時の動作、生成済みの例を確認します。</a>
  <a href="/ja/docs/format/"><span>出力</span>形式のカスタマイズ — JSON、CSV、Markdown、単位、フィールドを設定します。</a>
</div>
