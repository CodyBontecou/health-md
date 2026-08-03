---
title: "型付きクエリの実例"
description: "ページングと欠損を明示し、Health.mdの指標、睡眠、トレーニング、ワークアウト、カバレッジ、期間比較、エビデンスを新規取得またはキャッシュから照会します。"
---

高レベルCLIコマンドは、一般的なヘルスデータの質問を、仕様が固定された型付きクエリ操作へ変換します。既定では要求したiPhoneデータを取得し、Macの暗号化コンテキストを照会して、エビデンスとカバレッジを含むバージョン管理されたJSONを返します。

`healthmd.health_data`の日次データまたはソースレコード全体が必要な場合は、代わりに[正規抽出](/ja/docs/cli-extract/)を使用してください。

## 準備状況を確認し、指標を探す

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

指標カタログは、正規ID、表示名、カテゴリ、単位、利用要件を返します。各指標についてHealthKitの権限が付与済みだと示すものではありません。

IDを推測せず、カタログからコピーしてください。

## 指標の時系列を照会する

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

カテゴリは現在のカタログに基づいて展開されます。

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

複数の指標フラグとカテゴリフラグは結合されます。新規取得では、保存済みのエクスポート設定を変更せず、展開済みの選択内容をiPhoneへ渡します。

レスポンスには`healthmd.cli_metric_query` v1エンベロープを使用します。ネストした型付きクエリレスポンスとともに、取得の診断情報も保持します。

## 新規取得、キャッシュ、カバレッジの再利用

既定は新規取得です。

```bash
healthmd query --metric resting_heart_rate --last 30
```

接続中のiPhoneへ正確なスコープを要求し、更新した暗号化所有者日をコミットしてから照会します。

キャッシュモードではiPhoneに接続しません。

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

保存されている取得時刻とカバレッジで十分な場合に限り、オフライン分析にキャッシュモードを使用してください。

`--reuse-covered`は、まず暗号化済みのサマリーカバレッジを確認します。

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

要求したすべての指標と日について、互換性のある完全なサマリーカバレッジがある場合にだけ取得を省略します。ロスレスリクエストと、新しくプロジェクションされた睡眠セッション操作では、この短縮経路を使用しません。

## 完了フィールドを理解する

新規クエリのレスポンスでは、次の3つの概念を分けて示します。

| フィールド | 答える質問 |
|---|---|
| `requested_scope_status` | 今回の取得で、要求したすべての指標、ソース、プロバイダ、所有者日の処理が完了したか |
| `corpus_status` | 取得したコーパス内のほかの分岐で、警告、スキップ、失敗が報告されたか |
| `unrelated_skips` | スキップまたは未対応となった分岐のうち、要求スコープ外だったものはどれか |

要求スコープが完了していても、コーパス内に無関係なスキップが存在する場合があります。Health.mdは、要求結果を誤って格下げしたり、コーパスの診断情報を隠したりせず、両方の事実を保持します。

新規取得の完了判定に数えるのは、更新開始後に置き換えられたblobだけです。古いキャッシュ値で、失敗したリクエストを完了扱いにはできません。

## 結果をページ単位で取得する

`--all-pages`を指定しない場合、コマンドは上限付きの1ページだけを返します。`next_cursor`を確認してください。

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

カーソルがnullでなければ、続きの結果があります。全ページの取得が完了するまで、外側の高レベルステータスは`partial_success`のままです。

自動取得では、不透明なカーソルをたどり、同じカーソルの反復も確認します。

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

レスポンスは、最初の`healthmd.query_response`を`query`に、後続のバージョン管理されたレスポンスを`pages`に保持します。また、ページ数、項目数、事実数、エビデンス数、最終的な走査状態を含む`healthmd.cli_query_receipt` v1も格納します。

自動取得には、全体のページ数とバイト数に上限があります。上限に達した場合は日付または指標の選択を狭めるか、[低レベルAPI](/ja/docs/agent-api/)を使って手動でページを取得してください。

## 進捗と表形式の出力

ヘルスデータを含まないフェーズ情報とページ進捗を、JSONLとして標準エラー出力へ出力できます。

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSONが完全な出力です。表モードは、ターミナルで人が読むための、明示的に選択する非可逆なTSV表示です。

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

表のフッターには、カバレッジ、ソース、制限事項、完了状態、無関係なスキップに関する注記が残ります。スクリプトで正確な型付き値やエビデンスが必要な場合は、表形式を使用しないでください。

## 睡眠セッション

Apple Healthの睡眠段階は日付をまたぐことがあり、ソース間で重複する場合もあります。睡眠コマンドは、各所有者日を1つの数値合計として扱わず、安定したセッションを構築します。

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

正確な日付と全履歴の選択も使用できます。

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

各セッションでは、次の情報を返せます。

- 安定したセッションID
- 所有者日とローカルタイムゾーン
- ローカルおよびUTCでの正確な開始・終了タイムスタンプ
- 夜間睡眠または昼寝の分類
- 選択した睡眠段階の合計
- 観測済み時間と未追跡時間
- 完全性と除外内容
- セッション開始を基準にした固定時間枠
- 隣接日の生理学的データのカバレッジ
- ソースエビデンス

セッション取得では、ロスレスの正規睡眠段階区間と、正規の睡眠段階指標一式を要求します。Health.mdは境界確認のため、技術的に必要な隣接所有者日を最大1日だけ読み取り、結果から無関係な日付を除外します。

