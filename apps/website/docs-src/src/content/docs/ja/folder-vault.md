---
title: "フォルダとVault"
description: "Markdownファイルの保存場所と、エクスポート先となるサブフォルダ名を指定します。ここでいうVaultはiOS上のフォルダで、Obsidian、ファイルApp、iCloud Drive、サードパーティのファイルプロバイダを利用できます。"
---

## ここでの「Vault」の意味
<p>実際にObsidianを使用しているかどうかにかかわらず、アプリでは選択したフォルダの総称として<em>Vault</em>を使用します。Obsidianを使用する場合は、Obsidian Vaultのルートを指定してください。それ以外の場合は、iCloud Driveの<code>Documents/Health</code>や「このiPhone内」のフォルダなど、任意のフォルダを選択できます。</p>

## ピッカーの仕組み
<p>Vaultの行をタップすると、iOS標準の書類ピッカー（<code>UIDocumentPickerViewController</code>）が開きます。フォルダを選択すると、iOSから<em>セキュリティスコープURL</em>が返されます。これは、起動のたびに再度確認を求めることなく、アプリが継続してフォルダへアクセスするための永続的な参照です。アプリはこれをブックマークとして<code>UserDefaults</code>に保存します。</p>

## サブフォルダ名
<p>Vaultを選択すると、エクスポート先となるサブフォルダ名の入力を求められます。デフォルトは<code>Health</code>です。指定した名前は、エクスポートするすべてのファイルのパスの先頭に追加されます。</p>

<div class="doc-diagram folder-tree" aria-label="Health.mdのエクスポートフォルダツリーの例">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← Health.mdで指定した名前</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>サブフォルダは、後から<em>設定 → Obsidian Vault</em>で変更できます。既存のファイルは移動されません。</p>

## アプリ間の動作
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Obsidian Vaultのルートを選択します。サブフォルダを<code>Health</code>などに設定すると、Vaultツリー内にエクスポート用フォルダとして表示されます。</p></div>
<div class="option"><strong>iCloud Drive</strong><p>iCloud Drive内のフォルダを選択します。ファイルはすべてのAppleデバイスへ自動的に同期されます。</p></div>
<div class="option"><strong>このiPhone内</strong><p>ファイルApp → このiPhone内で作成したフォルダを選択します。ローカル専用で、同期は行われません。</p></div>
<div class="option"><strong>サードパーティのプロバイダ</strong><p>Dropbox、Google Drive、Working Copyなど、ファイルAppのプロバイダとして利用できるサービスはすべて同じように機能します。</p></div>
</div>

<div class="callout">
<strong>iOS特有の動作</strong>
<p style="margin-top:6px;">iOSがセキュリティスコープブックマークを無効にすると、エクスポートが失敗するようになります。これはまれで、通常は対象フォルダを削除または移動した場合にのみ発生します。修正するには、<em>設定</em>からVaultを再選択してください。</p>
</div>

## 関連項目

<div class="related">
  <a href="/ja/docs/onboarding/"><span>前へ</span>オンボーディング — 最初にVaultを選択する場所です。</a>
  <a href="/ja/docs/export/"><span>次へ</span>新しいVaultへエクスポートします。</a>
  <a href="/ja/docs/format/"><span>カスタマイズ</span>形式のカスタマイズ — サブフォルダ内のファイルのエクスポート方法を設定します。</a>
</div>
