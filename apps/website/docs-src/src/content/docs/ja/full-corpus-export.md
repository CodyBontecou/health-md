---
title: "公開・承認済み全データのエクスポート"
description: "iPhoneまたはAndroidで公開APIから利用でき、対応・承認された全タイプをCLIで書き出します。"
---

<div class="availability preview"><strong>開発プレビュー · alpha.7には未収録</strong><p>後続の<code>healthmd-cli/v&lt;version&gt;</code>リリースが明示するまで本番自動化に使用しないでください。</p></div>

`--full-corpus`は、公開APIが提供し、インストール済みビルドが対応し、利用者が読み取りを許可した各タイプを要求します。Apple、Google、プロバイダの非公開データベースは読みません。

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Appleはv8文書と正規HealthKitレコードを、AndroidはHealth Connectネイティブスナップショットを維持します。`exported`、`empty`、`permission_not_granted`、`unsupported`、`feature_unavailable`、`skipped`、`partial`、`read_error`を確認してください。省略は空である証拠ではありません。

ジョブは7日間再開できます。

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

タイムアウトはキャンセルではありません。正確な時刻、経路、臨床テキスト、薬、添付を含む可能性があるため非公開ファイルへ保存してください。現在のMCP 2ツールは完全なローカルstdioプロファイルだけにあります。

<div class="related"><a href="/ja/docs/cli-jobs/"><span>復旧</span>重複せず再開。</a><a href="/ja/docs/guides/raw-snapshots/"><span>Android</span>ネイティブスナップショット。</a></div>
