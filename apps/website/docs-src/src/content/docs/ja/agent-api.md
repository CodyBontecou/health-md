---
title: "ループバッククエリAPI"
description: "HTTPまたは低レベルのhealthmd agentコマンドを使い、Health.mdのバージョン管理されたローカルクエリ、エビデンス、更新、準備状況、指標、永続ジョブの各ルートを呼び出します。"
---

Health.md for Macは、`/v1/agent/`以下でバージョン管理されたローカルAPIを公開します。このAPIは、暗号化コンテキストへのクエリ、エビデンスパケット、リクエスト単位で範囲を限定したiPhoneからの取得、準備状況、永続取得ジョブを提供します。

APIはポート`17645`のループバックにバインドされ、検証済みのIPv4またはIPv6ループバックピアだけを受け入れます。

<div class="callout">
<strong>このポートを外部に公開しないでください</strong>
<p style="margin-top:6px;">Bearerトークン、呼び出し元の登録、アクセスプロファイル、権限データベースはありません。ループバックへ到達できること自体が、認証境界のすべてです。Health.mdが開いている間は、どのローカルプロセスからでもリクエストを送信できます。</p>
</div>

## ルート

| メソッド | ルート | 用途 |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | バージョン管理されたスキーマ、対応スコープ、ページ上限を一覧表示 |
| `GET` | `/v1/agent/metrics` | クエリ可能な正規メトリックID、カテゴリ、単位、要件を返す |
| `GET` | `/v1/agent/readiness` | 暗号化コンテキストとiPhoneからの新規取得の準備状況、および次に必要な操作を返す |
| `POST` | `/v1/agent/query` | 上限を設定した型付きクエリを1ページ実行 |
| `POST` | `/v1/agent/evidence` | 事実に基づくエビデンスパケットを上限付きで1ページ生成 |
| `POST` | `/v1/agent/refresh` | 明示したスコープをiPhoneから取得し、Macの暗号化コンテキストへ格納 |
| `GET` | `/v1/agent/jobs/{id}` | ローカルの永続取得ジョブを確認 |
| `POST` | `/v1/agent/jobs/{id}/resume` | 変更不能な取得リクエストを再開 |
| `POST` | `/v1/agent/jobs/{id}/cancel` | 明示的なキャンセルを要求 |

廃止された`/v1/agent/profiles`および`/v1/agent/activity/query`ルートは、`410 removed_endpoint`を返します。

iPhone直接接続バックエンドは、これらのHTTPルートをホストしません。スタンドアロンの`healthmd`コマンドは、正規抽出とエクスポートにこのバックエンドを使用します。一方、`healthmd mcp serve`は、iPhoneクエリプロトコルv3を介し、新規の型付きクエリ、エビデンス、指標カタログ、準備状況、可視化、永続エクスポートの各ツールを直接実装します。ペアリングとMCPは同じ実行ファイルIDを使用します。更新とMacの暗号化コンテキストは、このHTTP API固有の機能です。

## CLIアダプターを優先する

低レベルCLIはリクエスト本文をそのまま保ち、ループバック転送のエラーも処理します。

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

`--json JSON`は、小さな本文で`--input`の代わりに使用できます。CLIが、これらのコマンドに渡したJSONの範囲を暗黙に広げたり狭めたりすることはありません。

通常のワークフローでは、`healthmd query`、`healthmd sleep sessions`、`healthmd compare`などの高レベルコマンドを使用してください。セレクターを検証し、型付き操作を自動で組み立てます。

## クエリ本文

`POST /v1/agent/query`がトップレベルで受け入れるのは、`request`と任意の`detail_level`だけです。

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

未知のラッパーフィールドは拒否されます。クエリリクエストのコントラクトでは、指標、ソース、日付、操作、ページ制御を定義します。`detail_level`には`summary`または`lossless`を指定します。

レスポンスは`healthmd.query_response` v1です。型付き項目、カバレッジ、エビデンス、ソース記述子、制限事項、任意の`next_cursor`が含まれます。

完全な合成レスポンスは、[`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json)で確認できます。

## カーソルの続きを取得する

次のページを要求するには、意味的に同一のリクエストを送信し、返されたカーソルを`page.cursor`に指定します。

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

`next_cursor`がなくなるまでたどります。カーソルは認証され、リクエストと暗号化コーパスのリビジョンに紐づきます。Health.mdは、変更されたカーソル、リクエストと一致しないカーソル、古くなったカーソルを拒否します。

ページ上限は、履歴全体や結果全体に上限を設けることなく、各リクエストのリソース使用量を制限します。

## エビデンス本文

`POST /v1/agent/evidence`は同じラッパーを使用します。操作は`derive_packet`で、パケット種別と明示的に選択した詳細を指定します。

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

レスポンスはページ分割されたクエリレスポンスのままで、`healthmd.evidence_packet` v1のフラグメントを含みます。各事実には型付き値とエビデンスが含まれます。パケットには、事実の観測だけを扱うという制限事項も記載されます。

完全な合成レスポンスは、[`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json)で確認できます。

