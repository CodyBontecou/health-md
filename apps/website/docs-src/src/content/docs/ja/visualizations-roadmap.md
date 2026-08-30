---
title: 可視化とロードマップ
description: エクスポートするデータ種別ごとに整理した、Health.mdのObsidian可視化における現在の対応状況と今後のチャート計画。
---

Health.mdは、Markdown、Obsidian Bases、JSON、CSV向けに、スキーマでバージョン管理されたローカルデータセットをエクスポートします。以下の可視化ロードマップでは、このデータ範囲と連携するObsidian可視化プラグインについて、現在利用できる機能、エクスポートデータから次に実現できる機能、汎用のスキーマ対応チャートが必要なカテゴリを示します。

<div class="callout">
<strong>データソース</strong>
<p style="margin-top:6px;">このページは、Health.mdのエクスポートスキーマとデータ辞書に基づき、アクティビティ、睡眠、心臓、バイタル、身体、栄養、マインドフルネス、服薬、ワークアウト、リプロダクティブヘルス、症状、聴覚、ライフスタイル／環境指標の順に構成されています。</p>
</div>

## 可視化ごとの単位上書き

プラグイン全体の設定とは異なる表示単位を1つのグラフで使う場合は、個別の `units` を `health-viz` ブロックに設定します。

```health-viz
type: workout-trends
metric: distance
units: imperial
```

`auto` はエクスポートで宣言された単位系に従い、`metric` はキロメートル、キログラム、メートル、摂氏で表示し、`imperial` はマイル、ポンド、フィート、華氏で表示します。この上書きはその可視化だけに適用され、グローバルな Units 設定より優先されます。変更されるのは表示値だけで、エクスポート済みの Health.md ファイルは変更されません。歩数、BPM、パーセンテージ、カロリーなど、変換できないメトリクスは変わりません。

## 現在の可視化対応範囲

<div class="reference-stats">
<div><strong>43</strong><span>現在利用できるプラグインレンダラー</span></div>
<div><strong>18</strong><span>エクスポートデータのカテゴリ</span></div>
<div><strong>220+</strong><span>正規エクスポートキー</span></div>
<div><strong>1</strong><span>今後必要な汎用指標レイヤー</span></div>
</div>

## エクスポーター別の対応プラットフォーム

可視化の対応範囲は、ソースデータがApple HealthKitとAndroid Health Connectの両方に存在するか、Apple HealthKitのエクスポートコントラクトだけに存在するかによって異なります。

### iOSおよびAndroid

これらの可視化は、HealthKitとHealth Connectで共有するエクスポートフィールドに対応しています。

| カテゴリ | 可視化の種類 |
| --- | --- |
| 概要 | `intro-stats`、`summary-card`、`trend-tile` |
| アクティビティ | `activity-rings`、`vitals-rings`、`bar-chart`、`activity-heatmap`、`step-spiral`、`weekday-average` |
| 心臓 | `heart-terrain`、`heart-range`、`hrv-trend` |
| 呼吸・バイタル | `oxygen-river`、`oxygen-range`、`breathing-wave` |
| 睡眠 | `sleep-schedule`、`sleep-quality-bars`、`sleep-architecture`、`sleep-polar` |
| モビリティ | `walking-symmetry`* |
| ワークアウト | `workout-log`、`workout-heart-rate`、`workout-zones`、`workout-trends`、`workout-intervals`、`workout-map` |

注記：

- `walking-symmetry`はAndroidで一部対応です。Androidには歩行速度がありますが、Apple固有の歩行非対称性や両脚支持時間の詳細はありません。
- `activity-rings`は、スタンドについてAndroidで一部対応です。`standHours`がない場合、プラグインは歩数から算出したスタンドの代替値を使用します。
- ワークアウトの経路とサンプルチャートには、詳細なワークアウトデータと経路データへの許可／同意が必要です。

### iOSのみ

HealthKitの「心の状態」／気分の可視化：

- `mood-trend` / `state-of-mind`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

服薬カタログ／服用イベントの可視化：

- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

Android Health Connectは、同等のHealthKit「心の状態」レコードや、HealthKit形式の服薬カタログ／服用イベントレコードを公開しません。

### Androidのみ

現在のObsidianプラグインの可視化レジストリにはありません。Androidは、PHR／FHIRリソース、計画済みワークアウト、アクティビティ強度など、Android固有のデータをエクスポートしますが、これらのフィールドを対象とする可視化はまだありません。

<span id="visualization-screenshot-gallery"></span>

## 可視化カタログ

各項目から、[Health.md可視化ギャラリー](/visualizations/)内の対応する公開バリエーションを開けます。リンクには`theme-colors`バリエーションを使用しているため、すべてのレンダラーをこのページへ埋め込まず、ドキュメントを高速で安定した状態に保てます。

### サマリーと概要

