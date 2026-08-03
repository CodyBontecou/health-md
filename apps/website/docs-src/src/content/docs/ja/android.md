---
title: Androidアプリ
description: Health.md for Androidをセットアップし、Health ConnectのデータをMarkdown、Obsidian Bases、JSON、CSVにエクスポートして、Storage Access Frameworkのフォルダ、エクスポートスケジュール、Taskerまたはadbによる自動化を設定します。
---

<div class="docs-hero">
  <p class="docs-eyebrow">Health Connectからプライベートなファイルへ</p>
  <p>Health.md for Androidは、デバイス上でHealth Connectを読み取り、Markdown、Obsidian Bases、JSON、またはCSVを選択したフォルダに書き込みます。Health.mdアカウント、ヘルスデータ用クラウド、サブスクリプションは不要です。</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Google Playで入手</a>
    <a class="docs-button-secondary" href="/ja/docs/export/">エクスポートドキュメントを読む</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>選択可能なHealth Connect指標</span></div>
<div><strong>4</strong><span>エクスポート形式</span></div>
<div><strong>10</strong><span>無料の手動エクスポート回数</span></div>
<div><strong>0</strong><span>必要なHealth.mdクラウドアカウント</span></div>
</div>

## Androidアプリでできること

Health.md for Androidは、Health Connectをローカルファーストのヘルスジャーナルに変換します。必要な指標を選択して出力をプレビューし、ローカルフォルダ、Obsidian Vault、同期プロバイダのフォルダ、または書き込みアクセスを許可する任意のAndroidドキュメントプロバイダへ、整理されたファイルをエクスポートできます。

<div class="options">
  <div class="option"><strong>Health Connectソース</strong><p>AndroidのオンデバイスHealth Connect APIを介して、アクティビティ、睡眠、心臓、バイタル、身体測定、栄養、ワークアウトなどのカテゴリを読み取ります。</p></div>
  <div class="option"><strong>Obsidian向けの出力</strong><p>日次ノート、YAML/frontmatter、Obsidian Bases向けノート、個別エントリ、Health.md Obsidianプラグインと互換性のあるJSONを書き込みます。</p></div>
  <div class="option"><strong>Androidネイティブのストレージ</strong><p>Storage Access Frameworkを使用するため、ローカルストレージ、Obsidian、Google Drive、OneDrive、Syncthing、または別のプロバイダが公開するフォルダを選択できます。</p></div>
</div>

## 要件

- Android 9 / API 28以降。
- Health Connectに対応したデバイスまたはエミュレータ。
- Health Connectに書き込むAndroidアプリ、ウェアラブル、またはサービスからのHealth Connectデータ。
- エクスポート先として書き込みを許可するフォルダまたはドキュメントプロバイダ。

## 最初のエクスポート

1. Google PlayからHealth.mdをインストールします。
2. **Health Connect**のセットアップを開き、Health.mdからエクスポートするカテゴリだけを許可します。
3. Androidのフォルダピッカーからエクスポート先を選択します。
4. Markdown、Obsidian Bases、JSON、CSV、またはその任意の組み合わせから形式を選択します。
5. 指標と日付範囲を選択します。
6. 出力をプレビューします。
7. エクスポートをタップし、フォルダまたはVaultで生成ファイルを確認します。

無料プランには、手動エクスポート10回分が含まれます。無制限エクスポートを解除する前に、権限、フォルダアクセス、形式、Obsidianのワークフローを試せます。

## Androidの保存先

Androidでは、iPhone → Macのローカルネットワーク保存先を使用しません。代わりにAndroidのStorage Access Frameworkを使用します。

| 保存先 | Androidでの対応状況 |
|---|---|
| ローカルデバイスのフォルダ | フォルダピッカーを介して対応 |
| Obsidian Vault | VaultフォルダがAndroidのピッカーに公開されている場合に対応 |
| Google Drive、OneDrive、Syncthing、Obsidian Syncなどのプロバイダ | プロバイダが書き込み可能なフォルダを公開している場合に対応 |
| iPhone/Macのローカルネットワーク保存先 | Appleプラットフォーム専用。Androidでは不使用 |

プロバイダがAndroidのピッカーを介して書き込み可能なフォルダを公開していない場合、Health.mdはその場所に安全に直接書き込めません。永続的な書き込みアクセスを許可するプロバイダフォルダを選択するか、ローカルにエクスポートして任意のツールで同期してください。

