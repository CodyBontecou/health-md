---
title: "Health.md CLI"
description: "スタンドアロンのhealthmd CLIをmacOS、Linux、Windowsにインストールし、iPhoneまたはAndroidデバイスと直接ペアリングして、準備状況の確認、データのエクスポート、クエリ実行、永続ジョブの管理を行います。Macアプリは不要です。"
---

スタンドアロンの`healthmd` CLIはmacOS、Linux、Windowsで動作し、開いているiPhone（プロトコルv1）またはAndroid（プロトコルv2）のHealth.mdアプリと直接ペアリングします。Health.md for Macを一切必要とせず、バックエンド選択も存在せず、コンピューターからApple HealthやHealth Connectを読み取ることもありません。

<div class="callout">
<strong>ヘルスデータはスマートフォン内にとどまります</strong>
<p style="margin-top:6px;">CLIはコンピューターからApple HealthやHealth Connectを読み取りません。新しいプラットフォームのヘルスデータを読み取るのは、そのたびに開いているiPhoneまたはAndroidのHealth.mdアプリです。CLIが受け取るのは、検証済みの結果またはファイルです。</p>
</div>

## スタンドアロンCLIをインストールする

<div class="availability preview">
<strong>公開プレビュー · 認定済み安定版はまだ</strong>
<p>クロスプラットフォームのRust CLIは公開配布されていますが、正確なモバイルマトリクスは依然として物理リリース認定待ちです。</p>
</div>

macOSまたはLinuxでは、<code>brew install CodyBontecou/tap/healthmd</code>でプレビューをインストールします。リリースエビデンスに記載された正確なモバイルビルドを使用してください。パッケージの公開はモバイル互換性を証明しません。

スタンドアロンのRust CLIはmacOS、Linux、Windowsで動作し、Manual IPまたはTailscaleによる直接接続を使用し、Macアプリを必要としません。プロトコルv1でiPhoneソースと、プロトコルv2でAndroidソースとペアリングし、Swift↔RustおよびKotlin↔Rustの自動互換性ゲートを備えます。プロトコル互換性は実装済みですが、最初の認定済み安定版の前に物理デバイスのリリースQAを完了する必要があります。チェックサム付きアーカイブ、PowerShellインストーラー、`cargo install healthmd-cli --locked`が各リリースに付属します。

ポータブルクライアントは、iPhoneとAndroidについて、3つのデスクトッププラットフォームすべてでペアリング、ステータス、生データエクスポート、生成ファイルの保存先、再開、キャンセルをサポートします。正規抽出と型付きMCPクエリはiPhoneの機能です。Androidの生スナップショットは、HealthKit形式への変換ではなくプロバイダー固有のHealth Connect契約を維持します。Androidの型付きクエリは未実装です。生成ファイルのエクスポートでは、スマートフォンは保存先を不透明なラベルとして扱い、受信側CLIがホストのファイルシステム配下で検証して永続的に束縛します。Androidプロトコルv2はすべてのCLIオペレーティングシステムでファイル保存先を確定し、生成ジョブごとに4,096ファイルまでに制限します。

## コマンド一覧

| コマンド | 目的 |
|---|---|
| `healthmd status` | ライブの準備状況またはローカルの永続ジョブを確認 |
| `healthmd export` | 生成ファイルの書き出しまたは厳密な生データJSONの返却 |
| `healthmd extract` | 選択した正規`healthmd.health_data`オブジェクトの取得（iPhone） |
| `healthmd query` | 固定の型付きクエリ操作の実行（iPhone） |
| `healthmd resume` | 不変の永続エクスポートジョブを再開 |
| `healthmd cancel` | 明示的なキャンセルを要求 |
| `healthmd direct ...` | スマートフォンの直接信頼をペアリング・一覧・削除 |
| `healthmd mcp ...` | 固定MCPツール面の提供または確認 |
| `healthmd setup codex` | Codexの設定とiPhoneのペアリングを一括実行 |

ダイレクトコマンドはiPhone（プロトコルv1）またはAndroid（プロトコルv2）のソースとペアリングします。正規`extract`とすべての型付きクエリコマンドはiPhoneの機能で、Androidのダイレクトソースはプロバイダー固有のHealth Connect生スナップショットと生成ファイルを返します。

