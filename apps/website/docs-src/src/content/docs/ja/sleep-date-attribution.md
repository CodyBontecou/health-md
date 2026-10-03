---
title: "睡眠の日付とデイリーノート"
description: "夜間睡眠が開始日に属する理由と、朝に書き出す期間を説明します。"
---

Health.mdは睡眠セッションを**開始した日**に割り当てます。月曜23:45から火曜7:30までの睡眠は月曜の概要に入ります。Health Connectが起床日を表示しても、AppleとAndroidでこの規則は共通です。

| 目的 | エクスポート |
|---|---|
| 火曜朝に昨夜の睡眠 | **昨日**（月曜） |
| 火曜の活動 | **今日** |
| 両方 | 月曜と火曜 |

日次概要は夜を一つに保ちます。正規ソースレコードは元の開始・終了時刻を維持し、開始日のアーカイブに属します。Health.mdは架空の半分に分けません。セッションとして扱う場合は`healthmd_sleep_sessions`を使用します。

Daily Note InjectionとAPI Endpointも同じ割り当てです。同期が遅れた場合は開始日を再エクスポートしてください。現在、起床日に再割り当てする設定はありません。

<div class="related"><a href="/ja/docs/scheduling/"><span>自動化</span>朝は昨日を含めます。</a><a href="/ja/docs/troubleshooting/"><span>ヘルプ</span>空・遅延データを確認。</a></div>
