---
title: "完整公开且已授权的数据导出"
description: "通过 CLI 导出 iPhone 或 Android 上公开 API 提供、当前构建支持且用户授权的全部类型。"
---

<div class="availability preview"><strong>开发预览 · alpha.7 不包含</strong><p>在后续 <code>healthmd-cli/v&lt;version&gt;</code> 明确发布前，请勿依赖它进行生产自动化。</p></div>

`--full-corpus` 请求公开 API 暴露、已安装构建支持且用户允许读取的每种类型。它不能读取 Apple、Google 或提供商的私有数据库。

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Apple 保留 v8 文档和规范 HealthKit 记录；Android 保留 Health Connect 原生快照。请检查 `exported`、`empty`、`permission_not_granted`、`unsupported`、`feature_unavailable`、`skipped`、`partial` 和 `read_error`。省略不等于为空。

任务可在七天内恢复：

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

超时不等于取消。数据可能包含精确时间、路线、临床文本、药物或附件，应保存到私密文件。当前两个 MCP 数据集工具只属于完整本地 stdio 配置。

<div class="related"><a href="/zh-hans/docs/cli-jobs/"><span>恢复</span>避免重复工作。</a><a href="/zh-hans/docs/guides/raw-snapshots/"><span>Android</span>原生快照。</a></div>
