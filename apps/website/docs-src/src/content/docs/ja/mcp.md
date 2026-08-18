---
title: "Health.md MCPサーバーとApp"
description: "ローカルでサンドボックス化されたMCP Appを介し、CodexまたはClaudeから範囲を限定したApple Health分析、ネイティブチャートの表示、永続Health.mdエクスポートの開始を行います。"
---

Health.md for Macには、署名済みの`healthmd-mcp` stdioヘルパーが同梱されています。Codex、ClaudeなどのMCPホストから、事実に基づくApple Healthデータの照会、可視化、暗号化されたローカルコンテキストの更新、開いているMacアプリを介した承認済み永続エクスポートを実行できます。

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>提供中 · Health.md for Mac</strong>
<p>同梱サーバーは、仕様が固定された21個のツールを公開します。サーバー自身がHealthKit、エクスポートフォルダ、セキュリティスコープ付きブックマーク、任意のファイルを読み取ることはありません。</p>
</div>

<div class="availability preview">
<strong>プレビュー · ポータブル直接接続MCP</strong>
<p>macOS、Linux、Windows向けの別構成である19ツール版<code>healthmd mcp serve</code>は実装済みですが、まだ公開パッケージはありません。クラウドを使わない<code>serve-read-only</code>エントリは、ローカルでのペアリング後、準備状況とクエリに関する13個のツールだけを公開します。このページにあるポータブル版専用コマンドには、プレビューと明記しています。</p>
</div>

## 要件

- Health.md for Macがインストール済みで開いていること
- 更新ツールまたはエクスポートが新しいHealthKit処理を開始するときは、接続済みのiPhoneでHealth.mdを開いていること
- stdioに対応するローカルMCPホスト
- **Health.md for Mac → CLI**に表示される署名済みヘルパーのパス

通常のヘルパーパスは`/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`です。対応するMCPコアプロトコルのバージョンは、`2024-11-05`、`2025-03-26`、`2025-06-18`、`2025-11-25`です。`healthmd-mcp`を通常の対話型コマンドとして起動しないでください。標準入力とプロセスのライフサイクルはMCPホストが管理します。

## Codexの設定

同梱ヘルパーを`~/.codex/config.toml`へ追加します。

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

Codexを再起動し、`healthmd_doctor`を呼び出して、`healthmd_metrics`でIDを解決します。更新ツールで小さな正確なスコープを明示的に取得してから、そのスコープを`healthmd_metric_chart`で照会します。対話型MCP Appsに対応していないホストでも、正確なJSONと標準PNGチャートを受け取れます。

## Claudeの設定

Claude DesktopのMCP設定、または信頼済みのClaude Code `.mcp.json`で、次のローカルstdioエントリを使用します。

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

設定を編集した後、Claude Desktopを再起動します。Claudeのプロジェクト設定では、ワークスペースの信頼と明示的なサーバー承認が必要です。

安定版のMCP Apps拡張を通知するClaude Desktopのバージョンでは、Health.mdの対話型ビューがインラインで表示されます。Claude Codeなどのテキスト中心のクライアントでも、JSONと画像のフォールバックが維持されます。

## ポータブル直接接続MCPのプレビュー

スタンドアロン版の公開後は、`healthmd setup codex`によって前面表示中のiPhoneをペアリングし、同じバイナリの`healthmd mcp serve`エントリを安全に作成できるようになります。この構成では、ポート`17647`上の認証済みで暗号化されたManual IPまたはTailscale転送、ネイティブの認証情報ストレージ、リクエストごとに明示するiPhoneからの読み取りを使用します。Linuxでは、ロック解除済みのSecret Serviceプロバイダも必要です。WindowsではCredential Managerを使用します。

`healthmd-cli/v<version>`リリースが提供されるまでは、未公開のパッケージやインストーラーURLに依存しないでください。段階的なペアリングと転送のコントラクトについては、[iPhone直接接続CLI](/ja/docs/cli-direct/)を参照してください。

## ネイティブMCP Appの可視化

Health.mdは、安定版`io.modelcontextprotocol/ui`ネゴシエーションを`text/html;profile=mcp-app`で実装しています。

ホストがこのMIMEタイプに対応していることを通知すると、サーバーは次を公開します。

- `ui://healthmd/query-visualization-v1`
- 標準の`resources/list`メソッドと`resources/read`メソッド
- 分析ツールとエクスポートレシートツール上の`_meta.ui.resourceUri`
- 正確なJSONテキストとともに、検証済みの`structuredContent`