## 形式

Androidアプリは、Appleアプリと同じプレーンファイルの方針を共有しています。

| 形式 | 用途 |
|---|---|
| Markdown | 読みやすい日次ヘルスサマリー、テンプレート、ノート |
| Obsidian Bases | Obsidianのデータベースビューで照会できるfrontmatter中心のノート |
| JSON | スクリプト、ダッシュボード、ノートブック、Health.md Obsidianプラグイン向けの構造化された日次ペイロード |
| CSV | スプレッドシートと分析のワークフロー |

AndroidのJSONエクスポートは、Health.mdのObsidian可視化と互換性を持つよう設計されています。MarkdownとBasesのエクスポートでは、[形式ガイド](/ja/docs/format/)に記載されているものと同じfrontmatter中心のワークフローを使用します。

## スケジュールと自動化

スケジュールエクスポートでは、Androidの「アラームとリマインダー」へのアクセスを許可した場合、1回限りの正確なアラームを使用し、永続的なWorkManager処理を補助的に使用します。正確なアラームへのアクセスがない場合はWorkManagerが主なスケジューラーとなるため、選択した時刻は厳密な保証ではなく目安です。Health.mdはエクスポート履歴を記録し、実行漏れとなった予定日を回収して、失敗した処理を再試行できます。

Tasker、adb、または別の自動化ツール向けに、Health.mdは明示的に指定した場合だけ受け付けるブロードキャストインテントを公開しています。外部の呼び出し元は、レシーバーコンポーネントを直接指定する必要があります。

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

例：

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

自動化では、現在のエクスポート設定、選択したフォルダ、形式、指標、無料利用枠とエクスポート回数の計上、履歴が使用されます。

## ヘルスソース

Health Connectが既定のローカルエクスポート経路です。Androidアプリには、Samsung Health、Huawei Health、Fitbit、Garmin、Withings、Oura、Polar、WHOOPなどのエコシステム向けに、ヘルスソースの設定画面もあります。これらのエコシステムがHealth Connectに書き込む場合、Health.mdはそのHealth Connectレコードをエクスポートできます。クラウドプロバイダから直接インポートするにはプロバイダの認証が必要で、追加のセットアップや利用可否の制約がある場合があります。

Health ConnectがAndroidで推奨されるヘルスデータレイヤーであるため、Google Fitは対応プロバイダの範囲から意図的に除外されています。

## 価格と購入の復元

- Androidアプリには、無料の手動エクスポート10回分が含まれます。
- 無制限のエクスポートとスケジュール自動化は、Google Play Billingを介した1回限りの買い切りで解除できます。
- サブスクリプションや継続課金はありません。
- Google Playでは、購入前に現在の現地価格が表示されます。
- 購入の復元では、Premiumを購入したGoogleアカウントを使用します。

## プライバシーモデル

Health.md for Androidはローカルファーストです。

- Health ConnectのレコードはAndroidデバイス上で読み取られます。
- エクスポートは選択したフォルダに直接書き込まれます。
- Health.mdはヘルスデータ用クラウドサービスを運営していません。
- 設定とエクスポート履歴はデバイス上に保持されます。
- 課金はGoogle Playによって処理されます。
- プロバイダが管理するフォルダは、そのプロバイダ自身の規約に従って同期されます。

最も厳格なローカル構成にするには、ローカルデバイスのフォルダへ手動でエクスポートし、スケジュールエクスポートとプロバイダ経由の同期を無効にします。

## 関連ドキュメント

<div class="related">
  <a href="/ja/docs/export/"><span>エクスポート</span>手動エクスポートの流れ、日付範囲、プレビュー、履歴、ファイル出力。</a>
  <a href="/ja/docs/metrics/"><span>指標</span>Health.md全体での指標選択とカテゴリの動作。</a>
  <a href="/ja/docs/format/"><span>形式</span>Markdown、Bases、JSON、CSV、単位、ファイル名、frontmatter。</a>
  <a href="/ja/docs/visualizations-roadmap/"><span>Obsidian</span>エクスポートしたJSONとMarkdownをHealth.mdの可視化に使用する方法。</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">最終更新日：2026-08-03</p>