## 更新本文

更新で取得するのは、明示したスコープだけです。本文では、日付、指標、ソース、詳細レベル、上限付きの待機タイムアウトを指定できます。

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Macは現在のカタログに照らしてスコープを検証し、変更不能な正規選択へ変換します。iPhoneが読み取るのは、選択した通常のHealthKitタイプだけです。リクエスト単位の設定によって、iPhoneに保存済みのエクスポート設定が変わることはありません。

更新では専用の`encrypted_context`転送モードを使用します。

- エクスポートファイルを書き込みません。
- ファイルエクスポートの利用枠を消費しません。
- 上限付きで再開可能なパーティションを転送します。
- Macは決定論的なコンパクト所有者日を、確認応答の前にそれぞれコミットします。
- 正確なリクエストが永続ジョブとともに保持されます。

プロバイダだけを対象とするスコープでは、Apple Healthを読み取る必要はありません。プロバイダ固有の履歴はプロバイダ固有のエビデンスのまま保持され、合成したApple Health指標へ変換されることはありません。

## 利用可能なすべての項目を選択する

指標と日付のセレクターには`all_available`を指定できます。

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

iPhoneは、選択したApple Healthレコードのうち最も古い利用可能な日付から今日まで、ソースの各暦日を解決します。プロバイダからの取得では、プロバイダ固有の履歴カーソルをたどります。解決した識別子は転送前に固定されるため、再開時にリクエストの範囲が変わることはありません。

日付や結果に固定上限はありません。パーティション、ページ、1日単位の復号、ディスク容量、上限付きの待機時間によってリソースを制限します。

## 永続取得ジョブ

更新の待機処理がタイムアウトしても、ジョブは続行できます。レスポンスにはジョブIDと、安全に表示できる進捗が含まれます。

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

ジョブは作成から7日後に期限切れになります。再開時には、同じリクエスト、Mac、iPhone、ソーススコープ、コミット済みの進行地点を再利用します。

キャンセルが終端状態になるのは、iPhoneが確認応答した後だけです。iPhoneを利用できない場合、ジョブがキャンセル保留状態のままになることがあります。

## HTTPを直接呼び出す

CLIの使用を推奨しますが、ローカルソフトウェアからHTTPを直接呼び出すこともできます。

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

リスナーは、ヘッダーとJSON本文の上限、明示的なメソッドとコンテンツタイプ、受信期限、制限時間内に完了するリクエスト処理を適用します。

HTTPを直接呼び出すクライアントは、同じMac上で使用してください。LANへのバインド、プロキシ、トンネル、リモートHTTP MCPラッパーを追加しないでください。

## 型付き値と欠損

クエリ結果では、型と単位が保持されます。値には、数量、期間、件数、文字列、カテゴリ、真偽値、タイムスタンプ、暦日、ネストした配列、将来追加される未知の型付き値を使用できます。

欠損ステータスには、完全だが空、一部完了、失敗、未対応、スキップ、キャンセル、未要求、レガシーでは利用不可、編集済み、未同期があります。利用側は、これらをゼロへ変換してはいけません。

カバレッジには、要求範囲と利用可能範囲、対象日数、値がある日数、ステータス付きの欠損期間を圧縮した一覧が含まれます。

## エラー処理

エラーには`healthmd.query_error` v1を使用し、安定したコード、メッセージ、再試行可能かどうか、型付きの詳細を含めます。次のエラーは区別されます。

- 無効なページ制御
- 不正または改ざんされたカーソル
- カーソルとクエリの不一致
- 古くなったコーパスリビジョン
- 無効な日付範囲
- 指標またはソースの検証エラー
- 単位または集計の不一致
- 未対応の操作
- エビデンスのスコープ違反
- iPhoneまたは暗号化ストアの準備状況
- 永続ジョブの状態

結果が不明な更新を、状態確認なしに再試行しないでください。先にジョブの状態を確認します。

## 関連項目

<div class="related">
  <a href="/ja/docs/agents/"><span>概要</span>ローカルエージェントとヘルスコンテキスト：設定、暗号化ストレージ、スコープ、レポート規則。</a>
  <a href="/ja/docs/agent-queries/"><span>高レベル</span>型付きクエリの実例：一般的な指標、睡眠、ワークアウト、エビデンスの質問に使える検証済みコマンド。</a>
  <a href="/ja/docs/mcp/"><span>ツール</span>ローカルMCPサーバー：stdio設定、型付きツール、ページング、サンドボックスの制限。</a>
  <a href="/ja/docs/reference/api-and-cli/"><span>リファレンス</span>APIとCLIのコントラクト：エクスポート、抽出、クエリ、直接接続バックエンド、運用上の制限。</a>
  <a href="/ja/docs/reference/evidence-packets/"><span>データコントラクト</span>コンパクトクエリとエビデンスパケット：型、カーソル、操作、決定論的なパケットID。</a>
</div>