ビューは自己完結型のHTML5リソースで、ネットワーク、リモートスクリプト、リモートフォント、ストレージ、ネストしたフレームを使用しません。宣言されたCSPのconnect/resource/frame/baseドメインリストは空です。標準の初期化、ツール結果、テーマ、サイズ変更、キャンセル、終了の各ライフサイクルに従います。

次の内容を表示できます。

- 単位と明示的な欠損データの空白を含む指標折れ線チャート
- 呼び出し元が選択した集計方法による期間比較
- 睡眠セッションと睡眠段階の時間サマリー
- ワークアウトと、事実に基づくワークアウト／睡眠の時間関係
- カバレッジ、欠損期間、エビデンス、制限事項
- 全ページ走査のレシート
- 永続エクスポートの進捗、保存先、ジョブレシート

ホストがMCP Appsに対応していない場合でも、ツールは動作します。`healthmd_metric_chart`は完全なJSONをテキストとして維持しながら、画像対応ホスト向けに`image/png`コンテンツを追加します。

## 利用可能なツール

同梱Macサーバーは、準備状況／クエリ用13個、生成ファイルジョブ用4個、暗号化コンテキスト更新ジョブ用4個の計21個の固定ツールを公開します。19ツールのポータブル版プレビューは、準備状況／クエリ用13個とエクスポート用4個を維持し、Mac更新ジョブを直接ペアリング用2ツールに置き換え、前面表示中のiPhoneで型付きクエリを直接実行します。

### 準備状況と検出

| ツール | 用途 |
|---|---|
| `healthmd_status` | Macアプリ、コンテキスト、iPhone、エクスポートの準備状況を確認 |
| `healthmd_doctor` | 同梱ヘルパーとMacループバック構成を診断 |
| `healthmd_capabilities` | 直接クエリ、エビデンス、エクスポート、スキーマ、ページング機能を一覧表示 |
| `healthmd_metrics` | 正規メトリックID、カテゴリ、単位、要件を一覧表示 |

### 分析と可視化

| ツール | 用途 |
|---|---|
| `healthmd_metric_chart` | 指標時系列を照会し、カバレッジと単位を含むネイティブチャートを表示 |
| `healthmd_sleep_sessions` | 安定した睡眠セッションと生理学的データのカバレッジを一覧表示・可視化 |
| `healthmd_training_alignment` | ワークアウトと前後の睡眠との事実に基づく時間関係を表示 |
| `healthmd_workouts` | ワークアウトを一覧表示・可視化 |
| `healthmd_coverage` | 指標／日付のカバレッジと欠損を確認 |
| `healthmd_compare_periods` | 集計方法を明示して正確な期間を比較 |
| `healthmd_training_evidence` | 事実に基づくトレーニングエビデンスパケットを作成 |
| `healthmd_query` | 正確な`healthmd.query_request`を送信し、任意でページを走査 |
| `healthmd_evidence_packet` | 正確なエビデンスリクエストを送信し、任意でページを走査 |

### 生成ファイルのエクスポート

| ツール | 用途 |
|---|---|
| `healthmd_export_files` | Macアプリを介し、選択済みフォルダへ永続エクスポートを実行 |
| `healthmd_export_job_status` | エクスポートの進捗と保存先レシートを確認 |
| `healthmd_export_job_resume` | 変更不能な永続エクスポートジョブをそのまま再開 |
| `healthmd_export_job_cancel` | エクスポートジョブを明示的にキャンセル |

エクスポート、再開、キャンセルのツールには、破壊的な書き込みの可能性があることを示すマークが付きます。設定されたエクスポートモードによって生成ファイルが更新または上書きされる場合があるため、現在のClaudeホストでは明示的な操作が必要です。上記のCodex設定では、追加の安全策として、これらのツールを使うときに確認を求めます。

### 暗号化コンテキスト取得ジョブ · 同梱Mac版のみ

| ツール | 用途 |
|---|---|
| `healthmd_refresh` | 承認済みのスコープをiPhoneから取得し、破棄可能なMacの暗号化コンテキストへ格納 |
| `healthmd_job_status` | ヘルスデータの値を読み取らず、更新の進捗を確認 |
| `healthmd_job_resume` | 受け入れ済みの更新ジョブをそのまま再開 |
| `healthmd_job_cancel` | 受け入れ済みの更新ジョブを明示的にキャンセル |

### 完全なクエリ形式を確認する

