---
title: "iPhone直接接続CLI"
description: "Manual IP、Tailscale、または対応するNearby転送でhealthmdをiPhoneとペアリングし、Health.md for Macを起動せずにエクスポートします。"
---

直接接続バックエンドは、コマンドをHealth.md for Mac経由で送ることなく、`healthmd`を開いているiPhone版Health.mdへ接続します。iPhoneがHealthKitを読み取り、保護されたストレージへ結果を準備して、検証済みのパーティションをCLIへ転送します。

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>プレビュー · ポータブル直接接続CLI</strong>
<p>同梱のSwift直接接続バックエンドはmacOSで利用できます。クロスプラットフォームのRustクライアントは、実機iPhoneでのリリースQAと最初の公開パッケージを待つアルファ版です。LinuxとWindowsのコマンドは、段階的に提供予定のワークフローを説明しています。</p>
</div>

## 直接接続モードの対応機能

- 1回限りのペアリングと信頼済みの再接続
- ローカルの信頼済みデバイスの確認とペアリング解除
- iPhoneのリアルタイムな準備状況
- 厳密な生のschema-v7エクスポート
- 選択範囲の正規抽出
- 本番エクスポーターによるファイル生成
- ローカル永続ジョブの状態確認と再開
- 明示的なキャンセル
- 同じ実行ファイルによる`healthmd mcp serve` stdioサーバー。iPhone直接接続の型付きクエリ、指標カタログ、エビデンス、MCP Apps UI、PNGフォールバックに対応

`healthmd`コマンドの直接接続バックエンドは、Macアプリの暗号化コンテキスト用HTTPルートをエミュレートしません。このため、Mac向けの`doctor`、query、evidence、refreshサブコマンドは、バックエンドを切り替えずに`backend_unsupported`を返します。iPhone直接接続で新規の型付き分析を行うには`healthmd mcp serve`を使用します。Codexの設定とペアリングを自動で行うには、`healthmd setup codex`を実行します。`healthmd mcp schema [TOOL]`は、ネストしたMCP入力スキーマと例をローカルに正確に出力します。睡眠には`healthmd_sleep_sessions`を直接使用し、正規の`extract`出力を型付きクエリAPIとして扱わないでください。

## 要件

- 直接接続に対応する`healthmd`バイナリと、対応するiPhone版Health.mdのビルド
- ペアリング時と新しいコマンドの開始時に、iPhoneでHealth.mdが前面表示されていること
- iPhoneの**設定 > Mac同期 > Direct CLI Access**が有効であること
- HealthKit権限、保護されたデータ、ローカルネットワーク権限、エクスポート利用枠を使用できること
- Manual IPでは、到達可能なコンピューターのアドレスとTCPポート`17647`。Tailscaleアドレスも使用可能
- 生成ファイルモードでは、既存の絶対パスの保存先

CLIがリスナーになります。iPhoneは、Direct CLI Accessに入力したコンピューターのアドレスへ接続します。

## 対応する転送方式

| 転送方式 | macOS同梱のSwiftヘルパー | ポータブルRustクライアント |
|---|---:|---:|
| LAN上のManual IP | 対応 | macOS、Linux、Windows |
| Tailscaleアドレス | 対応 | macOS、Linux、Windows |
| Nearby / MultipeerConnectivity | 対応 | 非対応 |

Nearbyでは、Appleの暗号化されたMultipeerセッションに加え、Manual IPと同じHealth.mdアプリケーション認証および暗号化を使用します。ポータブルクライアントでNearbyを指定すると、`transport_unsupported`が返されます。

## Manual IPで一度ペアリングする

コンピューターでリスナーを起動します。

```bash
healthmd direct pair --transport manual-ip
```

コマンドは、6桁のコード、候補となるコンピューターのアドレス、リスナーポートを標準エラー出力へ出力し、標準出力は最終的なJSON結果のために空けておきます。

iPhoneでは、次の手順を行います。

1. **Health.md >設定 > Mac同期 > Direct CLI Access**を開きます。
2. Direct CLI Accessを有効にします。
3. **Manual IP**を選択します。
4. コンピューターのLANアドレスまたはTailscaleアドレスを入力します。
5. ポート`17647`を入力します。CLIで別のグローバル`--port`を使用している場合は、そのポートを入力します。
6. ペアリングコードを入力し、「ペアリング」をタップします。
7. 両方で成功が報告されるまで、アプリを開いたままにします。

ペアリングコードの有効期限は10分です。ネットワーク経由で送信されることも、保存されることもありません。

必要に応じて別のポートを使用します。

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

以後のstatus、export、resume、cancelコマンドでも、同じポートを明示してください。

## Nearbyでペアリングする

Nearbyは、同梱のSwiftヘルパーでのみ利用できます。

