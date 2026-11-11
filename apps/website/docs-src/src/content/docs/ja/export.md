---
title: "輸出"
description: "Apple Healthのデータを今すぐ、またはスケジュールでエクスポートします。アーカイブで準備状況を確認し、「今すぐエクスポート」で期間を選び、オートメーションごとに保存先を設定します。"
---

<p>iPhoneのHealth.mdには、<strong>アーカイブ</strong>、<strong>オートメーション</strong>、<strong>設定</strong>の3つのタブと、丸い<strong>今すぐエクスポート</strong>ボタンがあります。iPadではタブがサイドバーに表示されます。</p>

## アーカイブで準備状況を確認する
<p><strong>アーカイブ</strong>のカレンダーには、各オートメーションがカバーした健康データの日付が表示されます。エクスポートを妨げる問題があると、上部の<strong>要確認</strong>カードにその内容が表示されます。</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.mdが示すのはアプリのセットアップ状態であり、すべてのカテゴリへの読み取りアクセスが確認されたわけではありません。HealthKitは拒否された読み取り許可を明かしません。Apple Healthでカテゴリを確認してください。結果が空の場合は、アクセスが許可されていないか、データがない可能性があります。<a href="/ja/docs/troubleshooting/">データが見つからない場合</a>。</p></div>
<div class="option"><strong>フォルダ</strong><p><strong>設定 → フォルダ</strong>でフォルダを選択、または選び直します。フォルダの移動後にiOSがアクセスを失った場合は、Health.mdが選び直すよう求めます。データは削除されません。</p></div>
</div>

## オートメーションの保存先を選ぶ
<p>各オートメーションには独自の保存先があります。<strong>オートメーション</strong>を開いてオートメーションを選び、<strong>出力</strong>を開きます。</p>

<div class="options">
<div class="option"><strong>ローカルフォルダ</strong><p>このデバイスで選んだフォルダまたはObsidianの保管庫に直接書き込みます。</p></div>
<div class="option"><strong>接続中のMac</strong><p>取得した日次データと設定の正確なスナップショットを、近くのMacアプリに送ります。iPhoneがHealthKitを読み取り、Macが選んだ形式を生成してファイルを書き込みます。</p></div>
<div class="option"><strong>APIエンドポイント</strong><p>JSONエンベロープを、iPhoneから自分で設定したHTTP(S)エンドポイントへ直接POSTします。<a href="/ja/docs/api-endpoint/">APIエンドポイントを参照</a>。</p></div>
<div class="option"><strong>Agent Dataゲートウェイ</strong><p>エクスポートした各ファイルを、変更せずにゲートウェイの取り込みエンドポイントへアップロードします。</p></div>
</div>

## 「今すぐエクスポート」で期間を選ぶ
<p><strong>今すぐエクスポート</strong>をタップし、複数ある場合はオートメーションを選んでから、期間を選びます。</p>

<div class="options">
<div class="option"><strong>昨日</strong><p>その日が終わっているため、毎日のエクスポートに最も安全な選択です。</p></div>
<div class="option"><strong>7日 / 30日</strong><p>昨日までの直近1週間または1か月です。30日以上の場合は、事前に確認を求めます。</p></div>
<div class="option"><strong>カスタム</strong><p>特定の期間の開始日と終了日を選びます。</p></div>
</div>
<p><strong>書き込み内容</strong>には、保存先と、エクスポートの対象となるおおよそのファイル数と日数が表示されます。<strong>期間の概要のみ</strong>は、日次ファイルの代わりに概要ファイルを1つだけ書き込みます。「今日」と「全期間」は<strong>オートメーション → すべての書き出し設定</strong>で引き続き利用できます。</p>

## プレビューまたはエクスポート
<div class="options">
<div class="option"><strong>プレビュー</strong><p>何かを書き込む前に、生成されるファイルと内容を表示します。</p></div>
<div class="option"><strong>エクスポート</strong><p>エクスポートを実行し、タブバーの上にキャンセルボタン付きで進捗を表示し、結果を履歴とアーカイブのカレンダーに記録します。</p></div>
</div>

## データの詳細レベルを選択します