重複する睡眠段階ソースは、総睡眠時間の計算時に重複を排除します。集計値しかないキャッシュ済みコンテキストには`aggregated`と表示し、区間の観測カバレッジがあるとは主張しません。固定の`first:4h`時間枠に、日次集計を4時間分として按分することもありません。

## ワークアウトと睡眠の対応付け

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

Health.mdは選択したワークアウトごとに、前後36時間以内で条件を満たす直近の睡眠セッションを、前後それぞれ1つ特定します。次の情報を返します。

- 安定したワークアウトIDとセッションID
- 正確な時間差
- 要求した睡眠時間枠
- 生理学的サンプル数
- 睡眠段階とセッションのカバレッジ
- エビデンスと除外内容

この操作は決定論的な時間的対応付けです。ワークアウトが睡眠結果を引き起こした、または睡眠がワークアウトのパフォーマンスを引き起こしたとは主張しません。技術的に必要な隣接所有者日は最大2日しか読み取らず、無関係なデータも返しません。

## ワークアウトの一覧

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

ワークアウト一覧は、安定したID、正確なタイムスタンプ、型付きの詳細、エビデンス、欠損情報を保持します。結果は開始タイムスタンプと安定したワークアウトIDの順に並びます。ワークアウト総数に固定上限はなく、各レスポンスをページ制御で制限します。

## カバレッジ

「値はいくつか」ではなく「どのデータがあるか」を知りたい場合は、カバレッジを使用します。

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

カバレッジは、要求範囲と利用可能範囲、対象日数、値がある日数、ステータス付きの欠損期間を返します。同じステータスと理由が連続する期間は、意味を失わずに圧縮される場合があります。

該当する観測値がない日は`complete_empty`になることがあります。一度も同期されていない日は、別のステータスになります。どちらもゼロには変換されません。

## 正確な期間を比較する

CLIは、指標を合計、平均、最小、最大、件数、最新値のどれで集計するべきか推測しません。各メトリックIDの直後に集計方法を指定してください。

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

対応する集計方法は次のとおりです。

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

単位や型が一致しない値は、暗黙に結合せずエラーにします。値がない期間には集計値がありません。第1期間の基準値がゼロの場合、絶対変化量はありますが変化率はなく、制限事項として`zero_baseline`が含まれます。

方向は事実だけを表し、`increased`、`decreased`、`unchanged`、`not_comparable`のいずれかです。良くなった、または悪くなったという意味ではありません。

## トレーニングのエビデンスパケット

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

必要な場合に限り、特定のワークアウト詳細を要求します。

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

ワークアウト詳細を選択すると、そのリクエストに必要なロスレススコープが要求されます。パケットには、事実に基づく値、カバレッジ、ソース記述子、エビデンスロケーター、制限事項が含まれます。

パケットIDは、意味内容から算出する決定論的なSHA-256ダイジェストです。同じパケットを別の時刻に再生成した場合、生成メタデータが変わっても意味IDは変わりません。

コントラクトv1のエビデンスパケット種別には、`daily_wellness`、`training`、`doctor_visit`があります。現在、高レベルの便利なコマンドで公開しているのはトレーニングパケットです。正確なリクエスト本文には低レベルAPIを使用してください。

## 日付の所有権とタイムゾーン

クエリの日付は、コンパクトコンテキストの`owner_date`値です。各日には、その日を構成した正確な半開区間のUTC範囲と、取得時のIANAカレンダータイムゾーンも保持されます。

睡眠セッションはローカルタイムスタンプと日付またぎを保持します。技術的な隣接日読み取りにより、Macの現在のタイムゾーンに合わせてデータを移動せず、セッションを所有者日の境界越しに扱えます。

日付に依存する質問をエージェントへ行う場合は、意図する所有者日を含め、コンピューターのタイムゾーンを前提にせず、返されたタイムゾーンを確認してください。

## エージェントの回答で欠損を隠さない

安全な要約には、次の情報を残す必要があります。

- メトリックIDと正規単位
- 日付範囲とタイムゾーン
- 新規取得、キャッシュ、カバレッジ再利用のいずれのモードか
- 要求スコープとコーパスのステータス
- ページ走査が完了したか
- エビデンス参照またはソースダイジェスト
- 完全だが空の期間と欠損期間
- 警告、制限事項、無関係なスキップ

失敗した日を除外して平均したり、データなしをゼロとして扱ったり、時間的な対応付けを因果関係として説明したりしないでください。

## 関連項目

<div class="related">
  <a href="/ja/docs/agents/"><span>アーキテクチャ</span>ローカルエージェントとヘルスコンテキスト：設定、暗号化、リクエストスコープ、エビデンス、保持。</a>
  <a href="/ja/docs/mcp/"><span>MCP</span>ローカルMCPヘルパー：クエリ、睡眠、対応付け、ワークアウト、カバレッジ、比較、エビデンスに対応する型付きツール。</a>
  <a href="/ja/docs/agent-api/"><span>低レベルコントラクト</span>ループバッククエリAPI：正確なリクエスト、1ページのレスポンス、更新、ジョブルート。</a>
  <a href="/ja/docs/reference/evidence-packets/"><span>リファレンス</span>コンパクトクエリとエビデンスパケット：型付き値、カーソル、操作、カバレッジ、ID。</a>
</div>
