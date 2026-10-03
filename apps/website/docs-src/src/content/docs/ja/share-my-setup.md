---
title: "設定を共有"
description: "健康データ、認証情報、購入、端末の信頼情報を含まない、開発中のv2プロファイル移行を説明します。"
---

<div class="availability preview"><strong>開発プレビュー・リリース未認定</strong><p>v2契約は実機の相互運用性・アクセシビリティ確認が終わるまでpre-canonicalかつplannedです。本番では依存しないでください。</p></div>

Share My Setupは1つ以上のプロファイルをまとめます。指標、形式、命名、整理方法、移行先の意図を移します。健康データ、トークン、実際のフォルダ権限、ペアリング、購入、履歴、ジョブは含みません。

1. 移行元の**設定 → Share My Setup**からv2ファイルを書き出します。
2. 移行先で開き、各プロファイルを確認します。
3. **追加**または**置換**を選びます。
4. フォルダ、認証情報付きAPI、Macを端末上で再接続します。
5. 適用し、小さなエクスポートを試します。

処理は原子的で、一度だけ**取り消す**ことができます。移行先が再接続されるまでプロファイルはブロックされ、スケジュールは無効です。現在の開発ソースは`healthmd.shared_setup` v2だけを書き出し、v1は拒否します。

<div class="related"><a href="/ja/docs/export-profiles/"><span>プロファイル</span>固定設定。</a><a href="/ja/docs/guides/platform-features/"><span>状態</span>QA状況。</a></div>