```bash
# 準備状況とローカルの信頼
healthmd status
healthmd direct devices

# プラットフォーム固有の生データエクスポート。--outputを省略すると検証済みJSON/NDJSONをstdoutへストリーム
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# MCPと同じ操作レジストリによる型付きクエリ（iPhone）
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# 範囲を指定した正規抽出（iPhone）
healthmd extract --category Sleep --last 7 --output sleep.json

# すべてのCLI OSでの本番生成ファイル
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# 永続操作
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### ポータブルCLIでのプロファイル別ファイル出力

スタンドアロンのダイレクトCLIは、対応する両スマートフォンプラットフォームで保存済みプロファイルを安定IDで解決できます。プロファイルは凍結された出力設定を提供し、コンピューターの保存先は引き続き明示します。

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID`は`--use-device-settings`やメトリック／カテゴリセレクターと併用できず、不明なIDはライブ設定を使用せずフェイルクローズします。IDはiPhoneまたはAndroidの**設定 → エクスポートプロファイル → プロファイルID**からコピーします。自動化と保存先の動作は[エクスポートプロファイル](/ja/docs/export-profiles/)を参照してください。

ポータブルダイレクトクライアントは、MCPラッパーなしで対応するiPhoneの型付き操作を呼び出せます。

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## 同梱Macヘルパー

Health.md for Macは、アプリ内に署名済みの独自Swiftヘルパー`healthmd`と`healthmd-mcp`を同梱します。このヘルパーはMacアプリの機能であって、スタンドアロンCLIのバックエンドではありません。既定では実行中のMacアプリのループバックサーバーと通信し、暗号化ローカルクエリ、MCPツール、Health.md for Macで選択済みの保存先フォルダを提供します。さらに`--backend direct`で選択できる互換ダイレクトiPhoneモードも備えます。2つのクライアントがモードを黙って切り替えることはありません。

<div class="availability available">
<strong>利用可能 · Health.md for Mac</strong>
<p>署名済みのSwift CLI・MCPヘルパーはリリース済みMacアプリに同梱されています。</p>
</div>

Macアプリを開いて**CLI**を選ぶと、インストール済みコピーのパス、セットアップコマンド、エージェントプロンプト、任意のエージェントスキールインストーラーを確認できます。

アプリバンドルの通常パスは次のとおりです。

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

1回のシェルセッションでエイリアスを使う場合：

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

または、ユーザー所有のbinディレクトリに永続的なシンボリックリンクを作成します。

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

シェルがまだ含めていない場合は`~/.local/bin`を`PATH`に追加します。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

MCPのstdioループを開始せずにヘルパーを検証します。

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor`は、Mac、暗号化コンテキスト、iPhoneの準備状況を含む`healthmd.cli_doctor` JSONを返します。ヘルス値は出力しません。

### 同梱ヘルパーのコマンド

| コマンド | 目的 |
|---|---|
| `healthmd export --iphone ...` | Macアプリ経由で生成ファイルの書き出しまたは厳密な生データJSONの返却 |
| `healthmd status` | Mac/iPhoneの準備状況または永続ジョブを確認 |
| `healthmd doctor` | Mac、暗号化コンテキスト、iPhoneの準備状況を説明 |
| `healthmd metrics list` | 正規クエリ可能メトリックカタログを返却 |
| `healthmd query` | 選択した型付きメトリックの取得とクエリ |
| `healthmd sleep sessions` | 第一級の睡眠セッションと固定ウィンドウを返却 |
| `healthmd training align` | ワークアウトを前後の睡眠に整合 |
| `healthmd workouts` | エビデンス付きの型付きワークアウトを一覧 |
| `healthmd coverage` | 日付・メトリックのカバレッジまたは欠落を確認 |
| `healthmd compare` | 呼び出し側が選ぶ集計で正確な期間を比較 |
| `healthmd evidence training` | 事実に基づくトレーニングエビデンスパケットを作成 |
| `healthmd resume` / `healthmd cancel` | 永続ジョブを管理 |
| `healthmd agent ...` | 低レベルのループバッククエリ／ジョブAPIを呼び出し |
| `healthmd --backend direct ...` | ヘルパーの互換ダイレクトiPhoneモード |

ヘルパーのダイレクトモードでは、Macコンテキストのquery、evidence、doctor、metrics、refreshサブコマンドはMacアプリへ切り替えるのではなく`backend_unsupported`を返します。

### 最初のMacアプリワークフロー

1. ファイルを書き出す予定がある場合は、MacでHealth.mdを開き保存先フォルダを選択します。
2. ペアリング済みiPhoneでHealth.mdを開き、Macとの接続を待ちます。
3. 準備状況を確認します。
4. 大きな履歴を要求する前に小さなコマンドを実行します。

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

新しいクエリは、指定されたメトリック、ソース、日付、要約またはロスレス詳細のみを取得します。iPhoneの保存済みエクスポート設定は変更しません。

### 同梱ヘルパーによるファイル・生データエクスポート

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings
```

