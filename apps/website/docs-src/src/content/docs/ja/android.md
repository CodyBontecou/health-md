---
title: "Androidアプリ"
description: "Android 用にHealth.mdセットアップします。 Health Connectデータをエクスポートし、Storage Access Framework フォルダーを選択し、エクスポートをスケジュールし、Tasker または adb で自動化します。"
---

<div class="docs-hero">
 <p class="docs-eyebrow"> Health Connectプライベート ファイルへ</p>
 <p> Android のHealth.mdはデバイス上のHealth Connectを読み取り、 Markdown 、 Obsidian Bases、JSON、または CSV を選択したフォルダーに書き込みます。このフォルダー エクスポート ワークフローには、 Health.mdアカウントは必要ありません。 Google Playアクセス オプションとF-Droidに含まれるアクセスについては、以下で説明します。 </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener"> Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droidステータス</a>
 <a class="docs-button-secondary" href="/ja/docs/export/">エクスポート ドキュメントの読み取り</a>
 </div>
 <p id="distribution-status"> F-Droidカタログの発行は保留中です。 Google Playで現在の Android リリースを入手してください。 </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> <span>選択可能なHealth Connectメトリクス</span> </div>
 <div> <strong> 4 </strong> <span>エクスポート形式</span> </div>
 <div> <strong> 2 </strong> <span> Android 配布チャネル</span> </div>
 <div> <strong> 0 </strong> <span> Health.mdクラウド アカウントが必要</span> </div>
 </div>

## Android アプリの機能

Android 用Health.mdは、 Health Connectローカルファーストの健康ジャーナルに変えます。必要なメトリクスを選択し、出力をプレビューします。次に、ファイルをローカル フォルダー、 Obsidianボールト、同期されたプロバイダー フォルダー、または書き込み可能な Android ドキュメント プロバイダーにエクスポートします。

<div class="options">
 <div class="option"> <strong> Health Connectソース</strong> <p> Android のオンデバイスHealth Connect API を介して、アクティビティ、睡眠、心臓、バイタル、身体測定、栄養、トレーニング、その他のカテゴリを読み取ります。 </p> </div>
 <div class="option"> <strong> Obsidianネイティブ出力</strong> <p>毎日のメモ、YAML/frontmatter、 Obsidian Bases フレンドリーなメモ、個々のエントリ、およびHealth.md Obsidianプラグインと互換性のある JSON を書き込みます。 </p> </div>
 <div class="option"> <strong> Android ネイティブ ストレージ</strong> <p>ストレージ アクセス フレームワークを使用して、ローカル ストレージ、 Obsidian 、Google Drive、OneDrive、Syncthing、または別のプロバイダーによって公開されるフォルダーを選択できます。 </p> </div>
 </div>

## ＃＃ 要件

- Android 9 / API 28 以降。
- Health Connect対応のデバイスまたはエミュレータ。
- Health Connect Health Connectに書き込む Android アプリ、ウェアラブル、またはサービスからのデータ。
- エクスポートの書き込みアクセスを許可するフォルダーまたはドキュメント プロバイダー。

## 最初のエクスポート

1. Google Playから現在のHealth.mdリリースをインストールします。
2. ** Health Connect ** セットアップを開き、 Health.mdでエクスポートするカテゴリのみを許可します。
3. Android のフォルダー ピッカーを使用してエクスポート先を選択します。
4. 形式を選択します: Markdown 、 Obsidianベース、JSON、CSV、または任意の組み合わせ。
5. メトリクスと日付範囲を選択します。
6. 出力をプレビューします。
7. [エクスポート] をタップし、フォルダーまたはボールト内に生成されたファイルを確認します。

サブスクリプション対応のGoogle Play電話リリースには、手動エクスポート用のアクティブな試用版、サブスクリプション、ライフタイム、または保存された永続的なアクセスが必要です。対象となるサブスクリプションには 7 日間のトライアルが含まれます。生涯に試練はない。 F-Droidビルドには、購入や復元フローのない無制限のアクセスが含まれています。

## Android の目的地

Android はiPhone → Mac のローカルネットワーク宛先を使用しません。代わりに、Android のストレージ アクセス フレームワークに依存します。

