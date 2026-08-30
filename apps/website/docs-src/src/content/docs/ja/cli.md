---
title: "Health.md CLI"
description: "Macアプリまたはスマートフォン直接接続バックエンドを選択し、healthmdをiPhoneまたはAndroidデバイスとペアリングして、準備状況の確認、ファイルのエクスポート、正規Apple Healthデータの抽出、型付きクエリ、永続ジョブの自動化を行います。"
---

`healthmd`コマンドには2つの動作モードがあります。暗号化されたローカルクエリ、MCPツール、Health.md for Macで選択済みの保存先フォルダを使用する場合は、Macアプリのバックエンドを選びます。Macアプリを起動せずに生データや生成ファイルを取得する場合は、スマートフォン直接接続バックエンドを選びます。直接接続モードは、iPhone（プロトコルv1）またはAndroid（プロトコルv2）で開いているHealth.mdアプリとペアリングします。

<div class="callout">
<strong>ヘルスデータはスマートフォン内にとどまります</strong>
<p style="margin-top:6px;">どちらのCLIバックエンドも、コンピューターからApple HealthやHealth Connectを読み取ることはありません。新しいプラットフォームのヘルスデータを読み取るのは、そのたびに開いているiPhoneまたはAndroidのHealth.mdアプリです。CLIが受け取るのは、検証済みの結果またはファイルです。</p>
</div>

## バックエンドを選ぶ

| 機能 | Macアプリのバックエンド | スマートフォン直接接続バックエンド |
|---|---|---|
| 同梱Macヘルパーの既定値 | はい | いいえ。`--backend direct`で選択 |
| 接続先デバイス | iPhone | iPhone（プロトコルv1）またはAndroid（プロトコルv2） |
| Health.md for Macを開く必要がある | はい | いいえ |
| 新しいデータの取得時にスマートフォン版Health.mdアプリを開く必要がある | はい | はい |
| ファイル保存先 | Macアプリで選択したフォルダ | 既存の絶対パス`--destination` |
| 厳密な生データエクスポート | 対応 | 対応。AndroidではプロバイダネイティブなHealth Connectスナップショット |
| 正規`healthmd extract` | 対応 | iPhoneのみ |
| 暗号化コンテキスト、型付きクエリ、エビデンス | 対応 | iPhoneのみ（ポータブルクライアント） |
| `healthmd-mcp` | 対応 | 非対応 |
| Manual IPまたはTailscale | Mac同期または明示的な直接接続モード | 対応 |
| Nearby直接転送 | 同梱のSwiftヘルパーのみ | ポータブルRustクライアントでは非対応 |

バックエンドと転送方式が暗黙に切り替わることはありません。直接接続コマンドが、クエリを実行するためにMacアプリへ切り替わることはなく、Nearby接続の失敗時にManual IPへ切り替わることもありません。

## 同梱Macヘルパーをインストールする

<div class="availability available">
<strong>提供中 · Health.md for Mac</strong>
<p>署名済みのSwift CLIヘルパーとMCPヘルパーは、リリース済みのMacアプリに同梱されています。</p>
</div>

Health.md for Macには、署名済みの`healthmd`ヘルパーと`healthmd-mcp`ヘルパーが含まれています。Macアプリを開いて**CLI**を選択すると、インストール済みアプリのパス、設定コマンド、エージェント用プロンプト、任意のエージェントスキルインストーラーを確認できます。

通常のアプリバンドル内のパスは次のとおりです。

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

1回のシェルセッションだけで使用する場合は、エイリアスを設定します。

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

ユーザーが所有するbinディレクトリに永続的なシンボリックリンクを作成することもできます。

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

シェルにまだ含まれていなければ、`~/.local/bin`を`PATH`へ追加します。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

