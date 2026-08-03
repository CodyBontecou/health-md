---
title: "Mac同期"
description: "macOSコンパニオンをローカルの出力先として使用します。iPhoneがHealthKitデータと設定を取得し、Macが要求されたファイルをレンダリングして書き込みます。"
---

## 概要
<p>Mac同期を使うと、Mac自体をHealthKitリーダーにすることなく、Macでエクスポートを作成できます。Apple Healthデータの信頼できる情報源は引き続きiPhoneです。iPhoneが選択した日次データと設定の正確なスナップショットを取得し、そのジョブをMacに転送します。Macは共有エクスポーターを使ってパスを計画し、要求された形式をレンダリングして、選択した出力先フォルダにファイルを書き込みます。</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Mac同期のエクスポートフロー">
    <span><strong>iPhone</strong>HealthKitデータを取得し、有効な設定のスナップショットを作成します。</span>
    <span><strong>ローカルネットワーク</strong>バージョン管理されたジョブを近くのMacアプリへ転送します。</span>
    <span><strong>Mac</strong>選択された形式をレンダリングし、指定されたフォルダに書き込みます。</span>
    <span><strong>Vault</strong>Obsidian、iCloud Drive、または任意のローカルフォルダに最終的なエクスポートが保存されます。</span>
  </div>
</div>

## 有効にする方法
<ol>
<li>macOSアプリをインストールして開きます。</li>
<li>Macで出力先フォルダを選択し、Health.mdに書き込み権限を付与します。</li>
<li>iPhoneで同期タブを開き、Mac接続を有効にします。</li>
<li>iPhoneのエクスポートタブに戻り、<em>接続中のMac</em>を選択してエクスポートを設定し、エクスポートをタップします。</li>
</ol>

## 転送される内容
<ul>
<li>日付範囲と有効な設定を記述した、バージョン管理されたエクスポート要求</li>
<li>iPhoneがHealthKitデータを取得している間の進捗メッセージと機能情報</li>
<li>取得した日次データと、ファイル書き込みジョブ用の正確な設定スナップショットを運ぶ、サイズ上限付きでチェックサム検証済みのフレーム</li>
<li>完了、一部完了、失敗、拒否、利用不可のいずれかを示す構造化された結果</li>
</ul>
<p>アカウントやリモートのヘルスデータクラウドは必要ありません。近距離同期では暗号化されたMultipeer Connectivityを使用し、手動IP／Tailscaleではペアリング済みの暗号化されたNetwork.frameworkトランスポートを使用します。両方のデバイスが互いに到達できる必要があり、HealthKitを読み取るのは常にiPhoneです。</p>

## 使用する場面
<div class="options">
<div class="option"><strong>デスクトップ専用Vault</strong><p>Obsidian VaultがMacにしかない場合、iPhoneのHealthKitからMac上のファイルへ送るための最も明快な方法です。</p></div>
<div class="option"><strong>大規模なバックフィル</strong><p>iPhoneでHealthKitの読み取りとエクスポート設定を行いながら、最終ファイルをデスクトップのディスクに保存できます。</p></div>
<div class="option"><strong>ローカルアーカイブのワークフロー</strong><p>macOS上でバックアップ、バージョン管理、インデックス作成の対象となるフォルダへ直接書き込めます。</p></div>
</div>

<div class="callout">
<strong>ローカルネットワークが必要です</strong>
<p style="margin-top:6px;">両方のデバイスが近くにあり、ローカルネットワークの使用を許可されている必要があります。携帯電話回線だけを使用しているiPhoneは、Macの出力先を検出できません。準備状況にMacでの対応が必要と表示された場合は、Macアプリを再度開き、出力先フォルダを選び直してください。</p>
</div>

## Mac同期とDirect CLI Accessは別の機能です

Mac同期では、出力先へのエクスポートと暗号化されたエージェントコンテキストのために、iPhoneとHealth.md for Macをペアリングします。Direct CLI Accessでは、別の信頼ドメインを通じてiPhoneとコマンドライン環境をペアリングします。直接接続モードではMacアプリなしで生データまたは生成済みファイルをエクスポートできますが、Macの暗号化されたクエリインデックスやMCPは利用できません。

iPhone側の個別設定を有効にする前に、[Direct iPhone CLI](/ja/docs/cli-direct/)をご覧ください。

## 関連項目

<div class="related">
  <a href="/ja/docs/macos/"><span>デスクトップ</span>macOSアプリ — Mac上のエクスポート、スケジュール、履歴。</a>
  <a href="/ja/docs/scheduling/"><span>ワークフロー</span>スケジュール — 定期的なエクスポートを自動化します。</a>
  <a href="/ja/docs/cli-direct/"><span>別の信頼関係</span>Direct iPhone CLI — Macアプリを経由せずにCLIをペアリングします。</a>
  <a href="/ja/docs/reference/connected-mac-iphone-protocol/"><span>プロトコル</span>接続中のMac–iPhoneリファレンス — 機能、要求、制限付き転送、結果。</a>
</div>