| 行き先 | アンドロイドのステータス |
| --- | --- |
| ローカルデバイスフォルダー | フォルダーピッカーを通じてサポートされます |
| Obsidianボールト | ボールト フォルダーが Android のピッカーに公開されている場合にサポートされます |
| Google Drive、OneDrive、Syncthing、 Obsidian Sync、および同様のプロバイダー | プロバイダーが書き込み可能なフォルダーを公開する場合にサポートされます |
| iPhone /Mac ローカルネットワークの宛先 | Apple プラットフォーム固有。 Androidでは使用されていません |

プロバイダーが Android のピッカーを介して書き込み可能なフォルダーを公開していない場合、 Health.mdそこに安全に直接書き込むことができません。永続的な書き込みアクセスを許可するプロバイダー フォルダーを選択するか、ローカルにエクスポートして好みのツールと同期します。

## フォーマット

Android アプリは、Apple アプリと同じプレーン ファイルの目標を共有します。

| 形式 | 用途: |
| --- | --- |
| Markdown | 読みやすい毎日の健康概要、テンプレート、メモ |
| Obsidian Bases | Obsidianデータベース ビューでクエリできる Frontmatter-first のメモ |
| JSON | スクリプト、ダッシュボード、ノートブック、 Health.md Obsidianプラグインの構造化された日次ペイロード |
| CSV | スプレッドシートと分析のワークフロー |

Android JSON エクスポートは、 Health.mdのObsidian視覚化と互換性があるように設計されています。 Markdownおよび Bases エクスポートは、[フォーマット ガイド](/ja/docs/format/) に記載されている同じフロントマターに重点を置いたワークフローを使用します。

## スケジューリングと自動化

サブスクリプション対応のGoogle Play電話リリースでは、スケジュールされたエクスポートにはアクティブな試用版、サブスクリプション、ライフタイム、または保存された永続的なアクセスが必要です。これらはF-Droidビルドに含まれています。 Android のアラームとリマインダーへのアクセスを許可すると、ワンショットの正確なアラームが使用され、バックアップとして耐久性のあるWorkManager機能が使用されます。正確なアラームにアクセスしない場合、 WorkManagerプライマリ スケジューラになるため、選択された時間は厳密な保証ではなく目標になります。 Health.mdはエクスポート履歴を記録し、失敗したスケジュールされた日付を回復したり、失敗した実行を再試行したりできます。

Tasker、adb、またはその他の自動化ツールの場合、 Health.mdは明示的のみのブロードキャスト インテントを公開します。外部呼び出し元は、受信側コンポーネントを直接アドレス指定する必要があります。

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

例:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

オートメーションは、凍結された宛先、形式、メトリック、アカウンティング、履歴を含むアクティブなプロファイルをデフォルトで使用します。提供された`PROFILE`エクストラでは、安定したプロファイル ID または名前を選択できます。不明な参照は、現在の設定を使用せずにフェールクローズされます。スケジュールされた実行もプロファイルにバインドされたままになります。 [プロファイルのエクスポート](/ja/docs/export-profiles/)を参照してください。

### バックグラウンドでの準備と計画されたキャンセル

- 無人エクスポートのバックグラウンドHealth Connect読み取りを許可します。それ以外の場合は、 Health.mdを開いてヘルスデータの読み取りを完了します。
- 通知を有効にして、Android がアクティブな作業、フォアグラウンド サービスの状態、結果、回復アクションを表示できるようにします。
- 正確なアラームのスケジュールが必要な場合にのみ、アラームとリマインダーを許可します。これがなければ、耐久性のあるWorkManager作業は引き続き利用可能ですが、選択された時間はおおよその時間です。
- スケジュールされた実行をキャンセルすると、その試行のみが停止されます。完了した日付は完了したままとなり、未解決の日付は再試行でき、定期的なスケジュールは有効なままになります。

## 健康情報源

Health Connectは、両方のチャネルのローカル エクスポート パスです。 Google Playビルドには、Samsung Health、Huawei Health、Fitbit、Garmin、Withings、Oura、Polar、WHOOP などのエコシステム用のヘルス ソース セットアップ領域も含まれています。これらのエコシステムがHealth Connectに書き込む場合、どちらのビルドでも結果のHealth Connectレコードをエクスポートできます。クラウド プロバイダーの直接インポートと OAuth コールバックは再生のみです。 F-Droidプロバイダー カタログにはHealth Connectのみが含まれます。

Health Connectは Android の優先健康データ レイヤーであるため、Google Fit はサポート対象プロバイダー サーフェスから意図的に除外されています。

### 現地当日の正確な手順