MCPのstdioループを開始せずにCLIを確認します。

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor`は、Mac、暗号化コンテキスト、iPhoneの準備状況を含む`healthmd.cli_doctor` JSONを返します。ヘルスデータの値は出力しません。

## ポータブルCLIの提供状況

<div class="availability preview">
<strong>プレビュー · 公開パッケージは未提供</strong>
<p>クロスプラットフォームのRust CLIは、実機iPhoneでのリリースQAと、最初の品質確認済みパッケージの公開を待っています。</p>
</div>

スタンドアロンのRust CLIは、`0.1.0-alpha.1`として開発中です。macOS、Linux、Windowsで動作し、既定ではManual IPまたはTailscaleによる直接接続を使用するため、Macアプリは不要です。プロトコルv1でiPhoneソースと、プロトコルv2でAndroidソースとペアリングし、Swift↔RustとKotlin↔Rustの自動互換性ゲートを備えています。プロトコル互換性は実装済みですが、最初の公開リリースまでに、実機デバイスでのリリースQAと公開パッケージの準備を完了する必要があります。

リリースされるまでは、同梱のMacヘルパーを使用してください。未公開のHomebrew、crates.io、GitHubインストーラー、ダウンロードURLに依存しないでください。

ポータブルクライアントは、iPhoneとAndroidの両方のソースについて、3つのデスクトッププラットフォームすべてで、ペアリング、status、生データエクスポート、生成ファイルの保存先、resume、cancelに対応します。正規抽出と型付きMCPクエリはiPhoneの機能です。Androidの生スナップショットはHealthKit形式のデータへ変換されず、プロバイダネイティブなHealth Connectコントラクトを維持します。Androidの型付きクエリは未実装です。生成ファイルのエクスポートでは、スマートフォンは保存先を不透明な対象ラベルとして扱い、受信側CLIがホストのファイルシステム上で検証し、永続的に紐づけます。Androidプロトコルv2は、すべてのCLIオペレーティングシステムでファイル保存先をコミットし、各生成ジョブの上限は4,096ファイルです。iOSプロトコルv1はWindows上でファイル保存先を拒否します。

## コマンド一覧

| コマンド | 用途 | バックエンド |
|---|---|---|
| `healthmd status` | リアルタイムの準備状況またはローカル永続ジョブ1件を確認 | 両方 |
| `healthmd doctor` | Mac、暗号化コンテキスト、iPhoneの準備状況を説明 | Macアプリ |
| `healthmd metrics list` | クエリ可能な正規指標カタログを返す | Macアプリ |
| `healthmd extract` | 選択した正規`healthmd.health_data`オブジェクトを取得 | 両方（iPhoneソース） |
| `healthmd query` | 選択した型付き指標を取得して照会 | Macアプリ |
| `healthmd sleep sessions` | 第1級オブジェクトの睡眠セッションと固定時間枠を返す | Macアプリ |
| `healthmd training align` | ワークアウトを前後の睡眠セッションと対応付け | Macアプリ |
| `healthmd workouts` | エビデンス付きの型付きワークアウトを一覧表示 | Macアプリ |
| `healthmd coverage` | 日付や指標のカバレッジまたは欠損を確認 | Macアプリ |
| `healthmd compare` | 呼び出し元が選択した集計方法で正確な期間を比較 | Macアプリ |
| `healthmd evidence training` | 事実に基づくトレーニングエビデンスパケットを構築 | Macアプリ |
| `healthmd export` | 生成ファイルを書き込むか、厳密な生のJSONを返す | 両方 |
| `healthmd resume` | 変更不能な永続エクスポートジョブを再開 | 両方 |
| `healthmd cancel` | 明示的なキャンセルを要求 | 両方 |
| `healthmd agent ...` | 低レベルのループバッククエリAPIとジョブAPIを呼び出す | Macアプリ |
| `healthmd direct ...` | スマートフォン直接接続の信頼情報をペアリング、一覧表示、削除 | 直接接続 |

直接接続コマンドは、iPhone（プロトコルv1）またはAndroid（プロトコルv2）のソースとペアリングします。正規`extract`とすべての型付きクエリコマンドはiPhoneの機能です。Androidの直接接続バックエンドは、プロバイダネイティブなHealth Connectの生スナップショットと生成ファイルを返します。

## 最初のMacアプリワークフロー

1. MacでHealth.mdを開き、ファイルを書き込む場合は保存先フォルダを選択します。
2. ペアリング済みのiPhoneでHealth.mdを開き、Macへ接続されるまで待ちます。
3. 準備状況を確認します。
4. 大規模な履歴を要求する前に、小さなコマンドを実行します。

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

新規クエリが取得するのは、指定した指標、ソース、日付、サマリーまたはロスレスの詳細だけです。iPhoneに保存済みのエクスポート設定は変更しません。

## ファイルエクスポートと生データエクスポート

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

# Run a saved export profile by UUID (frozen settings + destination)
healthmd export --iphone --last 7 --profile 11111111-2222-4333-8444-555555555555
```

`--profile PROFILE_ID` は、保存されたエクスポートプロファイルをその安定した UUID で iPhone 上で解決します。実行では、アプリの現在の設定ではなく、そのプロファイルの凍結されたメトリック選択・フォーマット・保存先が使われます。`--use-iphone-settings` やメトリック/カテゴリセレクターとの併用はできず（プロファイルが設定スコープを所有します）、不明な UUID は型付きの `profile_not_found` エラーで失敗し、現在の設定へフォールバックすることはありません。UUID はアプリの「エクスポート」タブのプロファイル選択で確認してください。

