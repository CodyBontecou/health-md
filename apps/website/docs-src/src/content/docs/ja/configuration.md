---
title: エージェントを設定
description: Health.mdのMCPまたはCLIインターフェースを選択し、Codex、Claude、または別のローカルクライアントを設定して、HealthKitをクラウドサービス経由にせず、ペアリング済みのiPhoneに接続します。
---

リリース済みのMacアプリには、型付きエージェントツール用の`healthmd-mcp`と、明示的なCLIワークフロー用の`healthmd`という、2つの署名済みローカルヘルパーが含まれています。iPhoneへの直接MCP接続に対応する別のクロスプラットフォームCLIは、最初の公開パッケージが実機リリースQAを完了するまでプレビューとして記載されています。

<div class="callout">
<strong>HealthKitはiPhone内にとどまります</strong>
<p style="margin-top:6px;">設定により、ローカルクライアントはHealth.mdの範囲が限定されたインターフェースへアクセスできます。コンピューターやエージェントにHealthKitへの直接アクセスを許可するものではなく、ソースライブラリをHealth.mdのクラウドへアップロードするものでもありません。</p>
</div>

## インターフェースを選択

| 目的 | 最初に使用 | 続き |
|---|---|---|
| CodexまたはClaudeからMac上のヘルスデータを照会し、グラフ化する | 同梱の`healthmd-mcp`をstdioで使用 | [MCPサーバーとツール](/ja/docs/mcp/) |
| Macのスクリプトで正規JSONまたは生成ファイルをエクスポートする | 同梱の`healthmd` CLI | [CLI](/ja/docs/cli/) |
| Macアプリを使用せず、開いているiPhoneに直接接続する | ポータブルな直接CLI（**プレビュー**） | [iPhoneへの直接アクセス](/ja/docs/cli-direct/) |
| 厳密なリクエストおよびレスポンスエンベロープを利用して開発する | ループバックAPIまたは公開コントラクト | [ループバックAPI](/ja/docs/agent-api/) |
| スキーマ、レコード、エビデンス、生成済みフィクスチャを解析する | バージョン管理されたリファレンス | [データコントラクト](/ja/docs/reference/) |

バックエンドと転送方式は明示的に選択します。Health.mdがiPhoneへの直接アクセスからMacアプリへ暗黙にフォールバックすることはありません。

## MacアプリでCodexを使用

<div class="availability available">
<strong>提供中 · 署名済みMacヘルパー</strong>
<p>Health.md for Macをインストールして<strong>CLI</strong>画面を開き、アプリが<code>/Applications</code>にない場合は、表示された同梱MCPパスをコピーします。</p>
</div>

独立した署名済み`healthmd-mcp`ヘルパーを`~/.codex/config.toml`に追加します。

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Codexを再起動し、`healthmd_doctor`、`healthmd_metrics`の順に呼び出してから、`healthmd_metric_chart`などの小規模な型付きツールを1つ呼び出します。同梱サーバーは、Macの準備状況、暗号化コンテキストの更新ジョブ、エビデンス、可視化を含む21個のツールを公開します。

## MacでClaude DesktopまたはClaude Codeを使用

同梱ヘルパーをClaude DesktopのMCP設定、または信頼済みのClaude Code `.mcp.json`に追加します。

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

設定を変更した後、クライアントを再起動します。プロジェクトスコープの設定でも、ワークスペースの信頼と明示的なサーバー承認が必要です。ツールが新しいHealthKitデータを必要とするときは、MacとiPhoneのアプリを開いたままにしてください。

## Mac上の任意のstdio MCPクライアント

ローカルプロセスを1つ設定します。

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

ホストがstdinとプロセスのライフサイクルを管理します。ヘルパーを通常の対話型コマンドとして起動したり、JSON-RPC出力を変更するシェルでラップしたりしないでください。MCPの`tools/list`を使用して、インストール済みアプリが公開する厳密なスキーマを確認します。

## ポータブル直接接続のセットアップ

