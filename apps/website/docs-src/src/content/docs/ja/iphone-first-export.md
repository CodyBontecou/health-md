---
title: "最初のiPhoneエクスポート"
description: "Apple Healthへのアクセスを許可し、ファイルAppで保存先を選択してHealth.mdの出力をプレビューし、小規模な最初のiPhoneエクスポートを実行して、書き込まれたファイルを確認します。"
---

指標、形式、自動化を変更する前に、小規模で検証しやすいエクスポートを作成するための手順です。Health.mdは、iOSで許可されたApple Healthのカテゴリだけを読み取り、選択したフォルダに生成ファイルを書き込みます。

<div class="availability available">
<strong>提供中 · Health.md for iPhone</strong>
<p>最初のエクスポートは無料枠で実行できます。スケジュールなどの有料機能は後から設定できます。</p>
</div>

## 始める前に

以下が必要です。

- Apple Healthのデータが保存されているiPhoneにHealth.mdがインストールされていること。
- 1つ以上のApple Healthカテゴリを読み取る権限。
- iCloud Drive、「このiPhone内」、Obsidian Vaultなど、ファイルAppで書き込み可能な保存先。

最初の実行を最短で済ませるには、既定の指標とMarkdown出力を使用してください。利用可能な全履歴ではなく、**昨日**または別の1日の範囲から始めます。

## 1. iPhoneのセットアップを完了する

初回起動時に**セットアップを開始**をタップし、7つのオンボーディング手順を完了します。必要なApple Healthカテゴリを許可し、サンプル出力を確認して、ファイルAppでフォルダを選択し、**準備完了**まで進みます。ロック解除の手順が表示された場合も、無料枠で続行できます。

オンボーディングをすでに完了している場合は、**エクスポート**タブを開き、Apple Healthとローカルフォルダの準備ができていることを確認します。保存先が見つからない、またはアクセスできない場合は、フォルダのコントロールから選び直してください。

<div class="callout">
<strong>画像内の言語について</strong>
<p style="margin-top:6px;">オンボーディング開始画面と、セットアップが必要な状態の画面には、英語UIの共通参照画像を使用しています。操作位置と手順の確認用です。</p>
</div>

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="オンボーディングのスクリーンショットをフルサイズで開く">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="7ステップ中1ステップ目のHealth.mdオンボーディング開始画面。Start Setupボタンが表示されている英語版の参照画像。" />
  </a>
  <figcaption>Start Setupでは、アクセスを要求する前に、ローカルアーカイブ、スケジュール済みノート、フォルダモデルを説明します。このオンボーディング参照画像は英語です。</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="セットアップが必要な状態のスクリーンショットをフルサイズで開く">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Healthの接続がなく、Choose Folderが使用可能で、Local iPhone Folderと日付範囲ボタンが表示されたHealth.mdのExportタブ。英語版のセットアップ参照画像。" />
  </a>
  <figcaption>準備状況のバッジにより、Healthとフォルダの未設定が明確になります。このシミュレータ画像では、意図的に両方が未完了になっています。セットアップ参照画像は英語です。</figcaption>
</figure>
</div>

## 2. 小規模なエクスポートを選択する

エクスポートタブで以下を行います。

1. 保存先として**iPhone内のローカルフォルダ**を選択します。
2. **昨日**または1日のカスタム範囲を選択します。
3. 最初の実行では既定の指標選択を維持します。
4. **Markdown**を選択したままにします。基本的な処理が成功した後で、CSV、JSON、Obsidian Basesを追加できます。

短い範囲にすると、権限、空のカテゴリ、保存先の問題を把握しやすくなります。また、最初の長時間リクエストを失敗したエクスポートと誤認することも防げます。

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/ja/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="指標選択のスクリーンショットをフルサイズで開く">
    <img src="/docs/assets/docs/ja/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="219件中217件の指標が有効で、標準指標スイッチ、検索フィールド、展開可能な睡眠、アクティビティ、心拍カテゴリが表示された「ヘルス指標」画面。" />
  </a>
  <figcaption>指標の合計数は、インストールされているアプリのバージョンと権限によって異なります。このローカライズされた画面では219件中217件の指標と標準指標が有効ですが、最初のエクスポートでこの件数まで有効にする必要はありません。</figcaption>
</figure>

## 3. 書き込む前にプレビューする

**プレビュー**をタップします。プレビューにはApple Healthへのアクセスが必要ですが、書き込み可能なローカルフォルダは不要です。そのため、読み取り権限の問題とファイルAppの問題を切り分ける際に役立ちます。

プレビューで以下を確認します。

- リクエストした日付。
- 想定した指標名と単位。
- データがない箇所を0で埋めず、欠損または利用不可と明示していること。
- 選択した形式とファイル名構造。

日付、指標、形式を調整する必要がある場合は、エクスポートタブに戻ります。

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/ja/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="エクスポートプレビューのスクリーンショットをフルサイズで開く">
    <img src="/docs/assets/docs/ja/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="1日分のエクスポート見積もり、ロールアップ期間、TestVaultの保存先、生成ファイル名を表示するHealth.mdのエクスポートプレビュー画面。" />
  </a>
  <figcaption>プレビューでは、出力の確認と書き込みを分けて行えます。この再現可能なドキュメント画像ではサンプルのヘルスデータを使用し、保存先としてTestVaultが選択されています。</figcaption>
</figure>

## 4. エクスポートして確認する

**データをエクスポート**をタップします。セットアップが未完了の場合、Health.mdは不完全な書き込みを黙って開始せず、不足しているHealthまたはフォルダの要件を示します。

完了後、以下を行います。

1. アプリ内の結果で、書き込まれたファイル、スキップされたファイル、失敗したファイルを確認します。
2. ファイルAppを開き、選択したフォルダに移動します。
3. 生成されたファイルを1つ開き、日付、単位、frontmatterを確認します。
4. トラブルシューティングのために結果の詳細を保持します。ボタンが待機状態に戻っただけで成功と判断しないでください。

<div class="callout">
<strong>選択した日にデータがありませんか？</strong>
<p style="margin-top:6px;">アクティビティや睡眠のデータがあると分かっている日を試し、Apple Healthの権限と指標選択を確認してください。許可済みの範囲が空であることと、転送または書き込みの失敗は異なります。</p>
</div>

## 次のステップ

<div class="related">
  <a href="/ja/docs/metrics/"><span>データを選ぶ</span>Apple Healthの指標を検索し、カテゴリや追加の権限を調整します。</a>
  <a href="/ja/docs/format/"><span>出力を整える</span>形式、日付、単位、frontmatter、テンプレート、ファイル名を設定します。</a>
  <a href="/ja/docs/scheduling/"><span>自動化</span>手動実行を1回確認した後、繰り返しのエクスポートをスケジュールします。</a>
  <a href="/ja/docs/folder-vault/"><span>保存先の問題を解消</span>ファイルAppのプロバイダ、フォルダアクセス、復旧方法を確認します。</a>
</div>