<div class="options">
 <div class="option"> <strong>概要</strong> <p>読み取り、メモ、ダッシュボード用のコンパクトな日次合計とロールアップ。 </p> </div>
 <div class="option"> <strong>詳細な時系列</strong> <p>選択されたタイムスタンプ付きサンプルと間隔。このレベルは、選択したメトリクスが適切な詳細を明らかにする場合、Apple と Android の両方で利用できます。 </p> </div>
 <div class="option"> <strong>ロスレス健康記録</strong> <p>正規のHealthKitソースレコード アーカイブ。このレベルは Apple のみです。 Android はHealth ConnectレコードをHealthKitアーカイブに変換しません。 </p> </div>
 </div>

## 「エクスポート」の実際の内容
 <ol>
 <li>範囲内の毎日について、選択した概要予測を取得します。詳細時系列に互換性のあるサンプルを追加します。また、ロスレス健康レコードの場合は、正規のソース レコードとクエリ診断を追加します。 </li>
 <li>選択した形式 ( Markdown 、Bases、JSON、または CSV) とテンプレートを適用します。 </li>
 <li> 1 日あたり 1 つのファイルを<code>{vault}/{subfolder}/</code>に書き込むか、接続された Mac ワークフローを通じてファイルを転送するか、バージョン管理された JSON エンベロープを API エンドポイントに POST します。 </li>
 <li>個別追跡<em>がオンの場合、選択されたエントリごとの</em>ファイルMarkdownファイルベースのターゲットの正規アーカイブから派生します。 </li>
 <em> <li>毎日のメモの挿入</em>がオンの場合、選択した概要フィールドを毎日のメモにマージします。 </li>
 </ol>

<p> JSON と CSV は正規レコードを保存できます。 Markdownと Bases は読み取り可能な状態を維持し、アーカイブを埋め込むのではなく、コンパクトなキャプチャ診断を公開します。正確なスキーマと省略ルールについては、 <a href="/ja/docs/reference/">完全なエクスポート リファレンス</a>を参照してください。 </p>

## 停止、キャンセル、再試行

停止またはキャンセルすると、現在の試行のみが終了します。すでに完了したファイルと日付は完了したままですが、未解決の日付は引き続き再試行できます。スケジュールされた試行をキャンセルしても、その定期的なスケジュールは無効になりません。

## プロフィールと信頼できる経歴

保存したプロファイルは、実行時の設定と保存先を固定します。プロファイルを認識するスケジュール実行やオートメーションの履歴行には実行時のプロファイルが残り、履歴には実際に使われた保存先を示すプライバシーに配慮したラベルが残ります。手動エクスポートの行ではプロファイル名が省略されることがあります。後から名前や保存先を変えても、既存の履歴は書き換わりません。参照先のプロファイルが存在しない場合、操作は他の設定を代用せずに失敗します。[エクスポートプロファイル](/ja/docs/export-profiles/)を参照してください。

<div class="callout">
 <strong>ロック解除動作。 </strong>
 <p style="margin-top:6px;">サブスクリプション対応のiPhone / iPadおよびGoogle Play電話機リリースには、エクスポートとスケジュールのためのアクティブな試用版、サブスクリプション、ライフタイム、または保存された永続的なアクセスが必要です。現地の自由輸出枠は残っていない。 Mac コンパニオンおよびF-Droid含まれるアクセス ビルドでは、文書化された例外が保持されます。 <a href="/ja/docs/paywall/"> Apple の購入の詳細については、ペイウォール ページ</a>を参照してください。 </p>
 </div>

## ＃＃ 関連している

<div class="related">
 <a href="/ja/docs/export-profiles/"> <span>反復可能なセットアップ</span>プロファイルをエクスポートし、独立した設定、宛先、スケジュール、安定した自動化 ID を保存します。 </a>
 <a href="/ja/docs/scheduling/"> <span>毎日の使用</span>スケジュール設定。これを自動化すると、[エクスポート] を再度タップする必要がなくなります。 </a>
 <a href="/ja/docs/api-endpoint/"> <span> </span> API エンドポイントを統合し、選択した JSON を独自のサービスに直接送信します。 </a>
 <a href="/ja/docs/format/"> <span>カスタマイズ</span>形式のカスタマイズでは、各ファイルの外観を変更します。 </a>
 <a href="/ja/docs/shortcuts/"> <span> </span> Shortcuts強化し、 Siri 、オートメーション、または他のアプリからのエクスポートをトリガーします。 </a>
 <a href="/ja/docs/reference/"> <span>リファレンス</span>エクスポート リファレンス、スキーマ、正規レコード、診断、および生成されたサンプル。 </a>
 </div>