現在、暦日数に上限はありません。`--all`は、選択したソースレコードのうち最も古い利用可能なものをiPhoneに検出させ、解決した範囲を固定して、上限付きのパーティションで処理します。利用可能なストレージと、極端にデータ量の多い1日が実用上の制限になります。

`--raw`は、iPhoneの設定を変更せず、一時的に正規のロスレスソースレコードを要求します。生成ファイルを書き込まず、接続済みプロバイダのサイドカーも含みません。

## 正規抽出と派生クエリの使い分け

ソースに近い形式のデータが必要な場合は、`extract`を使用します。

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

型付きでエビデンスに紐づくビューが必要な場合は、クエリコマンドを使用します。

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7が公開ソースコントラクトです。クエリ、エビデンス、ジョブ、レシートの各スキーマは、転送または派生ビューを記述します。ソーススキーマを置き換えるものではありません。正規抽出はiPhoneの機能です。Androidの直接接続ソースでは、代わりに生データエクスポートを通じてプロバイダネイティブなHealth Connectスナップショットが提供されます。

## 機械可読動作

コマンドは既定で、バージョン管理されたJSONを標準出力または明示した`--output`パスへ書き込みます。正規抽出ではJSONLを選択でき、高レベルクエリでは意図的に非可逆な表形式を選択できます。ヘルスデータを含まない進捗は標準エラー出力へ書き込まれる場合があります。`--help`は平文です。コマンド開始前の引数エラーは、標準エラー出力に平文で出力され、終了コードは2です。

プロセスの終了が成功しただけでは、ヘルスデータが完全だと証明できません。次の項目を確認してください。

- 外側のstatus
- 要求スコープのstatus
- 日ごと、クエリごとの結果
- 欠損期間
- `next_cursor`または走査レシート
- ソーススキーマとバージョン
- 制限事項と警告

完全だが空の結果は、Health.mdが要求スコープを表現し、観測値が見つからなかったことを意味します。ゼロ、欠損、失敗、スキップ、未対応とは異なります。

## 安全な自動化

自動化ホスト側でプロセスのタイムアウトを設定し、プロンプトを表示しないコマンドでは標準入力を閉じてください。GNU `timeout`を使用できるシステムでは、次のように実行します。

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

タイムアウト、Ctrl-C、プロセス終了、ネットワーク切断、iOSバックグラウンド実行時間の終了によって、永続ジョブがキャンセルされることはありません。重複する処理を開始せず、ジョブIDを確認して再開してください。

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

iPhoneの確認応答があった場合にだけ、キャンセルが終端状態になります。

## プライバシー規則

生データ出力とロスレス出力には、正確なタイムスタンプ、経路、臨床レコード、服薬、気分の記録、心電図の値、出所、添付ファイルが含まれる場合があります。ターミナルへの出力よりも、出力ファイルを使用してください。ペイロードをIssue、エージェントのトランスクリプト、CIログ、シェルトレースへ貼り付けないでください。

ローカルクエリAPIには、Bearerトークン、登録、アクセスプロファイル、権限データベースがありません。ループバックへ到達できること自体が、アクセス境界のすべてです。Macアプリが開いている間は、どのローカルプロセスからでも使用できます。ポート`17645`を別のマシンへプロキシまたは公開しないでください。

## 次のガイド

<div class="related">
  <a href="/ja/docs/cli-direct/"><span>Macアプリ不要</span>スマートフォン直接接続CLI：iPhoneまたはAndroidとペアリングし、転送方式、生データとファイルのエクスポート、バックグラウンド動作、対応プラットフォームを確認します。</a>
  <a href="/ja/docs/cli-extract/"><span>ソースデータ</span>正規抽出：指標、オブジェクト、詳細、JSON Pointer、JSONL、レシートを選択。</a>
  <a href="/ja/docs/cli-jobs/"><span>自動化</span>永続ジョブ：タイムアウト、再開、キャンセル、部分的な結果、安全なスクリプト処理。</a>
  <a href="/ja/docs/agents/"><span>エージェント</span>ローカルエージェントのワークフロー：暗号化コンテキスト、直接指定するスコープ、型付きコマンド、エビデンス。</a>
  <a href="/ja/docs/mcp/"><span>MCP</span>サンドボックス化されたstdioヘルパーを設定し、ツール境界を確認します。</a>
  <a href="/ja/docs/reference/api-and-cli/"><span>コントラクト</span>APIとCLIのリファレンス：正確なルート、スキーマ、レスポンス、生成済みフィクスチャ。</a>
</div>
