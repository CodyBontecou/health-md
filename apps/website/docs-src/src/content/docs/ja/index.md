---
title: Health.mdを始める
description: Apple HealthまたはHealth Connectのデータをエクスポートし、署名済みのMacヘルパーをローカルエージェントに接続して、バージョン管理されたHealth.mdコントラクトを利用した開発を始めます。
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">提供中 · 署名済みMacヘルパー</p>
    <p>スマートフォンからヘルスデータをエクスポートしたり、署名済みのMacヘルパーを介してローカルエージェントを接続したり、バージョン管理されたコントラクトを利用して開発したりできます。HealthKitの読み取りはiPhone上で、Health Connectの読み取りはAndroid上で完結します。</p>
    <div class="docs-command" aria-label="Health.mdに同梱された準備状況確認コマンド"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">別の場所にインストールした場合は、<strong>Health.md for Mac → CLI</strong>から同梱ヘルパーのパスをコピーしてください。</p>
    <div class="docs-actions">
      <a class="docs-button" href="/ja/docs/iphone-first-export/">最初のiPhoneエクスポート</a>
      <a class="docs-button-secondary" href="/ja/docs/configuration/">エージェントを接続</a>
      <a class="docs-button-secondary" href="/ja/docs/reference/">コントラクトを見る</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Health.mdで行うことを選択">
  <a href="/ja/docs/iphone-first-export/"><span>01 · エクスポートする</span><strong>iPhoneから始める</strong>Apple Healthを許可し、フォルダを選択して出力をプレビューし、最初のエクスポートを実行します。</a>
  <a href="/ja/docs/configuration/"><span>02 · 質問する</span><strong>ローカルエージェントを接続</strong>署名済みのMac MCPヘルパーをCodex、Claude、または別のstdioクライアントで使用します。</a>
  <a href="/ja/docs/reference/"><span>03 · 開発する</span><strong>安定したコントラクトを利用</strong>スキーマ、レコード、エビデンス、生成済みフィクスチャ、厳密なエンベロープを統合します。</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>Macに同梱されたMCPツール</span></div>
<div><strong>4</strong><span>エクスポート形式</span></div>
<div><strong>v7</strong><span>公開エクスポートスキーマ</span></div>
<div><strong>0</strong><span>Health.mdクラウドを経由する必須処理</span></div>
</div>

<p class="docs-section-kicker">提供中 · macOS</p>

## 5分でローカルエージェントを開始

MacでHealth.mdを開き、ペアリング済みのiPhoneでもHealth.mdを開いて接続されるまで待ちます。同梱ヘルパーを使い、ヘルスデータの値を返さずに準備状況を確認し、Sleep指標を一覧表示して、1日分のクエリを実行します。

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

準備が完了した`doctor`の結果は`healthmd.cli_doctor`スキーマを使用し、セットアップが未完了の場合は次に行う操作を含みます。CodexまたはClaudeを使用する場合は、[エージェントを設定](/ja/docs/configuration/)へ進み、独立した署名済み`healthmd-mcp`ヘルパーをクライアントに指定してください。

<p class="docs-section-kicker">目的から選ぶ</p>

## 設定と接続

<div class="related">
  <a href="/ja/docs/configuration/"><span>提供中 · Mac</span>設定 — Codex、Claude、または別のstdioクライアントを署名済みMCPヘルパーに接続します。</a>
  <a href="/ja/docs/mcp/"><span>提供中 · Mac</span>MCPサーバーとApp — 同梱された21個のツールを確認し、プライベートな可視化をレンダリングして、ポータブル版プレビューを理解します。</a>
  <a href="/ja/docs/cli/"><span>提供中 · Mac</span>Health.md CLI — 同梱ヘルパーをインストールし、準備状況を確認してデータを照会し、ポータブル版プレビューとの違いを理解します。</a>
  <a href="/ja/docs/agents/"><span>アーキテクチャ</span>エージェントコンテキスト — リクエストのスコープ、ローカルの信頼、暗号化されたコンテキスト、エビデンス、保持、プライバシーについて説明します。</a>
