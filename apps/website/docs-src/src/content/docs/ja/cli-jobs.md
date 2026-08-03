---
title: "永続CLIジョブと自動化"
description: "機械可読出力、上限付きの待機、7日間保持される永続ジョブ、明示的な部分状態、再開、確認応答付きキャンセルを使い、healthmdを安全に自動化します。"
---

Health.mdは、接続を伴うエクスポートとコンテキスト取得の処理を永続ジョブとして扱います。ジョブの有効期間は、開始元のプロセスとは独立しています。ターミナルが閉じたりネットワーク接続に失敗したりしても、完了済みのパーティションは破棄されません。

コマンド側でより限定的な規則が記載されている場合を除き、このページはファイルエクスポート、厳密な生データエクスポート、正規抽出、新規の暗号化コンテキスト取得に適用されます。

## 最も重要な規則

タイムアウトや切断は、キャンセルを意味しません。

結果が不明なまま重複する処理を開始しないでください。返されたジョブIDを保存して状態を確認し、同じジョブを再開します。

export、raw、extractジョブでは、トップレベルのライフサイクルコマンドを使用します。

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

暗号化コンテキスト取得ジョブでは、ローカルエージェントのライフサイクルを使用します。

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## 7日間の有効期間

永続ジョブには、作成から7日後に固定された`expires_at`があります。進捗によって延長されることはありません。両方のピアが、変更不能なリクエストと、安全な再開に必要なコミット済み転送状態を保持します。

ジョブには次の情報を保持できます。

- 正確な日付、または全履歴から解決したID
- 指標、カテゴリ、ソース、詳細レベルのスコープ
- バックエンドとペアリング済みデバイスの紐付け
- 設定ポリシー
- 生データプロファイルまたは抽出の選択内容
- ファイル保存先のID
- リクエストフィンガープリント
- セッションと転送のマニフェスト
- パーティションのダイジェストチェーン
- コミット済みパーティションとバイト単位の進行地点
- 完了またはキャンセルの確認応答

再開時に、これらのフィールドを別の意味へ解釈し直すことはできません。

## 状態は実行中と完了だけではない

ジョブレスポンスには、次のフィールドが含まれる場合があります。

| フィールド | 意味 |
|---|---|
| `durable` | 復旧可能なジョブ状態があるか |
| `state` | 現在の永続ライフサイクル状態 |
| `job_id` | 安定したジョブID |
| `session_id` | 紐づけられた転送セッションID |
| `paused` | 同じiPhoneの再接続が必要か |
| `processed_days` / `total_days` | 論理所有者日の進捗 |
| `committed_partitions` | 受信側が永続的に確認応答したパーティション |
| `committed_bytes` | 安全にコミットされたペイロードのバイト数 |
| `fraction_complete` | ヘルスデータを含まない進捗率 |
| `expires_at` | 固定されたジョブの有効期限タイムスタンプ |

statusフィールドには、日付、ID、件数、バイト数、安全に表示できるエラーが含まれます。ヘルスデータのサンプルは含まれません。

## 明示的な出力計画でジョブを開始する

生データエクスポート：

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

正規抽出：

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

直接接続による生成ファイル：

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

リクエストを開始する前に、最終的な出力または保存先を決めてください。生データジョブは出力動作に紐づきます。直接ファイルジョブは、正確な保存先ルートを変更不能なリクエストに紐づけます。

## 再開

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

直接接続モードでは、元のリクエストと同じバックエンド、デバイス、転送方式、ポート、iPhoneを選択します。

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

切断後、保留中のバイトは破棄される場合があります。コミット済みのパーティションは、再転送も再解釈もされません。受信側がコミット済みのパーティションを受け入れるのは、変更不能な記述子がすべて一致する場合だけです。

ファイルジョブでは、再開時に別の保存先を指定できません。元のルートが変更されている場合、Health.mdは別のフォルダへ書き込まず、安全側に倒して失敗させます。

## キャンセル

ジョブの作成元と同じライフサイクルを使用します。

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

キャンセルには2つの段階があります。

1. CLIが永続的なキャンセル要求を記録して送信します。
2. iPhoneがキャンセルを確認応答し、終端状態にします。

iPhoneを利用できない場合、ジョブは`cancellation_pending`のままです。同じiPhoneを再度開き、cancelを再試行してください。ローカルでキャンセルする意思を記録しただけで、ジョブをキャンセル済みと報告してはいけません。

Ctrl-Cを受け取ったプロセスは、キャンセルが終端状態になったように装わず終了する必要があります。キャンセルする場合は、明示的なcancelコマンドを使用してください。

## 出力チャネル

Health.mdは、コマンド結果と進捗を分けて出力します。

| チャネル | 内容 |
|---|---|
| stdout | バージョン管理されたJSONのコマンド結果、エラー、または要求したJSON／JSONLストリーム |
| stderr | 平文のペアリング手順、ヘルスデータを含まない進捗、ストリーム時のJSONLレシート、使用方法 |
| `--output PATH` | アトミックにコミットされた、ヘルスデータを含むJSONまたはJSONL |
| `OUTPUT.receipt.json` | JSONLファイル出力用の、ヘルスデータを含まない抽出レシート |

`--help`は平文です。実行前の引数エラーは、標準エラー出力と終了コード2を使用します。コマンドの実行開始後に発生したランタイムエラーは、機械可読JSONを使用します。

自動化のパーサーで、標準出力と標準エラー出力を混在させないでください。

## 終了ステータスとデータステータス

プロセスの終了ステータスは、判断材料の1つにすぎません。成功と判断する前に、レスポンスを解析してください。