- [イントロ統計](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [サマリーカード](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [トレンドタイル](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### アクティビティ

- [アクティビティリング](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [棒グラフ](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [アクティビティヒートマップ](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [歩数スパイラル](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [曜日別平均](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### 心臓

- [心拍地形図](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [心拍数レンジ](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [HRVトレンド](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### 呼吸・血中酸素・バイタル

- [血中酸素リバー](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [血中酸素レンジ](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [呼吸波形](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [バイタルリング](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### 睡眠

- [睡眠スケジュール](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [睡眠品質バー](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [睡眠アーキテクチャ](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [睡眠ポーラーチャート](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### マインドフルネスと気分

- [気分トレンド](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [気分カレンダーヒートマップ](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [気分 × 睡眠散布図](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [気分の日内タイムライン](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [関連付けによる気分](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [気分ラベルクラウド](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [気分の不安定さ](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [日常と瞬間の気分](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [概日気分時計](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [回復＋マインドセットタイル](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [気分関連付け行列](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### 服薬

- [服薬概要](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [服薬一覧](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [服薬遵守サマリー](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [服用状況](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [服薬遵守の推移](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [最近の服用イベント](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### モビリティ、歩容、ランニングフォーム

- [歩行対称性](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### ワークアウト

- [ワークアウトログ](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [ワークアウト心拍数](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [ワークアウトゾーン](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [ワークアウトのトレンド](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [ワークアウト区間](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [ワークアウトマップ](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## 基盤ロードマップ

製品にとって最大の課題は、個別のチャートが1つ足りないことではありません。必要なのは、指標ごとに専用のパーサーやレンダラーを作らなくても、エクスポートされたHealth.mdのあらゆるフィールドを描画できる、汎用のスキーマ対応指標レイヤーです。

### 実装済み

- 日次エクスポート、旧形式ファイル、ロールアップ、データ辞書ファイルのスキーマ互換性を検出。
- JSON、CSV、Markdown、Obsidian Basesを読み込み。
- ロールアップを認識し、週次、月次、年次のサマリーが日次グラフへ混入するのを防止。
- チャートのデータ点から、その値に寄与したHealth.mdソースファイルへ移動。

### 計画中

- **汎用のスキーマ対応指標アクセサー** — ラベル、単位、カテゴリ、集計規則、エイリアスを`_healthmd_data_dictionary.json`から読み取ります。
- **汎用指標トレンド** — エクスポートされた任意の数値キーを折れ線／面グラフで表示します。
- **汎用指標バー** — 目標線としきい値線を備えた、日次／週次／月次の汎用棒グラフです。
- **汎用カレンダーヒートマップ** — 任意の日次数値指標をカレンダーグリッドで表示します。
- **可視化カバレッジレポート** — Vaultに存在するフィールドと、専用レンダラーが対応するフィールドを表示します。

---

## サマリーと概要

### 実装済み

- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) — 合計、平均、睡眠、バイタルを含むデータセットの概要。
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) — スパークラインと前期間比較を備えたApple風のKPIカード。
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) — 現在の期間と前の期間を比較するトレンドカード。

### 計画中

- 選択したHealth.mdフォルダ内のフィールドに基づいて自動生成するダッシュボード。
- データカテゴリ別のスキーマカバレッジダッシュボード。
- 睡眠と気分、HRVとワークアウト、症状と服薬、アルコールと睡眠などの相関サマリーカード。

---

## アクティビティ

Health.mdは、歩数、アクティブエネルギー、基礎代謝エネルギー、エクササイズ時間、スタンド時間、上った階数、歩行／走行距離、サイクリング、水泳、車椅子アクティビティ、ダウンヒルスノースポーツの距離、ムーブ時間、身体的負荷、VO₂ maxをエクスポートします。

### 実装済み

- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)

### 計画中

- 歩数、カロリー、エクササイズ、スタンド時間、身体的負荷を表示するアクティビティ負荷ダッシュボード。
- VO₂ maxの推移。
- ムーブ／エクササイズ／スタンドの一貫性チャート。
- ウォーキング／ランニング、サイクリング、水泳、車椅子、スノースポーツの距離構成グラフ。
- 水泳距離＋ストロークチャート。
- 車椅子の距離＋プッシュ数チャート。

---

## 睡眠

Health.mdは、総睡眠時間、就寝時刻、起床時刻、深い睡眠／REM／コア／覚醒／ベッド内の時間、詳細な睡眠段階区間をエクスポートします。

### 実装済み

- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)

### 計画中

- 睡眠負債と一貫性スコア。
- 睡眠段階比率の推移。
- 就寝／起床時刻の規則性ヒートマップ。
- 睡眠＋HRV＋安静時心拍数の回復ダッシュボード。

---

## 心臓

Health.mdは、安静時心拍数、歩行時心拍数、平均／最小／最大心拍数、HRV、心拍数サンプル、HRVサンプル、心拍数回復、心房細動負荷をエクスポートします。

### 実装済み

- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)

### 計画中

- 安静時心拍数の推移。
- 歩行時心拍数の推移。
- 心拍数回復の推移。
- 心房細動負荷チャート。
- HRV＋安静時心拍数の回復タイル。
- 時間帯別の概日心拍数プロファイル。

---

## 呼吸と血中酸素

Health.mdは、血中酸素の平均／最小／最大値、血中酸素サンプル、呼吸数の平均／最小／最大値、呼吸数サンプルをエクスポートします。

### 実装済み

- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)

### 計画中

- 呼吸数専用のレンジチャート。
- 酸素飽和度低下イベントチャート。
- 睡眠段階、血中酸素、呼吸数を組み合わせた夜間呼吸ダッシュボード。

---

## バイタル

Health.mdは、体温、血圧、血糖値、基礎体温、手首温度、皮膚電気活動、努力性肺活量、FEV1、最大呼気流量、吸入器の使用状況をエクスポートします。

### 実装済み

- サマリーカードと一般的な日次チャートによる部分的なカバレッジ。

### 計画中

- しきい値帯を含む収縮期／拡張期血圧レンジチャート。
- 血糖値レンジチャート。
- 体温、基礎体温、手首温度の推移。
- 手首温度による回復／体調タイル。
- FVC、FEV1、ピークフロー、吸入器の使用状況を示す呼吸機能ダッシュボード。
- 皮膚電気活動／ストレスの推移。

---

## 身体測定

Health.mdは、体重、身長、BMI、体脂肪率、除脂肪体重、腹囲をエクスポートします。

### 実装済み

- 専用の体組成レンダラーはまだありません。

### 計画中

- 体組成ダッシュボード。
- 移動平均と目標線を含む体重の推移。
- カテゴリ帯を含むBMIの推移。
- 体脂肪率と除脂肪体重の比較チャート。
- 腹囲の推移。

---

## モビリティ、歩容、ランニングフォーム

Health.mdは、歩行速度、歩幅、両脚支持時間、歩行非対称性、階段昇降速度、6分間歩行距離、歩行安定性、ランニング速度、ランニング歩幅、接地時間、上下動、ランニングパワーをエクスポートします。

### 実装済み

- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)

### 計画中

- 歩容ダッシュボード。
- 歩行安定性ゲージ。
- 6分間歩行距離の推移。
- 階段昇降速度チャート。
- 速度、歩幅、接地時間、上下動、パワーをまとめたランニングフォームダッシュボード。

---

## ワークアウト

Health.mdは、ワークアウト回数、時間、カロリー、距離、ワークアウト種別、心拍数統計、ランニング／サイクリングのフォーム指標、パワー、標高、ラップ、スプリット、経路点、心拍数ゾーン、ワークアウト時系列サンプルをエクスポートします。

### 実装済み

- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)

### 計画中

- ワークアウトカレンダーヒートマップ。
- 時間と強度から算出するトレーニング負荷チャート。
- 週ごとのワークアウト種別構成。
- ワークアウト種別ごとのペースと速度の推移。
- 獲得／下降標高の推移。
- 複数の小グラフによる経路比較。
- パワーカーブ／ベストエフォート。
- ランニングフォームとサイクリングパフォーマンスのダッシュボード。

---

## マインドフルネスと気分

Health.mdは、マインドフル時間、マインドフルセッション、「心の状態」の記録、平均感情価、日々の気分、瞬間的な感情、ラベル、関連付けをエクスポートします。

### 実装済み

- [`mood-trend`](/visualizations/mindfulness-mood/mood-trend/theme-colors/)
- [`mood-calendar-heatmap`](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/)
- [`mood-sleep-scatter`](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/)
- [`mood-day-timeline`](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/)
- [`mood-association-breakdown`](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/)
- [`mood-label-cloud`](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/)
- [`mood-volatility`](/visualizations/mindfulness-mood/mood-volatility/theme-colors/)
- [`mood-kind-split`](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/)
- [`mood-circadian-clock`](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/)
- [`mood-recovery-tile`](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/)
- [`mood-association-matrix`](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/)

### 計画中

- マインドフル時間の推移。
- マインドフルセッションの継続記録／カレンダー。
- 気分と服薬遵守の関係。
- 気分と栄養、アルコール、カフェインの関係。
- 気分ラベルのタイムライン。

---

## 服薬

Health.mdは、服薬一覧、使用中／アーカイブ済みの件数、服用イベント件数、服用／スキップ件数、薬剤詳細、RxNorm／コーディングメタデータ、服用量、スケジュール種別、予定日／開始日／終了日、ステータス、メタデータをエクスポートします。

### 実装済み

- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)

### 計画中

- 服薬スケジュールのタイムライン。
- 服薬遵守カレンダーヒートマップ。
- 予定時刻と服用時刻を比較する服薬遅延チャート。
- 服用量の推移。
- 服薬と症状／気分の相関ビュー。
- RxNorm／コーディング詳細パネル。

---

## 栄養

Health.mdは、食事由来のカロリー、タンパク質、炭水化物、脂質、飽和脂肪、一価不飽和脂肪、多価不飽和脂肪、食物繊維、糖類、ナトリウム、コレステロール、水分、カフェインをエクスポートします。

### 実装済み

- 専用の栄養レンダラーはまだありません。

### 計画中

- 栄養ダッシュボード。
- 三大栄養素の構成チャート。
- 摂取カロリーとアクティブカロリーの比較チャート。
- 水分摂取量の推移。
- 1日のカフェイン摂取量／摂取時刻チャート。
- 糖類とナトリウムのしきい値チャート。
- 食物繊維とタンパク質の目標達成度。

---

## ビタミンとミネラル

Health.mdは、ビタミンA、B6、B12、C、D、E、K、チアミン、リボフラビン、ナイアシン、葉酸、ビオチン、パントテン酸、カルシウム、鉄、カリウム、マグネシウム、リン、亜鉛、セレン、銅、マンガン、クロム、モリブデン、塩化物、ヨウ素をエクスポートします。

### 実装済み

- 専用の微量栄養素レンダラーはまだありません。

### 計画中

- 微量栄養素ヒートマップ。
- 1日の推奨量に対する進捗グリッド。
- ビタミン推移ダッシュボード。
- ミネラル推移ダッシュボード。
- 不足／過剰フラグパネル。
- 栄養充足度スコア。

---

## 聴覚

Health.mdは、ヘッドフォン音量レベルと環境音レベルをエクスポートします。

### 実装済み

- 概要レベルの部分的なカバレッジのみ。

### 計画中

- 音への曝露量の推移。
- 騒音の大きい日を示すカレンダー。
- 安全な曝露量のしきい値帯。
- 週ごとの曝露量サマリー。

---

## リプロダクティブヘルスと周期記録

Health.mdは、月経量、性行為、排卵検査結果、頸管粘液の質、月経間出血をエクスポートします。

### 実装済み

- リプロダクティブヘルス専用のレンダラーはまだありません。

### 計画中

- 月経周期カレンダー。
- 月経量ヒートマップ。
- 妊孕性シグナルのタイムライン。
- リプロダクティブヘルス、症状、気分、睡眠を組み合わせた周期症状のオーバーレイ。
- スポッティング／月経間出血のタイムライン。

---

## 症状

Health.mdは、頭痛、疲労、吐き気、めまい、気分の変化、睡眠の変化、食欲の変化、ほてり、悪寒、発熱、腰痛、腹部膨満、便秘、下痢、胸やけ、咳、喉の痛み、鼻水、息切れ、胸痛、脈が飛ぶ、頻脈、にきび、乾燥肌、脱毛、物忘れ、寝汗、嘔吐、腹部けいれん、乳房痛、骨盤痛、全身痛、失神、嗅覚喪失、味覚喪失、喘鳴、副鼻腔のうっ血、尿失禁、膣の乾燥について、日ごとの症状件数をエクスポートします。

### 実装済み

- 専用の症状レンダラーはまだありません。

### 計画中

- 症状カレンダーヒートマップ。
- 症状頻度ランキング。
- 症状の共起マトリクス。
- 症状増悪のタイムライン。
- 症状相関エクスプローラー。
- 身体系統別にまとめた症状ダッシュボード。

---

## その他の健康、ライフスタイル、環境

Health.mdは、UV曝露、日光を浴びた時間、転倒、血中アルコール、アルコール飲料、インスリン投与、歯磨き、手洗い、水温、水深をエクスポートします。

### 実装済み

- ライフスタイル／環境専用のレンダラーはまだありません。

### 計画中

- 日光／UVカレンダー。
- 転倒のタイムライン。
- アルコールと睡眠／HRVの比較チャート。
- インスリン投与量の推移。
- 歯磨きと手洗いの継続記録。
- 水温／水深チャート。

---

## 優先順位

1. 汎用のスキーマ対応指標基盤。
2. 汎用のトレンド、棒グラフ、カレンダーヒートマップの各レンダラー。
3. バイタル一式：血圧、血糖値、体温、呼吸機能。
4. 体組成ダッシュボード。
5. 栄養ダッシュボード。
6. 症状ヒートマップ、頻度ランキング、相関ビュー。
7. 周期／リプロダクティブヘルスカレンダー。
8. 微量栄養素ヒートマップとRDAグリッド。
9. モビリティとランニングフォームの拡張ダッシュボード。
10. 聴覚とライフスタイル／環境チャート。

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">最終更新日：2026-06-25</p>
