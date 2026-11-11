---
title: "最初のiPhoneエクスポート"
description: "Apple Healthへのアクセスを許可し、ファイルAppで保存先を選択してHealth.mdの出力をプレビューし、小規模な最初のiPhoneエクスポートを実行して、書き込まれたファイルを確認します。"
---

指標、形式、自動化を変更する前に、小規模で検証しやすいエクスポートを作成するための手順です。Health.mdは、iOSで許可されたApple Healthのカテゴリだけを読み取り、選択したフォルダに生成ファイルを書き込みます。

<div class="availability available">
<strong>提供中 · iPhone版 Health.md</strong>
<p>エクスポートには、有効なトライアル、サブスクリプション、またはLifetimeアクセスが必要です。スケジュールなどのオートメーションは後から設定できます。</p>
</div>

## 始める前に

始める前に、次のものが揃っていることを確認してください。

- Apple Healthのデータが保存されているiPhoneに[App StoreのHealth.md](https://apps.apple.com/app/health-md/id6757763969)をインストール済み
- 少なくとも1つのApple Healthカテゴリの読み取り許可
- 「ファイル」で書き込み可能なフォルダ（iCloud Drive、このiPhone内、またはObsidianの保管庫）

指標はデフォルトのまま、形式はMarkdownのままにします。1日分の期間として**昨日**を選択します。

## 1. iPhoneのセットアップを完了する

Health.mdのセットアップは5つの手順です。どの手順も先へ進むのを妨げません。Apple Healthへのアクセスとフォルダは、スキップして後で設定できます。

初回起動時に**Apple Healthに接続**をタップします。必要な健康カテゴリを許可し、サンプル出力を確認し、「ファイル」でフォルダを選んで、最後の手順まで進みます。

セットアップ後、アプリは**アーカイブ**を表示します。Apple Healthやフォルダに対応が必要な場合は、上部の**要確認**カードに修正すべき点が表示されます。

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="セットアップのスクリーンショットを実寸で開く">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="5手順中1手順目のHealth.mdセットアップ画面。3つの手順とApple Healthに接続するボタンが表示されている。" />
  </a>
  <figcaption>セットアップでは、アクセスを求める前にHealth.mdが何を読み取り、ファイルをどこに保存するかを説明します。このスクリーンショットのUIは英語のままです。</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="「今すぐエクスポート」のスクリーンショットを実寸で開く">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Health.mdの「今すぐエクスポート」シート。昨日が選択され、期間の概要のみのスイッチ、1日分1ファイルの書き込み内容、エクスポートボタンが表示されている。" />
  </a>
  <figcaption>「今すぐエクスポート」は、開始前に書き込む内容を表示します。この参考スクリーンショットのUIも英語です。</figcaption>
</figure>
</div>

## 2. 小さなエクスポートを選ぶ

タブバーの横にある丸い**今すぐエクスポート**ボタンをタップします。続いて：

1. **昨日**を選択します。
2. **期間の概要のみ**はオフのままにします。
3. **書き込み内容**に保存先フォルダと、1日分でおよそ1ファイルと表示されていることを確認します。

デフォルトのオートメーションは、デフォルトの指標選択と**Markdown**を使います。変更するには、**オートメーション**を開いてオートメーションを選び、**指標**または**形式**を開きます。CSV、JSON、Obsidian Basesは、このエクスポートが成功してから追加してください。期間が短いほど、権限・空データ・フォルダの問題を見つけやすくなります。

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/ja/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="指標選択のスクリーンショットを実寸で開く">
    <img src="/docs/assets/docs/ja/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Health.mdの指標ページ。有効な指標の数、おすすめ・すべて選択・すべて選択解除のボタン、検索欄、件数付きのカテゴリが表示されている。" />
  </a>
  <figcaption>指標の総数はアプリのバージョンと権限によって異なります。このローカライズ版スクリーンショットでは、219件中217件の指標が有効です。</figcaption>
</figure>

## 3. 書き込む前にプレビューする

**今すぐエクスポート**で**プレビュー**をタップします。プレビューにはApple Healthへのアクセスが必要ですが、書き込み可能なフォルダは不要です。

フォルダを試す前に、プレビューでApple Healthの権限の問題を確認しましょう。

プレビューに次の内容が表示されることを確認します。

- 指定した日付
- 想定どおりの指標名と単位
- 誤ったゼロではなく、欠損または利用不可の値
- 選んだ形式とファイル名の構成

指標や形式を変える必要がある場合は、プレビューを閉じてオートメーションの設定を変更します。

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/ja/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="エクスポートプレビューのスクリーンショットを実寸で開く">
    <img src="/docs/assets/docs/ja/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Health.mdのエクスポートプレビュー。睡眠の集計時間帯、1日分のMarkdownの見積もり、ロールアップ期間、保存先フォルダ、生成されるファイル名が表示されている。" />
  </a>
  <figcaption>この例ではサンプルの健康データを使用しています。</figcaption>
</figure>

## 4. エクスポートして確認する

**昨日分を書き出す**をタップします。セットアップが不完全な場合は、Health.mdがApple Healthまたはフォルダの不足している要件を示します。

エクスポートが完了したら：

1. 結果で、書き込まれた・スキップされた・失敗したファイルを確認します。その日が**アーカイブ**のカレンダーに表示されます。
2. 「ファイル」アプリで選んだフォルダを開きます。
3. 生成されたファイルを1つ開き、日付・単位・フロントマターが正しいか確認します。
4. 問題を調べる必要がある場合に備えて、結果の詳細を残しておきます。

カレンダー上のカバー済みの日は概要です。日付をタップすると、その日の各オートメーションの状態を確認できます。

<div class="callout">
<strong>選んだ日にデータがない場合</strong>
<p style="margin-top:6px;">アクティビティや睡眠のデータがある日を選んでください。そのうえでApple Healthの許可と指標の選択を確認します。期間が空であることは書き込みエラーではありません。</p>
</div>

## 次のステップ

<div class="related">
  <a href="/ja/docs/metrics/"><span>データを選ぶ</span>Apple Healthの指標を検索し、カテゴリや追加の権限を調整します。</a>
  <a href="/ja/docs/format/"><span>出力を整える</span>形式、日付、単位、frontmatter、テンプレート、ファイル名を設定します。</a>
  <a href="/ja/docs/scheduling/"><span>自動化</span>手動実行を1回確認した後、繰り返しのエクスポートをスケジュールします。</a>
  <a href="/ja/docs/folder-vault/"><span>保存先の問題を解消</span>ファイルAppのプロバイダ、フォルダアクセス、復旧方法を確認します。</a>
</div>