| 結果 | 既定の終了動作 |
|---|---|
| 完全に成功 | 0 |
| 要求スコープが完全だが空 | 0 |
| 検証済みだが部分的な厳密生データまたは抽出 | 0以外 |
| `--allow-partial`を明示した部分的な結果 | 0。ただしレスポンスは部分状態を維持 |
| 引数エラー | 終了コード2。標準エラー出力に平文 |
| 検証または転送の失敗 | 構造化されたランタイムエラーと0以外の終了コード |

`--allow-partial`は受け入れポリシーであり、データ修復ではありません。すべての欠損日、失敗したクエリ、未対応タイプ、警告がそのまま表示されます。

## ページ走査はジョブの完了とは別

型付きクエリのレスポンスはページ分割されます。新規取得ジョブが完了していても、クエリに次のページが残っている場合があります。

`--all-pages`を指定しない場合は、`next_cursor`を確認してください。次のページがある場合、高レベルCLIは全ページ取得済みと主張せず、`partial_success`を報告します。

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages`は不透明なカーソルをたどり、反復を確認して、全体のページ数とバイト数の上限を適用します。上限に達した場合は、スコープを狭めるか、低レベルAPIを使って手動でページを取得してください。結果総数に隠れた上限はありませんが、1回の呼び出しは常に制限されます。

## 新規取得、キャッシュ、カバレッジの再利用

高レベルクエリコマンドは、既定でiPhoneから新しいデータを取得します。

```bash
healthmd query --metric resting_heart_rate --last 30
```

古いコンテキストを許容できる場合に限り、キャッシュ済みデータを使用します。

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Health.mdが要求日の指標を考慮した完全なサマリーカバレッジを検証した後でだけ取得を省略するには、`--reuse-covered`を使用します。

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

カバレッジを再利用する短縮経路は、ロスレスデータや新しくプロジェクションされた睡眠セッション操作には適用されません。別のプロバイダや古いblobを、今回のリクエストが新規取得を完了した証拠として扱うこともありません。

## シェルの例

この例では、ヘルスデータのペイロードを保護されたファイルに保存し、安全なstatusフィールドだけを出力します。GNU `timeout`がインストールされていることを前提としています。ほかの自動化ホストでは、それぞれの方法でプロセス期限を設定してください。

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

ヘルスデータのJSONをストリームする可能性があるコマンドや、機密性の高いパスを含むコマンドの実行中に、`set -x`を有効にしないでください。

## 結果が不明な場合のエージェントの動作

エージェントまたはスケジューラーは、次の順序で対処してください。

1. 構造化されたエラーとジョブIDを読み取ります。
2. ローカルで`status --job`を実行します。
3. ジョブが一時停止中、終端状態、期限切れ、確認応答待ちのいずれかを確認します。
4. 新規処理または確認応答が必要な場合は、同じiPhoneを再度開きます。
5. 同じバックエンドとデバイスを使って、既存のジョブを再開します。
6. 前の結果が判明したか、期限切れを明示的に受け入れた後でだけ、新しいジョブを開始します。

結果が不明な変更操作を状態確認なしに再試行すると、ファイルのコミット自体が冪等でも、ソース側の処理が重複する可能性があります。

## 一般的な機械可読エラー

| コード | 意味 | 安全な対処 |
|---|---|---|
| `timed_out` | ジョブ完了前に、コマンドが待機を終了した | 返されたジョブを確認して再開する |
| `job_not_found` | そのIDに対応するローカル永続レコードがない | 最初からやり直す前に、バックエンドと状態ディレクトリを確認する |
| `job_expired` | 固定された7日間の期限を過ぎた | 欠落を記録し、必要に応じて新しいリクエストを作成する |
| `direct_export_paused` | 直接接続の処理に、ペアリング済みiPhoneが再び必要 | iPhoneを再度開いて再開する |
| `direct_cancellation_pending` | ローカルのキャンセル意思に対するiPhoneの確認応答がない | iPhoneを再度開き、cancelを再試行する |
| `invalid_direct_raw_response` | 厳密な生データの検証に失敗した | 出力を使用しない |
| `invalid_direct_file_receipt` | ファイルマニフェストまたはコミットレシートの検証に失敗した | ファイルを手動で修復または追記しない |
| `partial_canonical_extraction` | 要求した抽出が未完了 | レシートを確認し、許容できる場合にだけ部分的な結果を明示的に受け入れる |
| `unvalidated_response_too_large` | 現在の検証上限では1つの結果を公開できない | スコープを狭めるか、適切な出力モードを使用する |
| `stale_cursor` | ページカーソルの発行後に暗号化コンテキストが変更された | 現在のコーパスに対してクエリを最初から実行する |

## ペイロードを記録しない進捗出力

高レベルクエリのフェーズとページ走査には、`--progress-json`を使用します。

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

進捗JSONLには、フェーズ、ページ数、項目数、日付、安全な診断情報を含めることができます。ヘルスデータの値を含めてはいけません。最終結果とは分けて保存し、それでも適切な保持ポリシーを適用してください。

## 関連項目

<div class="related">
  <a href="/ja/docs/cli/"><span>設定</span>Health.md CLI：インストール、バックエンドの選択、コマンド出力の理解。</a>
  <a href="/ja/docs/cli-direct/"><span>直接接続</span>iPhone直接接続CLI：ペアリング、限られたバックグラウンド実行時間、明示的な保存先、信頼済みの再開。</a>
  <a href="/ja/docs/agent-queries/"><span>ページング</span>型付きクエリの実例：新規取得とキャッシュモード、ページ走査、カバレッジ、レシート。</a>
  <a href="/ja/docs/reference/generated/cli/exit-codes/"><span>生成済みコントラクト</span>CLI終了コード：本番環境から生成されたステータスとエラー動作。</a>
</div>
