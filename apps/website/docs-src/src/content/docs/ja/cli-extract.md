---
title: "正規ヘルスデータの抽出"
description: "healthmd extractを使い、選択したApple Health指標を取得して、正規のschema-v7ドキュメント、ソースレコード、JSON Pointerプロジェクション、またはJSONLを明示的なレシートとともに出力します。"
---

`healthmd extract`は、スクリプトやエージェントがソースデータを取得するためのコマンドです。選択した指標と詳細レベルだけを取得するようiPhoneへ要求し、永続転送を検証して、転送エンベロープを取り除きます。その後、正規の`healthmd.health_data` v7ドキュメント、またはプロジェクションであることが明示された結果を出力します。

元のHealth.mdデータが必要な場合は抽出を使用します。セッション、比較、ワークアウトとの対応付け、カバレッジ、エビデンスパケットが必要な場合は、[型付きクエリ](/ja/docs/agent-queries/)を使用してください。

## 基本構文

抽出には次の指定が必要です。

1. 指標、カテゴリ、オブジェクト、`--all-metrics`セレクターのうち1つ以上
2. 日付セレクターを1つ
3. 任意で、詳細、オブジェクト、フィールド、形式、出力、タイムアウト、部分的な結果の扱い

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

現在の正規抽出ソースは`apple_health`です。プロバイダ固有のサイドカーは、それぞれ独自のコントラクトにとどまり、合成したApple Health値へ変換されません。

## 範囲を絞ったリクエストから始める

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

指標名とカテゴリ名は、iPhoneで処理を始める前に、現在のカタログに照らして検証されます。複数を組み合わせるには、セレクターを繰り返し指定します。

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## HealthKitを読み取る前に選択する

抽出では、保存済みの全指標エクスポートを取得してから削るのではありません。CLIは指定したセレクターを変更不能な`CanonicalHealthDataSelection`へ解決し、iPhoneへ送信します。Health.mdが確認して読み取るのは、選択した指標の根拠となる通常のHealthKitタイプだけです。

この違いは、プライバシー、性能、完全性に影響します。

- 選択していない指標は取得されません。
- iPhoneに保存済みの指標設定は変更されません。
- サマリーリクエストが、隠れたソースアーカイブを作ることはありません。
- ロスレスリクエストでは、選択内容に必要なソースタイプだけを取得します。
- 選択内容は、永続リクエストのフィンガープリントに含まれます。

オブジェクトセレクターとJSON Pointerセレクターは、取得後に出力するデータを絞ります。指標、カテゴリ、ソース、詳細レベルの各セレクターは、iPhoneでの取得そのものを絞ります。

## サマリーとロスレスの詳細レベル

既定はサマリーです。

```bash
healthmd extract --category Activity --last 7 --detail summary
```

サマリー出力には、型付きの日次サマリー、クエリ診断、`raw_capture_status: not_requested`を含めることができます。このステータスは実際の処理を正確に示しています。コマンドは正規ソースレコードを取得していません。

ソースオブジェクト、UUID、正確なタイムスタンプ、出所、アーカイブ診断が重要な場合は、ロスレス詳細を要求します。

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

`records`など、アーカイブを対象とするオブジェクトは、`--detail`を省略してもロスレス詳細を暗黙に要求します。

## オブジェクトセレクター

`--object`を使うと、選択した各日の既知の部分だけを残せます。現在の名前は次のとおりです。

| オブジェクト | 主な内容 |
|---|---|
| `sleep` | 日次の睡眠サマリーフィールド |
| `activity` | 歩数、エネルギー、距離、エクササイズなどのアクティビティサマリー |
| `heart` | 心拍数、安静時心拍数、HRVなどのサマリー |
| `vitals` | 血圧、血糖値、体温、血中酸素などのバイタルサマリー |
| `body` | 体重、体組成、身長、身体測定 |
| `nutrition` | 栄養素と水分摂取のサマリー |
| `mindfulness` | マインドフルセッションと心の健康に関するサマリー |
| `mobility` | 歩行、歩容、モビリティのフィールド |
| `hearing` | 音への曝露と聴覚のフィールド |
| `reproductive-health` | リプロダクティブヘルス、妊娠、周期のフィールド |
| `cycling` | サイクリングのサマリー |
| `vitamins` / `minerals` | 各栄養素のサマリー |
| `symptoms` | 症状データ |
| `medications` | 利用可能で権限が付与されている場合の服薬データ |
| `workouts` | 正規ワークアウトサマリーオブジェクト |
| `archive` | 正規HealthKitアーカイブエンベロープ |
| `records` | 正規ソースレコード。ロスレス詳細を暗黙に要求 |
| `external-records` | 公開日次データにすでに含まれている外部レコード |
| `query-results` | クエリごとの取得結果 |
| `warnings` | 整合性の警告 |

例：

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## JSON Pointerプロジェクション