<div class="availability preview">
<strong>プレビュー · 未公開パッケージ</strong>
<p>クロスプラットフォームRust CLI、<code>healthmd setup codex</code>、同一バイナリの<code>healthmd mcp serve</code>、Linux/Windowsの直接ペアリングは実装済みですが、最初の品質確認済み公開リリースを待っています。</p>
</div>

公開後は、`healthmd setup codex`でCodexを冪等に設定し、iPhoneへの直接ペアリングを開始できるようになります。それまでは、未公開のHomebrew、crates.io、インストーラ、GitHubリリースURLに依存しないでください。[iPhoneへの直接アクセスCLI](/ja/docs/cli-direct/)のページに、段階的な転送方式とプロトコルの動作が記載されています。

## 明示的なCLIワークフロー

正規抽出またはファイル指向の自動化では、MCPホストに大きなソース本文を運ばせるのではなく、`healthmd`を直接呼び出します。

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

利用可否と構文は、同梱のMacヘルパーとスタンドアロンのクロスプラットフォームCLIで異なります。無人の自動化にコマンドをコピーする前に、[Health.md CLI](/ja/docs/cli/)を確認してください。

## ポータブル版のペアリングと準備状況

<div class="availability preview">
<strong>プレビュー · ポータブル直接接続ワークフロー</strong>
<p>以下の手順は、今後公開予定のクロスプラットフォームパッケージについて説明しています。リリース済みの同梱Mac MCPパスは、Macアプリの既存のiPhone接続を使用します。</p>
</div>

直接MCPおよびCLIワークフローでは、iPhone版Health.mdとの信頼済みペアリングを一度行う必要があります。ペアリングには認証済みの暗号化チャネルと、macOS、Linux、またはWindowsのネイティブ認証情報ストレージを使用します。

1. iPhone版Health.mdで**Direct CLI Access**を有効にします。
2. `healthmd setup codex`または`healthmd direct pair`からペアリングを開始します。
3. iPhoneで範囲が限定されたペアリングリクエストを承認します。
4. クエリまたはエクスポートを開始するときは、Health.mdを前面に表示したままにします。
5. 大規模な処理の前に、MCPで`healthmd_doctor`、またはポータブルCLIで`healthmd status`を呼び出します。

Manual IP、Tailscale、ポート、信頼済みデバイス、前面表示、復旧の詳細は、[iPhoneへの直接アクセス](/ja/docs/cli-direct/)を参照してください。

## 設定の境界

ローカルエージェントの設定によって、以下が許可されることは**ありません**。

- 任意のHealthKit読み取りまたは書き込み。
- 任意のファイルシステムアクセス。
- MCPを介した任意のURL、シェルコマンド、プロンプト、ルート、サンプリング。
- 欠損、カバレッジ、単位、エビデンス、制限を隠すこと。
- 適用される承認なしに、生成ファイルを再開、キャンセル、上書きすること。

完全な結果を得るには、プロセスの成功だけでなく、要求したスコープ、カバレッジ、ページ走査、制限事項、ソーススキーマを確認してください。

## 続き

<div class="related">
  <a href="/ja/docs/mcp/"><span>ツールインターフェース</span>利用可能な21個のMacツール、ポータブル版の17ツールのプレビュー、MCP Apps、スキーマ、ページング、エクスポート、サンドボックスの境界を確認します。</a>
  <a href="/ja/docs/agent-queries/"><span>最初の質問</span>型付きの指標、睡眠、ワークアウト、比較、カバレッジ、エビデンスのワークフローを実行します。</a>
  <a href="/ja/docs/cli-extract/"><span>正規データ</span>大きな本文をチャットに含めず、選択したschema-v7ドキュメントとソースレコードを抽出します。</a>
  <a href="/ja/docs/reference/"><span>コントラクト</span>バージョン管理されたデータ構造、フィールド一覧、生成済みフィクスチャ、統合レシピを参照します。</a>
</div>
