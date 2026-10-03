---
title: "전체 공개·승인 데이터 내보내기"
description: "iPhone 또는 Android에서 공개 API가 제공하고 지원되며 승인된 모든 유형을 CLI로 내보냅니다."
---

<div class="availability preview"><strong>개발 미리보기 · alpha.7에 미포함</strong><p>이후 <code>healthmd-cli/v&lt;version&gt;</code> 릴리스가 명시적으로 게시하기 전에는 자동화에 사용하지 마세요.</p></div>

`--full-corpus`는 공개 API가 노출하고 설치된 빌드가 지원하며 사용자가 읽기를 허용한 모든 유형을 요청합니다. Apple, Google 또는 제공자의 비공개 데이터베이스는 읽지 않습니다.

```bash
healthmd export --all --raw --full-corpus --output apple-health-corpus.json
healthmd export --all --raw --full-corpus --provider health_connect \
  --raw-format ndjson --output health-connect-corpus.ndjson
```

Apple은 v8 문서와 정규 HealthKit 레코드를, Android는 Health Connect 네이티브 스냅샷을 유지합니다. `exported`, `empty`, `permission_not_granted`, `unsupported`, `feature_unavailable`, `skipped`, `partial`, `read_error`를 확인하세요. 누락은 비어 있음의 증거가 아닙니다.

작업은 7일간 재개할 수 있습니다.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

시간 초과는 취소가 아닙니다. 정확한 시간, 경로, 임상 텍스트, 약물, 첨부를 포함할 수 있으므로 비공개 파일에 보관하세요. 현재 MCP 도구 2개는 전체 로컬 stdio 프로필에만 있습니다.

<div class="related"><a href="/ko/docs/cli-jobs/"><span>복구</span>중복 없이 재개.</a><a href="/ko/docs/guides/raw-snapshots/"><span>Android</span>네이티브 스냅샷.</a></div>
