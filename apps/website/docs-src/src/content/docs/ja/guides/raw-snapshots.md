---
title: Raw APIスナップショット
description: Health ConnectのレコードとFitbit、Oura、WHOOP、Withingsのプロバイダ応答を、型ごとのマニフェストとチェックサム付きの不変でバージョン管理されたJSONまたはNDJSONスナップショットとしてエクスポートします。
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · アーカイブグレードのエクスポート</p>
  <p>Raw API Snapshotは、移行とアーカイブのワークフロー向けに用意された、Health.md for Androidの独立したエクスポート製品です。選択した期間ごとに、ネイティブなレコードを保持した不変でバージョン管理されたJSONまたはNDJSONアーティファクトを1つ生成します。</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Google Playで入手</a>
    <a class="docs-button-secondary" href="/ja/docs/android/">Androidアプリガイド</a>
  </div>
</div>

## Rawスナップショットとは

互換エクスポートはHealth Connectのレコードを読みやすい日次の`HealthData`サマリーへ変換します。Rawスナップショットはこの変換を完全にスキップします：

- **Health Connectスナップショット**は、ピン留めされたAndroidX APIが公開するすべてのフィールドを保持します。ネイティブな識別子とメタデータ、ナノ秒タイムスタンプ、null許容のソースオフセット、生の列挙値、ネストしたサンプル、ステージ、経路、計画されたワークアウト構造まで含みます。
- **Fitbit、Oura、WHOOP、Withingsのスナップショット**は、成功したプロバイダ応答の正確なバイト列を保持し、エンドポイントのページネーションとサーバー側集計を明示します。未対応のプロバイダは、正規化されたりHealth Connectのデータで黙って置き換えられたりせず、報告されます。
- すべてのアーティファクトは、型ごとのステータス、問題、件数、チェックサムを含む**マニフェスト**で終わります。フォルダエクスポートにはさらに`.sha256`サイドカーファイルが付きます。

Rawスナップショットは、アプリがピン留めしたプロバイダAPIに対してAPI完全ですが、プロバイダデータベースのトランザクショナルバックアップではありません。アクセス不能なレコード、APIが公開しない元の単位、削除済みレコード、インストール済みSDKに未知のフィールドは復元できません。

## 送信先の決定前にプレビュー

Rawスナップショットは、送信先を設定しなくてもプレビューできます。プレビューはプロバイダネイティブの読み取り全体を非バックアップのプライベートストレージに対して実行し、メモリには上限付きの先頭・末尾テキストだけを保持し、一時アーティファクトをアップロードせずに削除します。

## 配信ルール

Raw APIのアップロードは、互換APIエクスポートより意図的に厳格です：

| ルール | 理由 |
|---|---|
| HTTPSのみ | ストリーミングされるアーティファクトが平文で流れることはない |
| リダイレクト拒否 | アーティファクトと資格情報が別のオリジンに再生されることはない |
| スキーマ・エクスポート・チェックサムヘッダー | 受信側エンドポイントが受け取った内容を検証できる |
| 試行後に一時プライベートアーティファクトを削除 | 端末にコピーが残らない |

## 差分アーカイブ

別個にバージョン管理される`healthmd.raw-changes`バックエンドは、Health Connectの変更トークンと削除トゥームストーンを使い、将来の差分アーカイブワークフローに備えます。これにより、完全なスナップショットだけがアーカイブ戦略である必要はありません。

## 要件

- Raw API Snapshot製品を備えたHealth.md for Android。
- 選択したレコード型のHealth Connect権限、またはプロバイダスナップショット用に接続済みのFitbit、Oura、WHOOP、Withingsアカウント。
- スナップショットをアップロードする場合はHTTPSエンドポイント。ローカルフォルダへのエクスポートにトランスポート要件はありません。

## 詳しくは

- [Raw snapshot v1コントラクト](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [Raw record v1コントラクト](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [Raw changes v1コントラクト](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
