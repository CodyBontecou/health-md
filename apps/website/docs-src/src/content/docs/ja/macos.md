---
title: "macOSアプリ"
description: "Health.md for Macを、iPhoneのエクスポート先、ローカルCLIおよびMCPホスト、暗号化されたヘルスコンテキストストア、履歴ビューア、フォルダ権限の管理元として使用します。"
---

Health.md for Macには、次の2つのローカルな役割があります。

1. iPhoneのエクスポートジョブを受信し、選択したフォルダへファイルを書き込む。
2. ローカルエージェントが使用するループバックCLI、クエリAPI、暗号化されたヘルスコンテキスト、MCPアダプターをホストする。

Apple Healthは引き続きiPhone上にあります。MacアプリがHealthKitを直接読み取ることはありません。

## 主な領域

<div class="options">
<div class="option"><strong>同期</strong><p>Macが検出可能で、iPhoneのエクスポートジョブを受信できる状態かを表示します。</p></div>
<div class="option"><strong>出力先フォルダ</strong><p>Markdown、JSON、CSV、Bases、ロールアップ、ZIP、デイリーノートの出力用に、セキュリティスコープ付きブックマークを保存します。</p></div>
<div class="option"><strong>スケジュール</strong><p>Mac側のスケジュールと準備状況を表示します。HealthKitデータは引き続きiPhoneから提供されます。</p></div>
<div class="option"><strong>履歴</strong><p>デスクトップに書き込まれたファイルについて、エクスポート結果、永続的な進捗、エラー、再試行のコンテキストを記録します。</p></div>
<div class="option"><strong>設定</strong><p>出力先の状態、暗号化されたコンテキストの保持設定、ローカルCLIの設定を表示します。</p></div>
<div class="option"><strong>メニューバー</strong><p>Health.mdがローカルで稼働している間、ステータス、設定、アプリへすばやくアクセスできます。</p></div>
<div class="option"><strong>CLI</strong><p>同梱された<code>healthmd</code>と<code>healthmd-mcp</code>のヘルパーをインストールし、設定用プロンプトをコピーし、任意のエージェントスキルをインストールして、テスト済みのコマンドを表示します。</p></div>
</div>

## Macの出力先を設定する

1. Health.mdをMacにインストールして開きます。
2. ローカルディスク、iCloud Drive、またはObsidian Vault内の出力先フォルダを選択します。
3. iPhoneの同期タブからMac接続を有効にします。
4. iPhoneで、エクスポート先として接続中のMacを選択します。
5. エクスポートを設定し、エクスポートをタップします。

iPhoneがHealthKitデータと有効な設定のスナップショットを取得します。接続中のピアは、サイズ上限付きでチェックサム検証済みのパーティションを転送します。Macは本番用エクスポーターを使用し、要求されたファイルを書き込みます。

<div class="callout">
<strong>HealthKitの制限</strong>
<p style="margin-top:6px;">Mac単独ではApple Healthを照会できません。新しいエクスポートとエージェントコンテキストには、接続済みのiPhoneアプリが開いている必要があります。保存済みの範囲で十分な場合、キャッシュされた暗号化クエリは、新しいiPhone接続がなくても実行できます。</p>
</div>

## CLIとエージェントの設定

Macアプリの**CLI**領域を開くと、次の操作ができます。

- このアプリバンドル内にある、署名済みヘルパーの正確なパスを確認する。
- エイリアスまたは`~/.local/bin`のシンボリックリンクを作成するコマンドをコピーする。
- エージェント支援による設定用プロンプトをコピーする。
- 任意の`healthmd-cli`スキルを、選択したディレクトリにインストールする。
- 現在の状況、doctor、抽出、クエリ、睡眠、トレーニング、ワークアウト、カバレッジ、エクスポートの各コマンドを確認する。
- 一般的な準備状況エラーを確認する。

ユーザーの操作なしに、アプリがシェルの起動ファイルを編集したり、システムディレクトリへインストールしたりすることはありません。

まず、次を実行します。

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

バックエンドの選択については[Health.md CLI](/ja/docs/cli/)、クエリアーキテクチャについては[ローカルエージェント](/ja/docs/agents/)をご覧ください。

## 暗号化されたヘルスコンテキスト

新しいクエリとエビデンスの要求では、専用のコンテキスト取得モードを使用します。iPhoneは、要求された指標、ソース、日付、詳細範囲だけを正確に読み取ります。エクスポートファイルを作成したり、保存済みのエクスポート設定を変更したりすることはありません。

Macは、所有者ごとの各日を、個別に認証されたAES-256-GCM blobとして保存します。「このデバイスのみ」かつ「ロック解除時」のKeychain項目に、ランダムな暗号化キーを保持します。ファイル名はランダムで、日付や指標名は分かりません。

設定には、暗号化された所有者日数と日付範囲が表示されます。保持期間は、互いに独立した2つの操作で管理します。

- **古いコンテキストを削除**では、選択した境界より前の所有者日を削除します。
- **暗号化されたコンテキストをすべて削除**では、すべてのコンテキストファイルと専用Keychainキーを削除します。

コンテキストの保持操作によって、Apple Healthデータ、エクスポートファイル、Macの出力先ブックマーク、接続済みプロバイダの認証情報が削除されることはありません。

## ループバックAPIの境界

Macアプリは、ローカルの状況、エクスポート、クエリ、エビデンス、更新、永続ジョブの各ルート用に、`127.0.0.1`と`::1`のポート`17645`で待ち受けます。

Bearerトークンやエージェント登録はありません。アプリが開いている間は、任意のローカルプロセスがAPIを呼び出せます。このポートをほかのマシンへ公開、プロキシ、トンネルしないでください。

サンドボックス化された`healthmd-mcp`ヘルパーは、正規のHTTPループバックエンドポイントだけを受け入れます。また、シェル、任意のファイル、SQL、URL取得、resources、prompts、roots、samplingを使用しないツールを提供します。

## Direct CLI Accessは別の機能です

iPhoneの**Direct CLI Access**設定は、Direct対応CLIとiPhoneの間に、別の信頼関係を作成します。生データのエクスポート、正規の抽出、生成済みファイル、状況確認、再開、キャンセルでは、Macアプリを迂回できます。

Directモードは、Macアプリの暗号化されたクエリコンテキストを使用しません。代わりに、ポータブルな`healthmd mcp serve`は、ペアリング時と同じ実行ファイルIDを使用して、前面表示中のiPhoneに対し新しい型付きクエリを直接実行します。ペアリングと対応プラットフォームについては、[Direct iPhone CLI](/ja/docs/cli-direct/)をご覧ください。

## 関連項目

<div class="related">
  <a href="/ja/docs/sync/"><span>出力先</span>Mac同期：iPhoneとMacをペアリングし、ローカルにファイルをエクスポートします。</a>
  <a href="/ja/docs/cli/"><span>ターミナル</span>Health.md CLI：ヘルパーをインストールし、バックエンドを選択してコマンドを実行します。</a>
  <a href="/ja/docs/agents/"><span>ローカルコンテキスト</span>エージェント：範囲を限定した取得、暗号化ストレージ、エビデンス、保持。</a>
  <a href="/ja/docs/mcp/"><span>ツール</span>ローカルMCPサーバー：設定、ツールカタログ、サンドボックス境界。</a>
  <a href="/ja/docs/scheduling/"><span>ワークフロー</span>スケジュール：定期的なエクスポートを自動化します。</a>
</div>
