---
title: "10分でエージェントを接続"
description: "リリース済みのHealth.md Mac用MCPヘルパーをCodexまたはClaudeに接続し、iPhoneから1つの明示的なスコープを取得して、範囲を限定したクエリを実行し、完全性を安全に確認します。"
---

<div class="availability available">
<strong>提供中 · Health.md for Mac</strong>
<p>この手順は、リリース済みMacアプリに同梱される署名済み<code>healthmd-mcp</code>ヘルパーを使います。ポータブルCLIプレビュー、Direct CLI Access、ペアリング用QRコード、ポート17647は使用しません。</p>
</div>

ローカルMCPホストを接続し、ヘルスデータの値を読まずに準備状況を確認し、iPhoneから小さなスコープを1つ明示的に更新して、その暗号化されたMacコンテキストを照会します。両方のアプリがすでにインストール済みで同じローカルネットワーク上にある場合、所要時間は約10分です。

## 1. Health.mdをインストールして開く

MacとiPhoneの両方で[App StoreからHealth.mdをダウンロード](https://apps.apple.com/us/app/health-md/id6757763969)し、両方のアプリを開きます。

HealthKitはiPhoneにとどまります。Macアプリは署名済みMCPヘルパーと、破棄可能な暗号化クエリコンテキストをホストします。HealthKitを直接読み取ることはありません。

## 2. iPhoneとMacを接続する

1. MacではHealth.mdを開いたままにします。
2. iPhoneで**Health.md → 同期**を開き、Mac接続を有効にします。
3. 両方のデバイスを同じ到達可能なローカルネットワークに置き、新しい処理を開始する間はHealth.mdをiPhoneで前面に保ちます。
4. Macアプリが意図したiPhone接続を表示していることを確認します。表示されない場合は、両方のアプリを開き直して、[Mac同期の準備状況](/ja/docs/sync/)を確認します。

これはリリース済みのMac接続です。`healthmd direct pair`を実行しないでください。このコマンドは、別個のポータブルプレビューに属します。

## 3. 署名済みヘルパーのパスをコピーする

**Health.md for Mac → CLI**を開き、表示されたMCPヘルパーのパスをコピーします。通常の`/Applications`インストールでは次を使います:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

別の場所にインストールしている場合は、表示されたパスを使用します。ヘルパーは直接設定してください。シェルでラップしたり、対話型コマンドとして起動したりしないでください。

## 4. CodexまたはClaudeを設定する

### Codex

`~/.codex/config.toml`に次を追加します。必要に応じてヘルパーのパスを置き換えます:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

ファイルを保存した後、Codexを再起動します。

### Claude DesktopまたはClaude Code

このローカルstdioエントリを、Claude DesktopのMCP設定または信頼済みのClaude Code `.mcp.json`に追加します:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

Claude Desktopを再起動するか、Claude Codeのワークスペースを信頼してサーバーを承認します。更新、エクスポート、再開、キャンセルの各操作では、承認プロンプトを有効なままにしてください。

## 5. 準備状況を確認する

`healthmd_doctor`を呼び出します。ヘルスデータの値を読まずに、準備状況だけを確認します。

準備完了の結果には次のフィールドが含まれます:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

完全な結果には、チェック項目と次のアクションも含まれます。続行する前に、ブロックしているチェックをすべて解決してください。接続済みのヘルパーは、暗号化コンテキストが最新であることの**証明にはなりません**。

次に`healthmd_metrics`を呼び出し、リクエストする予定の正規メトリックIDと単位を確認します。このウォークスルーでは`steps`を例としてのみ使います。

## 6. 小さなスコープを1つ明示的に更新する

実際に必要な日付を解決してから、両端を含む正確な範囲で`healthmd_refresh`を呼び出します。この例では1日分のサマリーデータを要求します:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

引数を確認し、取得を承認し、両方のアプリを開いたままにします。更新はエクスポートファイルを書き込まず、iPhoneに保存済みのエクスポート設定も変更しません。ジョブが終端状態に達するまで、返された`job_id`を保持してください。

## 7. 最初の範囲限定クエリを実行する

更新が完了したら、同じ日付、メトリック、ソース選択、詳細レベルで`healthmd_metric_chart`を呼び出します:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true`は、ヘルパーの集計ページ数およびバイト数の上限の範囲内でのみ、不透明なカーソルを走査します。睡眠については、正規抽出の代用ではなく`healthmd_sleep_sessions`を呼び出してください。

## 8. 回答する前に完全性を確認する

ツールの成功を、ヘルスデータの完全なカバレッジの証拠として扱わないでください。次のすべてを確認します:

- 更新が、同じ正確な日付、メトリック、ソース、詳細レベルで成功した終端状態に達したこと;
- レスポンスのスキーマとバージョンが認識可能であること;
- 要求した範囲とタイムゾーンが質問に一致していること;
- 示された各値が正規メトリックIDと単位を保持していること;
- カバレッジステータス、考慮日数、値のある日数、およびすべての欠損期間が報告されていること;
- `complete_empty`、`partial`、`failed`、`unsupported`、`skipped`、`cancelled`がゼロに変換されないこと;
- 走査が完了しているか、残ったカーソルや集計上限が開示されていること;
- エビデンス／ソース記述子と制限事項が回答に付いたままであること;
- 事実の観測が、診断、治療の助言、因果関係、「良い／悪い」という評価へ変換されないこと。

### 有用なデータを捨てずに部分結果を読む

型付きクエリは、要求したスコープの一部だけが完了した状態でも、有効な`healthmd.query_response`を返すことがあります。生成済みの[部分クエリレスポンスフィクスチャ](/docs/reference/generated/automation/agent-query-response-partial.json)は、利用可能なSteps項目を保持し、失敗した日を別々に報告します:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

上の`items`と`limitations`内の文字列は説明用の省略形です。正確なフィールドとエビデンスには、ダウンロード可能な生成済みフィクスチャを使用してください。保持された項目、失敗した期間、カバレッジ件数、制限事項をまとめて保持します。

`status: "partial_success"`を`healthmd.query_response`に追加しないでください。このステータスは、取得、走査、ファイル生成が不完全なときの、上位レベルのCLIおよびエクスポートのエンベロープに属します。タイムアウトはまた別です。これは結果が不明な永続ジョブであり、ジョブIDで確認する必要があります。

構造化された失敗は、部分レスポンスではなく`healthmd.query_error` v1を使います。安定したコード、メッセージ、再試行可能性、型付き詳細を含む生成済みの本番形式については、[agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json)を確認してください。

## 9. タイムアウトから安全に復旧する

タイムアウト、ホストの終了、MCP待機処理のキャンセルは、承認済みの更新をキャンセルしません。

1. 返された`job_id`を保持します。
2. そのIDで`healthmd_job_status`を呼び出します。
3. 変更不能なジョブが再開可能な場合は、同じIDと有限の待機タイムアウトで`healthmd_job_resume`を確認して承認します。
4. ステータスによって、承認済みジョブがもう完了しないことが証明された後でのみ、新しい更新を開始します。
5. `healthmd_job_cancel`は、ジョブを終了させる意思があるときだけ使用します。キャンセルは、iPhoneが確認応答した後のみ終端状態になります。

結果が不明なまま、決して盲目的に再試行しないでください。永続更新ジョブは、承認済みスコープとコミット済みの進行地点を保持します。

## 接続されました

doctorが準備完了になり、明示的な更新が終端状態に達し、範囲限定クエリの走査が完了し、カバレッジ、エビデンス、単位、制限事項を確認した時点で、最初の読み取り専用ワークフローは完了です。

生成ファイルのエクスポートは、承認が必要な別のワークフローです。リリース済みMacツールは、Health.md for Macで既に選択されているフォルダへ書き込みます。任意の保存先引数は受け付けません。

<div class="related">
  <a href="/ja/docs/mcp/"><span>ツールカタログ</span>リリース済みMacツール全体、正確なスキーマ、MCP Apps、ページング、安全境界を確認。</a>
  <a href="/ja/docs/configuration/"><span>その他のクライアント</span>リリース済みMac統合と、明確に示されたポータブルプレビューのどちらかを選択。</a>
  <a href="/ja/docs/agent-queries/"><span>次の質問</span>型付きのメトリック、睡眠、ワークアウト、比較、カバレッジ、エビデンスのワークフローを実行。</a>
  <a href="/ja/docs/agents/"><span>信頼モデル</span>暗号化コンテキスト、リクエストスコープ、保持期間、エビデンス、報告ルールを理解。</a>
</div>
