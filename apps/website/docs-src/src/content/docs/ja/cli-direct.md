---
title: "スマートフォン直接接続CLI"
description: "Manual IPまたはTailscaleでhealthmdをiPhoneまたはAndroidスマートフォンとペアリングし、Health.md for Macを起動せずにエクスポートします。"
---

直接接続バックエンドは、コマンドをHealth.md for Mac経由で送ることなく、`healthmd`を開いているiPhoneまたはAndroidのHealth.mdアプリへ接続します。スマートフォンは各プラットフォームのヘルスデータストア（iPhoneではHealthKit、AndroidではHealth Connect）を読み取り、結果を保護されたストレージへ準備して、検証済みのパーティションをCLIへ転送します。

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>プレビュー · ポータブル直接接続CLI</strong>
<p>同梱のSwift直接接続バックエンドはmacOSで利用でき、iPhoneとペアリングします。Androidのペアリング（プロトコルv2）は、公開パッケージ化されたクロスプラットフォームRustプレビューの一部です。実機iPhoneとAndroidでのリリースQAは未完了であり、LinuxとWindowsのコマンドは明示的に未認定のワークフローを説明しています。</p>
</div>

## 0.1.0-alpha.3のモバイル互換性

この独立した表が、明示的に未認定のプレビューで使用する互換性マトリックスです。認定済みの公開CLI／モバイルの組み合わせはまだありません。

| モバイルソース | プロトコル | 正確なtag-SHA対応版／未認定の互換性下限 | ポータブルRust操作 | 公開状態 |
|---|---|---|---|---|
| エクスポート対応iPhone | セレクタ1 / v1 | iOS 3.2.1（ビルド202608300209）/ iOS 3.0.3 | 状態、生データ、抽出、ファイル、再開、キャンセル | 実機認定待ち |
| クエリ対応iPhone | セレクタ1 / v1 + クエリv3 | iOS 3.2.1（ビルド202608300209）/ iOS 3.0.3 | V1に加えて19ツールのローカルMCP／クエリ | 実機認定待ち |
| Android | セレクタ2 / v2 | Android 1.8.1 (`versionCode 30`) / Android 1.5.4 (`versionCode 25`) | 状態、ネイティブ生データ、ファイル、再開、キャンセル | 実機認定待ち |
| Android型付きMCPクエリ | 該当なし | 未実装 | クエリツールにはiPhone v3が必要 | 非対応 |

## 直接接続モードの対応機能

- iPhone（プロトコルv1）またはAndroid（プロトコルv2）のソースとの、1回限りのペアリングと信頼済みの再接続
- ローカルの信頼済みデバイスの確認とペアリング解除
- スマートフォンのリアルタイムな準備状況
- 厳密な生データエクスポート。iPhoneではschema-v8 `healthmd.health_data`、AndroidではプロバイダネイティブなHealth Connectスナップショット
- 選択範囲の正規抽出（iPhoneのみ）
- 両方のスマートフォンプラットフォームでの本番エクスポーターによるファイル生成
- ローカル永続ジョブの状態確認と再開
- 明示的なキャンセル
- 同じ実行ファイルによる`healthmd mcp serve` stdioサーバー。iPhone直接接続の型付きクエリ、指標カタログ、エビデンス、MCP Apps UI、PNGフォールバックに対応（iPhoneのみ）

`healthmd`コマンドの直接接続バックエンドは、Macアプリの暗号化コンテキスト用HTTPルートをエミュレートしません。このため、Mac向けの`doctor`、query、evidence、refreshサブコマンドは、バックエンドを切り替えずに`backend_unsupported`を返します。iPhone直接接続で新規の型付き分析を行うには`healthmd mcp serve`を使用します。Codexの設定とペアリングを自動で行うには、`healthmd setup codex`を実行します。`healthmd mcp schema [TOOL]`は、ネストしたMCP入力スキーマと例をローカルに正確に出力します。睡眠には`healthmd_sleep_sessions`を直接使用し、正規の`extract`出力を型付きクエリAPIとして扱わないでください。

## 要件

- 直接接続に対応する`healthmd`バイナリと、対応するHealth.mdのビルド（iPhoneはプロトコルv1、Androidはプロトコルv2）。AndroidのペアリングにはポータブルRustクライアントが必要です。同梱のmacOSヘルパーがペアリングできるのはiPhoneだけです。
- ペアリング時と新しいコマンドの開始時に、スマートフォンでHealth.mdが前面表示されていること
- iPhoneでは**設定 > Mac同期 > Direct CLI Access**、Androidでは**設定 → Direct CLI**が有効であること
- プラットフォームのヘルス権限（HealthKitまたはHealth Connect）、保護されたデータ、ローカルネットワーク権限、エクスポート利用枠を使用できること
- Manual IPでは、到達可能なコンピューターのアドレスとTCPポート`17647`。Tailscaleアドレスも使用可能
- 生成ファイルモードでは、既存の絶対パスの保存先