```bash
healthmd direct pair --transport nearby
```

iPhoneのDirect CLI AccessでNearbyを選択し、表示されたコードを入力して、ペアリングが終わるまで両方のデバイスを開いたままにします。Nearbyの操作に失敗しても、Manual IPへ切り替わることはありません。

## 信頼済みデバイス

ペアリングでは、Health.md Macアプリの同期関係とは別の信頼関係が作成されます。

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

これらのコマンドはローカルの信頼情報を読み取り、または変更するだけで、iPhoneには接続しません。iPhone側では、**ペアリング済みCLIを削除**を使用して相手側を削除します。

複数のiPhoneを信頼している場合は、対象のインストールを明示的に選択します。

```bash
healthmd --backend direct --device DEVICE_UUID status
```

`healthmd direct reset-trust --confirm`は、ローカルの信頼情報が破損しているか、交換前のインストールに属している場合にだけ使用してください。ローカルの直接ペアリングがすべて削除されます。最初からやり直す前に、iPhone側でもそれらのペアリングを削除してください。

## リアルタイムの準備状況を確認する

```bash
healthmd --backend direct --transport manual-ip status
```

直接接続のstatusレスポンスは、ヘルスデータの値を含めず、接続状態と安全性の状態を報告します。作業を始める前に、次のフィールドを確認してください。

| フィールド | 準備完了の値 |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | 新しい処理では`true` |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | 生データと抽出では`true` |
| `iphone.can_trigger_exports` | 生成ファイルでは`true` |

直接接続のstatusでは、保存先は未選択のままです。ファイルモードで使用するのは、コマンドに明示した`--destination`だけです。

## 厳密な生データエクスポート

範囲セレクターを1つ選択します。

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

検証済みJSONを標準出力へストリームするには、`--output`を省略します。機密性の高いレスポンスや大きなレスポンスでは、出力ファイルを使用する方が安全です。

厳密な生データエクスポートは`healthmd.raw_result` v1を返します。この結果には、通常のschema-v7 `healthmd.health_data`日次データと、その正規ソースアーカイブが含まれます。iPhoneに保存済みの設定を変更せず、一時的にロスレス詳細を要求します。CLIは結果を公開する前に、正確な日付、プロファイル、スキーマ、アーカイブ、マニフェスト、ダイジェストチェーン、最終本文ダイジェスト、完了状態を検証します。

完全だが空の日は成功です。要求したデータが欠損、一部完了、失敗、キャンセル、未対応、スキップの場合は、`partial_success`とゼロ以外の終了コードになります。`--allow-partial`を明示した場合に限り、この終了動作を許容できます。

## 正規抽出

直接抽出は、同じ永続的な生データ転送を使用しますが、転送ラッパーではなく、選択したソースに近い形式のデータを返します。

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

指標、カテゴリ、ソース、詳細レベルの選択は、HealthKitを読み取る前にiPhoneへ到達します。オブジェクトセレクター、JSON Pointer、JSONL、レシートについては、[正規抽出](/ja/docs/cli-extract/)を参照してください。

## 本番エクスポーターによる生成ファイル

直接ファイルモードでは、iPhoneへHealth.mdの本番エクスポーターを実行するよう要求し、生成されたファイルを明示したコンピューターの保存先へ転送します。

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

保存先は、既存の絶対パスで、シンボリックリンクを経由して解決されないものに限ります。直接接続モードは、Macアプリのブックマークを推測したり使用したりしません。`--output`は生データまたは抽出結果の出力に、`--destination`は生成ファイルの保存先に使用します。

既定のリクエストでは、保存済みの形式、Healthサブフォルダ、ファイル名、テンプレート、書き込みモード、デイリーノートへの挿入、デイリーノートのみの設定を維持します。そのジョブでは、ロールアップとサマリーのみのモードを抑制します。繰り返し指定できる`--metric`または`--category`と`--detail`は、そのジョブの指標スコープと詳細スコープだけを置き換えます。`--use-iphone-settings`は保存済み設定をすべて反映し、セレクターとは併用できません。

iPhoneは、JSON、CSV、Markdown、ZIP、データ辞書、ロールアップ、個別レコード、デイリーノート、プロバイダサイドカーを準備できます。CLIはコミット前に、各相対パス、バイト数、ダイジェスト、ファイルマニフェスト、保存先ID、リクエストフィンガープリントを検証します。パストラバーサル、シンボリックリンクを含む祖先パス、ルートの変更、パスの衝突、ダイジェストの変化を拒否します。上書きはアトミックです。追記とMarkdownマージでは保存済みの計画を使用するため、リプレイで内容が重複することはありません。