MCPの`tools/list`には、日付、指標、ソース、ページング、期間の範囲、集計、高度な`healthmd.query_request`について、ネストした完全なJSON Schemaが含まれます。型付きツールには具体例も含まれます。エージェントは汎用のシェルヘルプを調べるのではなく、対応する型付きツールを直接呼び出してください。特に、睡眠に関する質問では`healthmd_sleep_sessions`を使用します。`healthmd extract`が生成するのは、別の正規ソースデータプロジェクションです。

ポータブル版プレビューでは、ネットワークリスナーを開いたりiPhoneへ接続したりせず、同じスキーマをローカルで確認できます。公開済みMacヘルパーではMCPのtools/listを使用します。

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

最小限の睡眠呼び出しは、次の形式です。実際のリクエストに合わせて、両端を含む日付を解決してください。

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

正規睡眠指標とロスレスのセッション詳細は、`healthmd_sleep_sessions`によって自動的に指定されます。

## データを分析してチャートを表示する

最初に`healthmd_doctor`を呼び出し、`healthmd_metrics`でメトリックIDを解決します。公開済みMacトポロジーでは、型付きクエリツールは暗号化されたMacコンテキストを読み取り、暗黙にiPhoneへ接続しません。現在のデータが必要な場合は、日付、メトリック、ソースを明示して更新ツールを呼び出し、永続ジョブの完了を待ってから、同じスコープのチャートを作成します。

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

このオブジェクトを`healthmd_metric_chart`へ渡します。対話型ビューでは、単位の安全性を保つスモールマルチプルを使用します。欠損または部分的な点は、ゼロへ変換せず線を途切れさせます。

公開済みMacの型付きツールは、暗号化されたローカルコンテキストを評価し、カバレッジ、欠損、エビデンス、制限事項を含む上限付きページを返します。接続済みで前面表示中のiPhoneへ接続し、要求したコンテキストスコープを置き換えるのは、明示的な更新だけです。ポータブル版プレビューでは、各型付きリクエストをペアリング済みで前面表示中のiPhone上で直接評価します。

## 生成ファイルをエクスポートする

最初にHealth.md for Macで書き込み可能な保存先フォルダを選択し、その選択を保持します。ホストが引数全体を表示し、ユーザーが承認した後で、`healthmd_export_files`を呼び出します。

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

全履歴には、`date_selection: "all_available"`を`date_range`なしで使用します。任意の`metric_ids`、`categories`、`all_metrics`で、保存済み設定を変更せずにiPhoneでの取得範囲を狭められます。`detail_level`は、これらの選択項目のいずれかがある場合だけ適用されます。`all_metrics`は、明示的な指標リストやカテゴリリストと併用できません。