CLIがリスナーになります。スマートフォンは、Direct CLI Accessに入力したコンピューターのアドレスへ接続します。

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

ポータブルRustクライアントは、6桁のiPhoneコード、別個の20桁のAndroidコード、候補となるコンピューターのアドレス、リスナーポートを標準エラー出力へ出力します。同梱のmacOSヘルパーが表示するのは6桁のiPhoneコードだけです。標準出力は、最終的なJSON結果のために空けておきます。

iPhoneでは、次の手順を行います。

1. **Health.md >設定 > Mac同期 > Direct CLI Access**を開きます。
2. Direct CLI Accessを有効にします。
3. **Manual IP**を選択します。
4. コンピューターのLANアドレスまたはTailscaleアドレスを入力します。
5. ポート`17647`を入力します。CLIで別のグローバル`--port`を使用している場合は、そのポートを入力します。
6. ペアリングコードを入力し、「ペアリング」をタップします。
7. 両方で成功が報告されるまで、アプリを開いたままにします。

iPhoneのペアリングコードの有効期限は10分です。ネットワーク経由で送信されることも、保存されることもありません。

## Androidスマートフォンをペアリングする

Androidのペアリングでは、ポータブルRustクライアントと、`healthmd direct pair`が表示する別個の20桁（約66ビット）の1回限りコードを使用します。AndroidがiPhoneプロトコルへダウングレードされることはありません。

1. Androidスマートフォンで**Health.md >設定 → Direct CLI**を開きます。
2. コンピューターのLANアドレスまたはTailscaleアドレスと、ポート`17647`を入力します。
3. 20桁のコードを入力し、ペアリングを確認します。
4. アプリを開いたままにします。Androidでは、アクティブな直接接続セッションの間、ユーザーが開始した可視のデータ同期フォアグラウンドサービスが実行されます。

1回限りコードが消費された後の再接続の信頼は、Keystoreによって保護されます。

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

これらのコマンドはローカルの信頼情報を読み取り、または変更するだけで、スマートフォンには接続しません。iPhone側では、**ペアリング済みCLIを削除**を使用して相手側を削除します。Androidでは、**設定 → Direct CLI**からペアリングを削除します。

複数のスマートフォンを信頼している場合は、対象のインストールを明示的に選択します。

```bash
healthmd --backend direct --device DEVICE_UUID status
```

`healthmd direct reset-trust --confirm`は、ローカルの信頼情報が破損しているか、交換前のインストールに属している場合にだけ使用してください。ローカルの直接ペアリングがすべて削除されます。最初からやり直す前に、スマートフォン側でもそれらのペアリングを削除してください。

## リアルタイムの準備状況を確認する

```bash
healthmd --backend direct --transport manual-ip status
```

直接接続のstatusレスポンスは、ヘルスデータの値を含めず、接続状態と安全性の状態を報告します。ポータブルクライアントは、ソースを`source`として報告し、`platform`は`ios`または`android`になります。同梱ヘルパーは、以下の`iphone`フィールドを公開します。作業を始める前に、次のフィールドを確認してください（iPhoneソースの例）。

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

Androidのソースでは、iPhoneのトリガーフラグの代わりに、`platform: "android"`と、`app_active`、`protected_data_available`、`export_in_progress`、利用可能な生データ製品が報告されます。

## 厳密な生データエクスポート（iPhone）

範囲セレクターを1つ選択します。

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

検証済みJSONを標準出力へストリームするには、`--output`を省略します。機密性の高いレスポンスや大きなレスポンスでは、出力ファイルを使用する方が安全です。

iPhoneの厳密な生データエクスポートは`healthmd.raw_result` v1を返します。この結果には、通常のschema-v8 `healthmd.health_data`日次データと、その正規ソースアーカイブが含まれます。iPhoneに保存済みの設定を変更せず、一時的にロスレス詳細を要求します。CLIは結果を公開する前に、正確な日付、プロファイル、スキーマ、アーカイブ、マニフェスト、ダイジェストチェーン、最終本文ダイジェスト、完了状態を検証します。

完全だが空の日は成功です。要求したデータが欠損、一部完了、失敗、キャンセル、未対応、スキップの場合は、`partial_success`とゼロ以外の終了コードになります。`--allow-partial`を明示した場合に限り、この終了動作を許容できます。

## プロバイダネイティブな生データエクスポート（Android）

