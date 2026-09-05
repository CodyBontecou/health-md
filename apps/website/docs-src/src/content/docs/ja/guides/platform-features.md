---
title: プラットフォーム別の機能
description: Health.mdがiPhone、iPad、Mac、Android、Wear OS、CLIで提供する機能。共通の機能と、正直に示されたプラットフォーム間の違い。
---

<div class="docs-hero">
  <p class="docs-eyebrow">プラットフォーム概要</p>
  <p>Health.mdがiPhone、iPad、Mac、Android、Wear OS、CLIで何をするか。プラットフォームが許すところでは共通化し、異なるところでは正直に示します。</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhoneとMac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

凡例：✓ 利用可能 · ◐ 行内に記載のあるプラットフォーム差あり · △ 計画中またはQA中 · ? 利用可能性は表明していない · — そのプラットフォームでは利用不可。

CLIは独立したヘルスデータプラットフォームの列ではありません。CLIの機能は自動化の行に現れ、iPhoneまたはAndroidのソースのセマンティクスを引き継ぎます。

## セットアップと権限

| 機能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| ヘルスデータの権限（読み取る内容を正確に選択） | ✓ Apple Healthのタイプ | ◐ ペアリング済みのiPhone／Macの保存先経由で読み取り | ✓ Health Connectのカテゴリ | — |
| エクスポート先を選択 | ✓ Obsidian保管庫、iCloud Drive、ファイル | ✓ ローカルフォルダ | ✓ 任意のAndroidフォルダプロバイダ（Drive、OneDrive、Syncthing、Obsidian Sync…） | — |
| サンプルプレビュー付きのオンボーディング | ✓ | ✓ | ✓ | — |
| Share My Setup（設定をデバイス間で移動） | △ QA中 | △ QA中 | △ QA中 | — |

## 読み取りとエクスポート

| 機能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Markdown、Obsidian Bases、JSON、CSVへの日次エクスポート | ✓ | ✓（ファイルはiPhoneから届きます） | ✓ | — |
| 225以上のApple Health指標／106のHealth Connect指標 | ✓ | ✓ | ✓ | — |
| 書き込み前のプレビュー | ✓ | ✓ | ✓ | — |
| 独立した設定を持つ保存済みエクスポートプロファイル | ✓ iPhoneで管理。? iPadでの管理は表明していない | ? 管理は表明していない | ✓ Androidで管理 | — |
| 週次／月次／年次のロールアップサマリー | ✓ | ✓ | △ 計画中。別途レビューされたAndroidスキーマプロファイルが必要（現行のv4/v5は変更なし） | — |
| エクスポート履歴と再試行 | ✓ | ✓ | ✓ | — |
| スケジュールを無効化せずに実行中の処理を停止またはキャンセル | ✓ 完了した日は保持され、未解決の日は再試行可能 | ✓ | ✓ 完了した日は保持され、未解決の日は再試行可能 | — |
| 1回分のZIPアーカイブ | ✓ | ✓ | — | — |
| サマリーデータ詳細 | ✓ | ✓ | ✓ | — |
| 選択した指標の詳細な時系列 | ✓ | ✓ | ✓ | — |
| ロスレスヘルスレコードの正規ソースアーカイブ | ✓ `healthmd.healthkit_records` | ✓ | — Apple専用。代わりにRaw APIスナップショットを参照 | — |
| Raw APIスナップショットのエクスポート（不変のJSON/NDJSON） | — | — | ✓ Health Connect＋Fitbit、Oura、WHOOP、Withings | — |

## 高度なデータ

| 機能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 個別エントリの追跡（トレーニング、睡眠段階、バイタル） | ✓ | ✓ | ✓ | — |
| トレーニングの詳細（提供される場合は完全なグラフとルート付き） | ✓ | ✓ | ✓ | — |
| ムード／State of Mindのエクスポート | ✓ | ✓ | —（Health Connectに相当する機能なし） | — |
| 投薬記録イベント | ✓ | ✓ | —（Health Connectに相当する機能なし） | — |
| 血圧、血糖、血中酸素、体温の測定値 | ✓ | ✓ | ✓ | — |
| サードパーティプロバイダのデータ | ◐ エクスポート内のWHOOPセクション（ベータ） | ◐ | ✓ プロバイダネイティブの生スナップショット | — |

一部のデータは、プラットフォーム間で意図的に**同等として扱いません**。心拍変動はAppleではSDNN、AndroidとWHOOPではRMSSDであり、Health.mdはこれらを混ぜず別々の指標として保持します。Apple Watchの手首の温度とHealth Connectの皮膚温度も、別々に保持されます。

## 自動化と統合

| 機能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 定期的なスケジュールエクスポート | ✓ 通知＋APNsフォールバック | ✓ | ✓ WorkManager（＋オプションの正確なアラーム）、起動時の回復 | — |
| システム自動化 | ✓ ショートカット／Siri／App Intents | — | ✓ Tasker、adb、明示的なブロードキャストインテント | — |
| エクスポートを独自のHTTP(S) APIエンドポイントへ送信 | ✓ | — | ✓ ヘッダーを暗号化して保存 | — |
| スタンドアロンCLI（`healthmd`）とのペアリング | ✓ フォアグラウンドのダイレクトサービス | ✓ 同梱＋スタンドアロン | ✓ 20桁コードによるペアリング | — |
| CLI直接リクエストのウェイク | ✓ 上限付きの待機＋オプトインのAPNs | ✓ CLIがイニシエータ | ◐ 上限付きの待機。FCMは計画中 | — |
| AIエージェント向けMCPサーバー | ◐ Mac経由で同梱。型付きポータブルな直接MCPはiPhone専用 | ✓ `healthmd-mcp`を同梱 | — 型付き直接MCPは非対応 | — |

## デバイスと一目でわかる画面

| 機能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| ホーム画面のウィジェット | ✓ サマリー、アクティビティリング、心拍レンジ、睡眠 | — | ✓ サマリー、アクティビティ、心拍レンジ、睡眠（スタンド時間の代わりに歩数） | — |
| エクスポート進捗のライブアクティビティ | ✓ | — | — | — |
| ウォッチ画面 | ✓ ウォッチアプリ＋10種のコンプリケーション | — | — | ✓ タイル＋10種のコンプリケーション |
| Macをエクスポート先に（暗号化されたローカル転送） | ✓ iPhoneが送信 | ✓ 受信 | — | — |

## 購入とプライバシー

| 機能 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 無料枠 | ✓ 手動またはスケジュールされたエクスポート10回 | — | ✓ 手動エクスポート10回 | — |
| 解除 | ✓ 1回限りの買い切り（個人／ファミリー） | ◐ 同じAppleの解除 | ✓ 1回限りの買い切り（スケジュール機能を含む） | — |
| ローカルファーストのプライバシー | ✓ Health.mdのヘルスデータクラウドなし | ✓ | ✓ | ✓ |
| 医療者向けレポート（診察用の1つのPDF） | ✓ | — | ✓ | — |

Health.mdはヘルスデータ用クラウドを運用していません。ヘルスデータが存在できるのは、ユーザーが選んだ保存先、暗号化されたローカルコンテキスト、および範囲が限定された非公開の転送状態です。フォルダ、Mac、APIエンドポイント、CLIの保存先は、いずれも明示的に設定します。プロファイルとスケジュールは、作成したデバイスのローカルに留まります。各プラットフォームのワークフローについては、[エクスポートプロファイル](/ja/docs/export-profiles/)、[Androidガイド](/ja/docs/android/)、[iPhoneエクスポートガイド](/ja/docs/export/)を参照してください。