現在のカレンダー日数上限はありません。`--all`はiPhoneに選択済みソースの最も古い利用可能なレコードを発見させ、解決済み範囲を固定し、境界付きパーティションで処理します。利用可能なストレージと異常に密度の高い1日が実際の限界です。

`--raw`はiPhoneの設定を変更せず、一時的に正規ロスレスソースレコードを要求します。生成ファイルは書き出さず、接続済みプロバイダーのサイドカーも含みません。

## 正規抽出と派生クエリの使い分け

ソース本来の形のデータが必要な場合は`extract`を使います。

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

型付きでエビデンスに紐づくビューが必要な場合はクエリコマンドを使います。スタンドアロンCLIは固定の型付き操作を提供し、同梱Macヘルパーは以下の高レベルシェルも提供します。

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8はAppleの公開ソース契約です。クエリ、エビデンス、ジョブ、レシートのスキーマは転送または派生ビューを記述し、ソーススキーマを置き換えません。正規抽出はiPhoneの機能で、Androidのダイレクトソースは代わりに生データエクスポートでプロバイダー固有のHealth Connectスナップショットを提供します。

## 機械可読動作

コマンドは既定でstdoutまたは明示的な`--output`パスにバージョン付きJSONを出力します。正規抽出はJSONLを選択でき、高レベルクエリは意図的に損失のあるテーブルを選択できます。ヘルス値を含まない進捗はstderrを使用できます。`--help`はプレーンテキストです。コマンド開始前の引数エラーは、終了コード2でstderrにプレーンテキストで出力されます。

プロセスの正常終了だけでは完全なヘルスデータを証明できません。次を確認してください。

- 外部ステータス。
- 要求スコープのステータス。
- 日別・クエリ別の結果。
- 欠落間隔。
- `next_cursor`またはトラバーサルレシート。
- ソースのスキーマとバージョン。
- 制限と警告。

完全に空の結果は、Health.mdが要求スコープを表現し観測を見つけなかったことを意味します。ゼロ、欠落、失敗、スキップ、未対応とは異なります。

## 安全な自動化

自動化ホストのプロセスタイムアウトを使用し、入力を求めないコマンドではstdinを閉じたままにします。GNU `timeout`のあるシステムでは次のようにします。

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

タイムアウト、Ctrl-C、プロセス終了、ネットワーク喪失、iOSバックグラウンド時間の使い切りは永続ジョブをキャンセルしません。ジョブIDを確認し、重複を開始せずに再開してください。

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

キャンセルが最終的になるのは、iPhoneが確認応答した場合のみです。

## プライバシー規則

生データおよびロスレス出力には、正確なタイムスタンプ、経路、臨床記録、投薬、気分記録、心電図値、来歴、添付ファイルが含まれる可能性があります。端末出力よりもファイル出力を優先してください。ペイロードを課題報告、エージェントトランスクリプト、CIログ、シェルトレースに貼り付けないでください。

同梱MacヘルパーのローカルクエリAPIには、ベアラートークン、登録、アクセスプロファイル、許可データベースがありません。ループバックの到達可能性がアクセス境界のすべてです。Macアプリが開いている間は任意のローカルプロセスが利用できるため、ポート`17645`をプロキシまたは他のマシンに公開しないでください。

## 次のガイド

<div class="related">
  <a href="/ja/docs/cli-direct/"><span>Macアプリ不要</span>ダイレクトフォンCLI：iPhoneまたはAndroidとのペアリング、転送方式、生データ・ファイルエクスポート、バックグラウンド動作、プラットフォーム対応。</a>
  <a href="/ja/docs/cli-extract/"><span>ソースデータ</span>正規抽出：メトリック、オブジェクト、詳細、JSONポインター、JSONL、レシートの選択。</a>
  <a href="/ja/docs/cli-jobs/"><span>自動化</span>永続ジョブ：タイムアウト、再開、キャンセル、部分結果、安全なスクリプティング。</a>
  <a href="/ja/docs/agents/"><span>エージェント</span>ローカルエージェントワークフロー：暗号化コンテキスト、ダイレクトスコープ、型付きコマンド、エビデンス。</a>
  <a href="/ja/docs/mcp/"><span>MCP</span>サンドボックス化されたstdioヘルパーを設定し、ツール境界を確認します。</a>
  <a href="/ja/docs/reference/api-and-cli/"><span>契約</span>APIとCLIのリファレンス：正確なルート、スキーマ、応答、生成フィクスチャ。</a>
</div>