ポータブルRustクライアントは既定で直接接続を使用するため、Androidの生データコマンドでは`--backend`フラグを省略します。

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider`は1つの明示的なプロバイダを指定し、既定値は`health_connect`です。`--raw-format`の既定値はNDJSONで、大きなスナップショットに推奨される形式です。メモリ内でのJSON検証は64 MiBが上限です。指標の選択では`--metric`と`--all-metrics`に対応しますが、正規抽出や生成ファイルのセレクターには対応しません。それらはiPhoneの機能として残ります。

Androidの生スナップショットは、Health Connectのプロバイダネイティブなコントラクトを維持します。HealthKit形式の`healthmd.health_data`日次データへ変換されることはなく、関連はするが異なる統計は独自の識別情報を持ち続けます。

## 正規抽出

直接抽出は、同じ永続的な生データ転送を使用しますが、転送ラッパーではなく、選択したソースに近い形式のデータを返します。これはiPhoneの機能です。

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

指標、カテゴリ、ソース、詳細レベルの選択は、HealthKitを読み取る前にiPhoneへ到達します。オブジェクトセレクター、JSON Pointer、JSONL、レシートについては、[正規抽出](/ja/docs/cli-extract/)を参照してください。

スマートフォンアプリが前面にある間は、一時的な切断後に信頼済み直接接続セッションが回数と待ち時間を制限して自動再接続する場合があります。バックグラウンドのアプリを起こしたりアクセスを保証したりはしません。前面にない場合はHealth.mdを再度開いてから再開してください。

## 本番エクスポーターによる生成ファイル

直接ファイルモードでは、スマートフォンへHealth.mdの本番エクスポーターを実行するよう要求し、生成されたファイルを明示したコンピューターの保存先へ転送します。

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

生成ファイルの保存先は、iPhoneプロトコルv1とAndroidプロトコルv2の両方で、すべてのCLIオペレーティングシステム（macOS、Linux、Windows）に対応します。Androidでは各生成ジョブの上限は4,096ファイルです。

Androidプロトコルv2のファイルジョブは、デバイスに保存済みの選択または`--profile PROFILE_ID`から出力設定を取得し、CLIの指標、カテゴリ、詳細セレクターは拒否します。どちらのスマートフォンプラットフォームでも、`--profile`は固定された出力設定を解決し、必須の`--destination`は引き続きコンピュータ上の明示的なフォルダを指定します。
安定IDと安全な失敗については [エクスポートプロファイル](/ja/docs/export-profiles/).

## 前面表示とバックグラウンドでの動作

ペアリングと新しい処理の開始時は、スマートフォンのアプリを前面に表示する必要があります。Direct CLI Accessによってスマートフォンがヘッドレスなエクスポートサーバーになることはなく、必要に応じてアプリを起動することもできません。

iPhoneでは、エクスポートが接続済みの状態でアプリがバックグラウンドへ移動すると、Health.mdは、限られたiOSバックグラウンド実行時間を要求します。その時間内にエクスポートが完了する場合があります。iOSによって実行時間が終了されると、接続が閉じ、永続ジョブが一時停止します。Health.mdを再度開き、同じジョブを再開してください。

Androidでは、アクティブな直接接続セッションの間、ユーザーが開始した可視のデータ同期フォアグラウンドサービスが実行されます。ペアリングと新しい処理の開始時は、アプリを前面に表示してください。

iPhoneでは、直接接続の処理中に表示される全体アクティビティバナーが、ヘルスデータの値を表示せずに、取得と転送のフェーズ、完了した日数、バイト単位の進捗、一時停止または完了の状態を示します。

スマートフォンアプリが前面にある間は、信頼済みの直接接続セッションが一時的な切断後に自動再接続することがあります。再試行間隔は徐々に増え、短い上限で止まります。バックグラウンドのアプリを起動したり、アクセスを保証したりするものではありません。アプリが前面にない場合は、再開前にHealth.mdを開き直してください。

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

- ペアリングでは、一時的な鍵共有と、プラットフォームのペアリングコード（6桁のiPhoneフロー、または別個の高エントロピーな20桁（約66ビット）のAndroid 1回限りコード）に紐づくトランスクリプト証明を使用します。
- 再接続では、保存済みのランダムなシークレットと両方のインストールIDを証明します。
- 接続ごとに新しい鍵とnonceを導出します。
- メッセージとバイナリフレームでは、単調増加するシーケンス検証を備えたChaCha20-Poly1305を使用します。
- パーティションでは、SHA-256マニフェストと連鎖ダイジェストの進行地点を使用します。
- iPhoneの信頼情報はKeychainに保存され、Androidの再接続の信頼はKeystoreによって保護されます。
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
  <a href="/ja/docs/android/"><span>Android</span>Android版Health.md：Health Connectソース、フォルダー保存先、端末上の自動化。</a>
  <a href="/ja/docs/cli-extract/"><span>データ</span>正規抽出：ソースに近い形式のHealth.mdデータを選択して出力します（iPhone）。</a>
  <a href="/ja/docs/cli-jobs/"><span>信頼性</span>永続ジョブと自動化：再開、キャンセル、部分的な結果、スクリプト処理。</a>
  <a href="/ja/docs/reference/connected-mac-iphone-protocol/"><span>プロトコル</span>接続中のMacとiPhoneのリファレンス：機能、上限付き転送、結果の状態。</a>
</div>