RFC 6901 JSON Pointerを`--field`で繰り返し指定すると、正確な値またはステータス項目を出力できます。

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Pointerの結果はプロジェクションであり、完全な日次ドキュメントではありません。ソーススキーマと日付を参照しますが、サブツリーが完全なエクスポートに見えるような形で`schema: healthmd.health_data`を持つことはありません。

選択したパスが存在しない場合は、完全だが空、またはその日の未完了ステータスとして報告されます。Health.mdがデータなしをゼロへ変換することはありません。

## JSON出力

既定のJSON出力には、次のいずれかのデータコレクションが含まれます。

- 完全な正規日次ドキュメントでは`health_data`
- オブジェクトまたはPointerの結果では`projections`

さらに、`healthmd.extract_receipt`も含まれ、次の情報を記録します。

- 解決済みの選択内容と日付範囲
- ソースと詳細レベル
- 日ごとの結果
- 保持した項目数と取得数
- 欠損日
- 部分的な結果または失敗の診断
- 出力の完了状態

レシートはプロトコルメタデータです。ソーススキーマを置き換えるものではありません。

## JSONL出力

ストリーム処理にはJSONLを使用します。

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

1行が1つのデータ項目です。レシートはヘルスデータのストリームに混在しません。

- `--output`を指定した場合は、`OUTPUT.receipt.json`に書き込まれます。
- `--output`を指定しない場合は、標準エラー出力に書き込まれます。

このため、パイプラインの動作を予測できます。

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

標準エラー出力にはレシートとヘルスデータ非依存の進捗が含まれるため、JSONLパーサーへパイプしないでください。

## 完了、空、部分的な結果

Health.mdは、次の状態を区別して保持します。

| 状態 | 意味 |
|---|---|
| `success` | 完全だが空の分岐を含め、要求したすべての分岐が完了 |
| `complete_empty` | 要求スコープは表現されているが、観測値がない |
| `partial_success` | 要求したデータの一部は保持されているが、少なくとも1つの要求分岐が未完了 |
| `failed` | 要求した分岐が失敗 |
| `unsupported` | プラットフォームまたはHealthKitが要求分岐に未対応 |
| `skipped` | Health.mdがその分岐を意図的に照会しなかった |
| `cancelled` | iPhoneがキャンセルを確認 |
| `missing` | 要求した日または分岐が表現されていない |

部分的な抽出では、既定で保持済みデータを出力しません。利用側が不完全なスコープを受け入れ、その状態を保持できる場合に限り、`--allow-partial`を追加します。

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

このフラグは、出力と終了動作を変更します。診断を削除したり、部分的なデータを完全なデータへ変えたりするものではありません。

## Macアプリと直接接続のバックエンド

このコマンドは、どちらのバックエンドでも動作します。

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

どちらの経路も、同じ公開日次スキーマと厳密な検証を使用します。転送、ペアリング、ストレージ、ジョブレコードは異なります。

## 大規模な履歴

`--all`には固定の日付上限がありません。

```bash
healthmd extract --metric steps --all --output all-steps.json
```

iPhoneは、選択したレコードのうち最も古い利用可能な日付を解決し、今日までのソース暦日をすべて固定して、上限付きのパーティションを転送します。CLIは、上限のない1つのメモリ内レスポンスを構築せず、ディスク上で組み立てて検証します。

コーパスが大きい場合は、JSONLを使用するか、選択範囲を狭めてください。利用可能なディスク容量と、極端にデータ量の多い1日が実用上の制限になります。

## プライバシーチェックリスト

- ヘルスデータを含む結果には`--output`を使用する
- 出力ファイルとレシートファイルを、元のApple Healthデータと同じ水準で保護する
- ヘルスデータのコマンド実行時にシェルトレースを使用しない
- CIログとエージェントのトランスクリプトにペイロードを残さない
- トラブルシューティングでは、レシート、件数、ステータス、スキーマ、欠損のフィールドだけを確認する
- 対象の利用側が安全にコミットした後、一時エクスポートを削除する

## 関連項目

<div class="related">
  <a href="/ja/docs/cli/"><span>CLI</span>Health.md CLI：設定、バックエンドの選択、コマンド一覧、出力規則。</a>
  <a href="/ja/docs/agent-queries/"><span>派生ビュー</span>型付きクエリの実例：指標時系列、睡眠、トレーニング、ワークアウト、比較、エビデンス。</a>
  <a href="/ja/docs/reference/daily-records/"><span>スキーマ</span>日次レコード：完全なschema-v7日次ドキュメントのコントラクト。</a>
  <a href="/ja/docs/reference/canonical-healthkit-records/"><span>ソースアーカイブ</span>正規Apple Healthレコード：ID、出所、関係、ペイロード。</a>
  <a href="/ja/docs/reference/api-and-cli/"><span>プロトコル</span>APIとCLIのリファレンス：抽出リクエスト、レシート、厳密な検証、終了動作。</a>
</div>