毎日の歩数の合計には、正確なゾーン化されたローカル日の境界が使用されます。集約の前に、 Health.md 、ローカルの午前 0 時に重複するHealth Connect間隔をクリップして分割します。したがって、旅行や夏時間の変更により、ステップが間違った日に移動することはありません。

## 配布、価格設定、およびスイッチング

- ** Google Play :** サブスクリプション対応の電話機リリースでは、個人の週次/年次サブスクリプションと生涯サブスクリプションが提供されます。対象となる初回購読者は 7 日間のトライアルを受け、その後Google Playを通じてキャンセルされるまで、表示された価格で自動的に更新されます。ライフタイムは、試用なしですぐに 1 回だけ課金されます。現地の自由輸出枠は残っていない。既存の永続的なアクセスは維持されます。購入を復元するには、購入用の Google アカウントを使用します。アプリを削除したり、ライフタイムを購入したりしても、サブスクリプションはキャンセルされません。古いリリースのビルドでは、以前の許容値が表示される場合があります。現在のリリースは電話専用です。 Wear OS コンパニオンは、後の認定サイクルに延期されます。
- ** F-Droid :** 無制限のアクセスが含まれます。無料カウンター、請求依存関係、ペイウォール、購入、または復元アクションはありません。
- ** F-Droidスコープ:** Health Connectのみ。Wear OS 統合、直接クラウド プロバイダー OAuth、Play レビュー、アトリビューション、またはHealth.mdオンボーディング テレメトリなし。
- **共有結果:** 両方のチャネルが同じHealth Connectキャプチャ、エクスポーター、スキーマ、自動化アクション、およびダイレクトデバイス プロトコルを使用します。
- **切り替え:** Google PlayとF-Droidは異なる署名キーを使用するため、チャネルを変更するには最初にアプリをアンインストールする必要があります。

チャネルの切り替えでは、購入、設定、履歴、資格情報、またはプライベート転送状態は移行されません。エクスポートされたファイルは、選択した宛先に残ります。

Google Play Billing が一時的に切断された場合、Play ビルドは再接続し、権利の状態を自動的に更新します。一時的なサービスの喪失によってプレミアムが永久に削除されるわけではありません。接続が戻った後もアカウントが未解決のままである場合にのみ、購入の復元を使用してください。

## プライバシーモデル

Android のHealth.mdはローカルファーストです。

- Health Connectレコードは Android デバイスで読み取られます。
- エクスポートは、選択したフォルダーに直接書き込まれます。
- コア フォルダーのエクスポートと直接デバイス クエリでは、既定ではHealth.mdサーバー コピーが作成されません。
- 設定とエクスポート履歴はデバイス上に残ります。
- 請求は Play ビルドのGoogle Playによって処理されます。 F-Droidには、課金なしの無制限のアクセスが含まれており、 Health.mdテレメトリ コードやテレメトリ ID/状態は含まれません。
- プロバイダーがサポートするフォルダーは、プロバイダー独自の条件に従って同期されます。

最も厳密なローカル設定が必要な場合は、ローカル デバイス フォルダーへの手動エクスポートを実行し、スケジュールされたエクスポートとプロバイダーによる同期は無効のままにしてください。

個別のオプションの単一所有者Health.mdクラウド パイロットは、意図的にアップロードされた API エクスポートのみを保持します。パブリックサインアップやデバイスの自動同期はありません。このフォルダー ワークフローはフォルダーにアップロードしません。保持、削除、クォータ、およびバックアップされていないストレージのリスクについては、[プライバシー ポリシー](/privacy-policy.html) を参照してください。

## 関連ドキュメント

<div class="related">
 <a href="/ja/docs/export-profiles/"> <span>プロファイル</span>独立した宛先、出力設定、スケジュール、および安定した自動化 ID を保存します。 </a>
 <a href="/ja/docs/export/"> <span>エクスポート</span>手動エクスポート フロー、日付範囲、プレビュー、履歴、およびファイル出力。 </a>
 <a href="/ja/docs/metrics/"> <span>メトリクス</span>メトリクスの選択とカテゴリがHealth.md間でどのように機能するか。 </a>
 <a href="/ja/docs/format/"> <span> </span> Markdownベース、JSON、CSV、ユニット、ファイル名、およびフロントマターの形式。 </a>
 <a href="/ja/docs/visualizations-roadmap/"> <span> Obsidian </span>エクスポートされた JSON およびMarkdown Health.mdビジュアライゼーションをどのように強化するか。 </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">最終更新日 2026-10-04 </p>
