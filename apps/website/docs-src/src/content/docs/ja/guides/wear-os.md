---
title: Wear OSコンパニオン
description: Health.md for Wear OSは、ウォッチにアクティビティとリカバリーのタイルに加え、10種類のヘルスコンプリケーションを追加します。電話はHealth Connectの唯一の権威であり続けます。
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.mdは、電話アプリと同じGoogle Play掲載情報の下でWear OSコンパニオンを提供します。電話がHealth Connectの唯一の権威であり続けながら、ウォッチに一目でわかるヘルス画面を追加できます。</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Google Playで入手</a>
    <a class="docs-button-secondary" href="/ja/docs/android/">Androidアプリガイド</a>
  </div>
</div>

## ウォッチに表示されるもの

| 画面 | 内容 |
|---|---|
| デイリーアクティビティタイル | 今日のアクティビティサマリーを文字盤タイルとして表示 |
| リカバリータイル | 今日のリカバリーサマリーを文字盤タイルとして表示 |
| コンプリケーション（10種） | アクティビティ、リカバリー、ステップ、ムーブ、エクササイズ、睡眠、安静時心拍数、平均心拍数、HRV、血中酸素を文字盤コンプリケーションとして表示 |

コンプリケーションはほとんどの文字盤で文字盤エディタから追加でき、タイルはウォッチのタイルカルーセルに表示されます。

## 仕組み

- ウォッチアプリは、電話アプリと同じPlay掲載情報と署名IDで配布されます。
- ヘルスデータは、Wear OSデータレイヤーを通じて電話からウォッチへ、非公開の集約スナップショットとして流れます。ウォッチは**Health ConnectやHealth Servicesを直接センシングせず**、すべてのメトリックで電話が権威であり続けます。
- ウォッチ画面は、電話アプリが最後に送信したスナップショットから更新されます。アカウントもクラウドもなく、ヘルスデータが端末の外に出ることはありません。

## 要件

- Health.mdをインストールしたAndroid電話と、ペアリングしたWear OSウォッチ。
- 表示したいメトリックの、電話上のHealth Connectデータ。
- ウォッチのPlay Storeか、コンパニオン電話のPlay Store掲載情報から、ウォッチにHealth.mdをインストール。

## セットアップ

1. ウォッチのPlay Store（または電話のPlay Storeのウォッチ欄）を開き、Health.mdをインストールします。
2. 電話アプリを一度開き、スナップショットが同期できるようにします。
3. 文字盤を長押し → **カスタマイズ** → Health.mdコンプリケーションを追加するか、タイルカルーセルまでスワイプしてHealth.mdタイルをピン留めします。

## プライバシーと検証

コンパニオンは純粋な非公開集約トランスポートコントラクトを使用するため、生のレコードがウォッチへ送信されることはありません。リリース品質は、Wear OSアーティファクトを出荷する前に、エミュレータスイートと、物理的なペアリング端末でのバッテリーおよびOEM QAエビデンスによってゲートされます。完全な手順書は[Wear OS実装チェックリスト](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md)を参照してください。