生成ファイルの保存先はmacOSとLinuxで利用できます。プロトコルv1ではWindows上の保存先を拒否します。Windowsの直接接続ユーザーは、生データエクスポートと抽出を使用できます。

## 前面表示とバックグラウンドでの動作

ペアリングと新しい処理の開始時は、iPhoneアプリを前面に表示する必要があります。Direct CLI AccessによってiOSがヘッドレスなエクスポートサーバーになることはなく、必要に応じてアプリを起動することもできません。

エクスポートが接続済みの状態でアプリがバックグラウンドへ移動すると、Health.mdは、限られたiOSバックグラウンド実行時間を要求します。その時間内にエクスポートが完了する場合があります。iOSによって実行時間が終了されると、接続が閉じ、永続ジョブが一時停止します。Health.mdを再度開き、同じジョブを再開してください。

iPhoneは、直接接続の処理中に全体アクティビティバナーを表示します。ヘルスデータの値は表示せず、取得と転送のフェーズ、完了した日数、バイト単位の進捗、一時停止または完了の状態を示します。

## 永続ジョブの再開とキャンセル

直接接続ジョブは、作成から7日後に期限切れになります。タイムアウト、Ctrl-C、プロセス終了、切断、バックグラウンド実行時間の終了によって、ジョブがキャンセルされることはありません。

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

再開時には、元の日付、設定、保存先、リクエストフィンガープリント、デバイス、パーティションの進行地点を維持します。ファイルジョブの再開時に、別の保存先を指定することはできません。

キャンセル要求は永続的に記録されますが、キャンセルが終端状態になるのはiPhoneが確認応答した後だけです。iPhoneを利用できない場合、statusは`cancellation_pending`のままです。同じiPhoneを再度開き、cancelを再試行してください。

## セキュリティモデル

- ペアリングでは、一時的なCurve25519鍵共有と、6桁のコードに紐づくトランスクリプト証明を使用します。
- 再接続では、保存済みのランダムなシークレットと両方のインストールIDを証明します。
- 接続ごとに新しい鍵とnonceを導出します。
- メッセージとバイナリフレームでは、単調増加するシーケンス検証を備えたChaCha20-Poly1305を使用します。
- パーティションでは、SHA-256マニフェストと連鎖ダイジェストの進行地点を使用します。
- iPhoneの信頼情報はKeychainに保存されます。
- ポータブル版の信頼情報はKeychain、Secret Service、またはWindows Credential Managerを使用し、平文へフォールバックしません。
- スプールとジャーナルはアプリ専用ストレージを使用し、プラットフォームが対応している場合はバックアップから除外します。

Manual IPは、ローカルネットワークまたはTailscale上でも暗号化されます。Tailscaleはネットワーク経路も保護しますが、Health.mdのアプリケーション認証を置き換えるものではありません。

## 一般的なエラー

| エラー | 対処方法 |
|---|---|
| `direct_not_paired` | このCLIインストールをiPhoneとペアリングします。 |
| `direct_device_selection_required` | 対象の信頼済み`--device`を指定します。 |
| `direct_trust_invalid` | 診断情報を保持します。復旧できない場合に限り、信頼情報をリセットします。 |
| `direct_iphone_unavailable` | アプリの前面表示状態、アクセストグル、アドレス、ポート、権限、LANまたはTailscaleの到達可能性を確認します。 |
| `direct_export_paused` | ジョブを確認し、iPhoneを再度開いて再開します。 |
| `direct_cancellation_pending` | ペアリング済みiPhoneを再度開き、cancelを再試行します。 |
| `transport_unsupported` | ポータブルクライアントではManual IPまたはTailscaleを使用します。 |
| `backend_unsupported` | query、evidence、doctor、metrics、MCPにはMacアプリのバックエンドを使用します。 |
| `invalid_direct_raw_response` | 出力を使用しないでください。検証の診断情報を保持します。 |
| `invalid_direct_file_receipt` | ファイルを手作業で修復しないでください。ジョブを確認して再開します。 |
| `job_expired` | 7日間の状態保持期間が終了しました。新しい処理を始める前に確認します。 |

## 関連項目

<div class="related">
  <a href="/ja/docs/cli/"><span>概要</span>Health.md CLI：同梱ヘルパーをインストールし、適切なバックエンドを選択します。</a>
  <a href="/ja/docs/cli-extract/"><span>データ</span>正規抽出：ソースに近い形式のHealth.mdデータを選択して出力します。</a>
  <a href="/ja/docs/cli-jobs/"><span>信頼性</span>永続ジョブと自動化：再開、キャンセル、部分的な結果、スクリプト処理。</a>
  <a href="/ja/docs/reference/connected-mac-iphone-protocol/"><span>プロトコル</span>接続中のMacとiPhoneのリファレンス：機能、上限付き転送、結果の状態。</a>
</div>