</div>

<p class="docs-section-kicker">日常的な操作</p>

## 照会、抽出、自動化

<div class="related">
  <a href="/ja/docs/agent-queries/"><span>型付きクエリ</span>指標、睡眠セッション、ワークアウト、比較、カバレッジ、事実に基づくエビデンスを照会します。</a>
  <a href="/ja/docs/cli-direct/"><span>プレビュー · ポータブルCLI</span>iPhoneへの直接アクセス — スタンドアロンパッケージの公開前に、Manual IPまたはTailscaleのペアリングを理解します。</a>
  <a href="/ja/docs/cli-extract/"><span>ソースデータ</span>正規抽出 — 選択したschema-v7の日付、ソースレコード、プロジェクション、またはJSONLを取得します。</a>
  <a href="/ja/docs/cli-jobs/"><span>信頼性の高い実行</span>永続ジョブ — タイムアウト、不明な結果、再開、キャンセル、部分的な結果を安全に処理します。</a>
  <a href="/ja/docs/agent-api/"><span>低レベル</span>ループバックAPI — 厳密なクエリ、エビデンス、カーソル、更新、永続ジョブのルートを使用します。</a>
  <a href="/ja/docs/reference/integration-recipes/"><span>パターン</span>統合レシピ — コントラクトを弱めずにHealth.mdの出力を解析、検証します。</a>
</div>

<p class="docs-section-kicker">安定したインターフェース</p>

## データコントラクトと構造

<div class="related">
  <a href="/ja/docs/reference/"><span>コントラクトマップ</span>エクスポートリファレンス — スキーマ、指標、形式、レコード、相互運用性フィクスチャを参照します。</a>
  <a href="/ja/docs/reference/api-and-cli/"><span>自動化</span>APIとCLIのコントラクト — エンベロープ、ルート、終了動作、生成済みの例を確認します。</a>
  <a href="/ja/docs/reference/evidence-packets/"><span>エージェント結果</span>クエリとエビデンス — 型付き値、カバレッジ、欠損、操作、決定論的IDを理解します。</a>
  <a href="/ja/docs/reference/daily-records/"><span>スキーマv7</span>日次レコード — 公開ソースドキュメントとその所有権ルールを理解します。</a>
  <a href="/ja/docs/shared-metric-registry/"><span>語彙</span>指標レジストリ — 安定したクロスプラットフォームの指標ID、カテゴリ、単位、プロファイルメタデータを使用します。</a>
  <a href="/ja/docs/reference/generated/"><span>機械可読</span>生成済みアーティファクト — 正規フィールド、フィクスチャ、メッセージ一覧、CLIコントラクトを開きます。</a>
</div>

<p class="docs-section-kicker">製品ワークフロー</p>

## アプリとエクスポート

<div class="related">
  <a href="/ja/docs/iphone-first-export/"><span>ここから開始 · iPhone</span>最初のエクスポート — Apple Healthを許可し、フォルダを選択して出力をプレビューし、書き込まれたファイルを確認します。</a>
  <a href="/ja/docs/android/"><span>Android</span>Health Connect — ドキュメントプロバイダのフォルダを選択し、プラットフォームの自動化を設定します。</a>
  <a href="/ja/docs/export/"><span>ファイル</span>エクスポート — Markdown、CSV、JSON、またはObsidian Basesで明示的な日付範囲をエクスポートします。</a>
  <a href="/ja/docs/format/"><span>構造</span>形式のカスタマイズ — 単位、日付、frontmatter、ファイル名、書き込み動作を制御します。</a>
  <a href="/ja/docs/scheduling/"><span>バックグラウンド</span>スケジュール — 日次および週次のエクスポート動作とプラットフォームの制約を理解します。</a>
  <a href="/ja/docs/shortcuts/"><span>自動化</span>ショートカットとApp Intents — Appleのワークフローからエクスポート、要約、ステータス確認を実行します。</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">ドキュメント構成の更新日：2026-08-02</p>
