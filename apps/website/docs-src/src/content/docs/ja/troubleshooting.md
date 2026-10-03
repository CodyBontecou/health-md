---
title: "Health.mdのトラブルシューティング"
description: "空のエクスポート、睡眠不足、電話未接続、スケジュール、フォルダ、部分結果、タイムアウトを確認します。"
---

端末1台、1日、1カテゴリ、1つの出力先から始めます。健康データ、経路、臨床文書、トークン、ペアリングコード、非公開パスを問題報告に含めないでください。

## データが空

Apple HealthまたはHealth Connectに値があるか、権限があるか確認し、1日・1カテゴリをエクスポートします。`complete_empty`、権限なし、非対応、スキップ、部分、失敗を区別します。欠測はゼロではありません。

## 「今日」に昨夜の睡眠がない

睡眠は夜が始まった日に属します。火曜朝は**昨日**または月曜と火曜をエクスポートします。[睡眠の日付](/ja/docs/sleep-date-attribution/)を参照してください。

## ファイルとスケジュール

vault、フォルダ権限、サブフォルダ、テンプレート、プロファイルを確認します。iOSバックグラウンド処理とWorkManagerの時刻は目標であり保証ではありません。ロックを解除して復旧を使います。

## CLIタイムアウト

タイムアウトは受理済みジョブをキャンセルしません。

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

完全性を主張する前に状態、欠落日、範囲、`next_cursor`、バージョン、制限を確認します。`--allow-partial`は終了方針だけを変えます。

<div class="related"><a href="/ja/docs/cli-jobs/"><span>ジョブ</span>再開とキャンセル。</a><a href="/ja/docs/release-status/"><span>バージョン</span>互換性。</a></div>
