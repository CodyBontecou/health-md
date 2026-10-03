---
title: "ショートカットとApp Intents"
description: "公開済み7アクションと開発ソースのMacコンテキスト2アクションをショートカットやSiriで使用します。"
---

<div class="availability preview"><strong>公開済み7アクション · 現在のソースは9</strong><p>Macコンテキストの2アクションには対応するiPhone/Macビルドが必要です。正確なリリースノートを確認してください。</p></div>

## アクション

- 昨日、指定日、期間、直近N日をエクスポート
- 健康概要または最終エクスポート状態を取得
- スケジュールを有効・無効化
- **Refresh Mac Health Context**（開発中）：プロファイルに結び付いた暗号化コンテキストの永続更新
- **Get Mac Context Refresh Status**（開発中）：状態とjob IDを取得

4つのエクスポートアクションは任意の**プロファイル**を受け取ります。不明な名前は安全に失敗します。通常のショートカットはiPhoneフォルダへ書き込み、API EndpointやConnected Macへ密かに切り替わりません。

ロック中の実行許可はHealthKitを解除しません。Health.mdは要求を保留し、**Health Export Needs Attention**を表示します。

### 朝の自動化

1. 時刻オートメーションを作ります。
2. **Export Yesterday's Health Data**を追加します。
3. **Get Last Export Status**と通知を追加します。

「昨日」には昨夜始まった睡眠が含まれます。[睡眠の日付](/ja/docs/sleep-date-attribution/)を参照してください。

<div class="related"><a href="/ja/docs/export-profiles/"><span>プロファイル</span>安定した識別子。</a><a href="/ja/docs/release-status/"><span>互換性</span>対応バージョン。</a></div>
