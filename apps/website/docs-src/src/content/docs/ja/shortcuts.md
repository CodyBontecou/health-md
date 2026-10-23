---
title: "ショートカットとApp Intents"
description: "Health.mdの7アクションをショートカットとSiriで使用します。Macコンテキスト更新アクションは提案段階で、利用できません。"
---

<div class="availability preview"><strong>ソースに登録された7アクション</strong><p>Refresh Mac Health ContextとGet Mac Context Refresh Statusは提案段階で、未実装です。開発版でも利用できません。<a href="https://github.com/CodyBontecou/health-md/issues/173">課題 #173</a>を参照してください。提供には実装、検証、正確なAppleリリースの説明が必要です。</p></div>

## アクション

- 昨日、指定日、期間、直近N日をエクスポート
- 健康概要または最終エクスポート状態を取得
- スケジュールを有効・無効化

### 提案されたMacコンテキストアクション（利用不可）

要求された**Refresh Mac Health Context**は明示的なプロファイルと日付範囲、認証済みの互換デバイス、永続的なコンテキスト取得を使用し、エクスポートファイルの作成やファイル出力枠の消費を行わない想定です。**Get Mac Context Refresh Status**は復旧可能なジョブ識別子とともに保留・完了・失敗を報告する想定です。これらは要件であり、現在のアプリで使えるアクション名、パラメータ、結果ではありません。

コンピュータ側のMCP更新はiOSの個人用オートメーションを提供しません。通常のエクスポートショートカットで代用しないでください。出力先は引き続きiPhoneフォルダです。スリープ中のMacを起こしたり、保護されたHealthKitデータを回避したりすることは保証できません。この機能の検証には、復帰後の実機iPhoneでのオートメーションQAが引き続き必要です。

4つのエクスポートアクションは任意の**プロファイル**を受け取ります。不明な名前は安全に失敗します。通常のショートカットはiPhoneフォルダへ書き込み、API EndpointやConnected Macへ密かに切り替わりません。

ロック中の実行許可はHealthKitを解除しません。Health.mdは要求を保留し、**Health Export Needs Attention**を表示します。

### 朝の自動化

1. 時刻オートメーションを作ります。
2. **Export Yesterday's Health Data**を追加します。
3. **Get Last Export Status**と通知を追加します。

「昨日」には昨夜始まった睡眠が含まれます。[睡眠の日付](/ja/docs/sleep-date-attribution/)を参照してください。

<div class="related"><a href="/ja/docs/export-profiles/"><span>プロファイル</span>安定した識別子。</a><a href="/ja/docs/release-status/"><span>互換性</span>対応バージョン。</a></div>