代わりに保存されたエクスポートプロファイルを実行するには、`settings_policy` を `"profile"` に設定し、プロファイルの安定した UUID を持つ `profile_reference` を渡します（省略可能な表示用 `name` はエラー時の記録専用です）:

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" }
}
```

プロファイルが設定スコープを所有します: `profile_reference` は `metric_ids`、`categories`、`all_metrics`、保存設定ポリシーと組み合わせることはできず、不明な UUID は型付きエラーで失敗し、現在の設定へフォールバックしません。

次の項目を確認します。

- `status`と永続的な`state`
- `job_id`
- 処理済み日数／総日数と進捗
- 書き込まれたファイルまたはデイリーノート
- 検証済みのデスクトップ保存先
- コミット済みパーティションとバイト数
- 一時停止／失敗の理由と有効期限

タイムアウトやMCPの待機処理終了によって、永続ジョブがキャンセルされることはありません。結果が不明なまま再開せず、先に`healthmd_export_job_status`を確認してください。明示的なキャンセルだけがジョブを終了させます。

生データや正規ソースの転送には、数GBに及ぶ経路、臨床テキスト、添付ファイル、ソースレコードが含まれる場合があります。Health.mdは、意図的にそれらの本文をMCPの会話へ含めません。ソースに近い形式の出力には、検証済みのストリーミングCLIを使用します。

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

MCP分析は派生した事実ビューです。生成ファイルのエクスポートでは、引き続き本番エクスポーターを通じて公開`healthmd.health_data`コントラクトを使用します。

## ページングと完全性

クエリ／エビデンスツールは、対応する箇所で`all_pages: true`を公開します。ヘルパーは、循環検出と全体のバイト数／ページ数上限を適用しながら不透明なカーソルをたどり、バージョン管理された各レスポンスを`healthmd.mcp_query_pages` v1の下に保持します。自動走査の上限に達した場合、成功した部分的ラッパーは`receipt.traversal_complete`を`false`に設定し、欠損なく続行するための正確な`receipt.next_cursor`を返します。iPhoneは、ページ分割されたコンパクトスナップショットを、前面表示中に操作がない状態で10分間保持し、走査の完了時またはバックグラウンド移行時に消去します。1回のリクエストには、366,000日とエンコード後64 MiBのコンパクトコンテキスト上限があります。`query_scope_too_large`は、論理履歴を利用できないという意味ではありません。呼び出しを分けて日付またはメトリックIDを分割してください。ページは、欠損期間リストとソース記述子リストを制限し、明示的な件数／切り捨てフィールドと制限事項を含めます。

転送の成功は、完全性を意味しません。必ず次の項目を確認します。

- 要求スコープとコーパスのstatus
- カバレッジと欠損期間
- 制限事項とエビデンス
- `next_cursor`または走査レシート
- 無関係なスキップ
- ソーススキーマとバージョン

MCP Appは、これらのフィールドを隠さず表示します。自動走査が安全上限に達した場合は、スコープを狭めるか、手動で続行してください。

## セキュリティとプライバシーの境界

ヘルパーには、prompts、roots、sampling、shell、SQL、任意のファイル読み取り、任意のURL取得、HealthKitへの書き込み、ループバックHTTPサービス、リモートMCPエンドポイントがありません。唯一のMCPリソースは、同梱のAppドキュメントです。生成ファイルへの書き込みは、承認が必要な1つの固定操作です。公開済みMacヘルパーはHealth.md for Macで選択したフォルダを使用します。ポータブル版プレビューでは、明示した既存の保存先を転送前に検証し、永続的に紐づけます。

直接接続の信頼情報は、Keychain、Secret Service、Windows Credential Managerのいずれかに保存されます。ペアリングでは、既存の認証済み暗号化プロトコルを使用します。iPhoneは前面表示され、コンピューターのLANまたはTailscaleアドレスへ明示的に接続されている必要があります。クエリページは、ネゴシエーション済みのバイト数／項目数上限で制限され、全ページの自動集約には追加のバイト数／ページ数上限があります。上限のない生データ本文は、検証済みのストリーミングCLI経路にとどまります。

Health.mdは、単位、出所、カバレッジ、欠損を含む事実の観測を報告します。診断、治療の推奨、因果関係の推定、方向を良いまたは悪いと評価することはありません。

## トラブルシューティング

| 症状 | 対処方法 |
|---|---|
| ホストがヘルパーを起動できない | インストール済み`healthmd`または`.exe`の絶対パスと引数`mcp serve`を使用します。 |
| ターミナルで実行するとヘルパーが待機する | 正常な動作です。MCPホストが標準入力へJSON-RPCを送信する必要があります。 |
| `healthmd_not_paired` | `healthmd direct pair`を実行し、iPhoneでペアリングを完了します。 |
| `healthmd_unavailable` | iPhoneのロックを解除してHealth.mdを前面表示し、Direct CLI Accessを有効にして、コンピューターへ接続します。 |
| `query_scope_too_large` | 呼び出しを分けて日付またはメトリックIDを分割します。論理コーパスは複数のリクエストにわたり引き続き利用できます。 |
| 対話型チャートがない | ホストを更新します。サーバーは引き続き正確なJSONとPNG指標チャートのフォールバックを返します。 |
| エクスポート先を利用できない | Mac：Health.mdで保存済みフォルダを再選択します。ポータブル版プレビュー：既存の絶対パスで、シンボリックリンクではないデスクトップディレクトリを作成して渡します。 |
| エクスポートの待機処理がタイムアウトする | 再開する前に、IDを使って永続エクスポートジョブを確認します。 |
| 結果に`next_cursor`がある | `all_pages: true`を設定するか、手動でカーソルの続きを取得します。 |

## 関連項目

<div class="related">
  <a href="/ja/docs/agents/"><span>アーキテクチャ</span>ローカルエージェント、暗号化コンテキスト、リクエストスコープ、エビデンス。</a>
  <a href="/ja/docs/agent-queries/"><span>分析</span>指標、睡眠、ワークアウト、比較、カバレッジのための型付きクエリ実例。</a>
  <a href="/ja/docs/cli-extract/"><span>ソースデータ</span>ソースに近い大規模な結果を検証して正規抽出。</a>
  <a href="/ja/docs/reference/evidence-packets/"><span>コントラクト</span>型付き値、欠損、エビデンス、パケットID。</a>
</div>
