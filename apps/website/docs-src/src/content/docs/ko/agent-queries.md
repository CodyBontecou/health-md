---
title: "타입 지정 쿼리 활용법"
description: "명시적 페이징 및 누락 상태와 함께 Health.md 측정 항목, 수면, 훈련, 운동, 데이터 범위, 기간 비교 및 증거 쿼리를 새 데이터 또는 캐시로 실행합니다."
---

고수준 CLI 명령은 일반적인 건강 데이터 질문을 고정된 타입 지정 쿼리 작업으로 변환합니다. 기본적으로 요청한 iPhone 데이터를 가져오고 암호화된 Mac 컨텍스트를 쿼리한 뒤 증거 및 데이터 범위가 포함된 버전 지정 JSON을 반환합니다.

완전한 `healthmd.health_data` 날짜 또는 소스 레코드가 필요하면 대신 [정규 추출](/ko/docs/cli-extract/)을 사용하세요.

## 준비 상태 확인 및 측정 항목 찾기

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

측정 항목 카탈로그는 정규 ID, 표시 이름, 카테고리, 단위 및 사용 가능 여부에 필요한 조건을 반환합니다. 특정 측정 항목에 HealthKit 권한이 부여되었다고 주장하지는 않습니다.

추측하지 말고 카탈로그에서 ID를 복사하세요.

## 측정 항목 계열 쿼리

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

카테고리는 현재 카탈로그를 통해 확장됩니다.

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

여러 측정 항목 및 카테고리 플래그가 결합됩니다. 새 데이터 가져오기는 저장된 내보내기 설정을 변경하지 않고 확장된 선택을 iPhone에 전달합니다.

응답은 `healthmd.cli_metric_query` v1 API 엔벨로프를 사용합니다. 중첩된 타입 지정 쿼리 응답과 함께 가져오기 진단을 유지합니다.

## 새 데이터, 캐시 및 데이터 범위 재사용

기본값은 새 데이터입니다.

```bash
healthmd query --metric resting_heart_rate --last 30
```

연결된 iPhone에서 정확한 범위를 요청하고, 업데이트된 암호화 소유자 날짜를 커밋한 뒤 이를 쿼리합니다.

캐시 모드는 iPhone에 연결하지 않습니다.

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

저장된 캡처 시간과 데이터 범위를 허용할 수 있는 오프라인 분석에만 캐시 모드를 사용하세요.

`--reuse-covered`는 먼저 암호화된 요약 데이터 범위를 확인합니다.

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Health.md는 요청한 모든 측정 항목과 날짜에 완전하고 호환되는 요약 데이터 범위가 있을 때만 가져오기를 건너뜁니다. 무손실 요청과 새로 투영한 수면 세션 작업은 이 단축 경로를 사용하지 않습니다.

## 완료 필드 이해

새 쿼리 응답은 세 개념을 구분합니다.

| 필드 | 답하는 질문 |
|---|---|
| `requested_scope_status` | 이 가져오기에서 요청한 모든 측정 항목, 소스, 제공자 및 소유자 날짜가 완료되었는가? |
| `corpus_status` | 캡처된 데이터 모음의 다른 분기에서 경고, 건너뜀 또는 실패를 보고했는가? |
| `unrelated_skips` | 요청 범위 밖에서 건너뛰거나 지원되지 않은 분기는 무엇인가? |

완전한 요청 범위와 관련 없는 데이터 모음 건너뜀이 함께 존재할 수 있습니다. Health.md는 요청 결과를 잘못 낮추거나 데이터 모음 진단을 숨기지 않고 두 사실을 모두 유지합니다.

새 작업의 완료 여부에는 해당 새로 고침 시작 후 대체된 블롭만 반영됩니다. 오래된 캐시 값은 실패한 요청을 충족할 수 없습니다.

## 결과 페이지 순회

`--all-pages`가 없으면 명령은 제한된 한 페이지를 반환합니다. `next_cursor`를 확인하세요.

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

null이 아닌 커서는 결과가 더 있다는 뜻입니다. 순회가 완료될 때까지 최상위 고수준 상태는 `partial_success`로 유지됩니다.

자동 순회는 반복 확인과 함께 불투명 커서를 따라갑니다.

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

응답은 첫 번째 `healthmd.query_response`를 `query` 아래에, 이후 버전 지정 응답을 `pages` 아래에 유지하며, 페이지, 항목, 사실, 증거 개수 및 최종 순회 상태가 포함된 `healthmd.cli_query_receipt` v1을 제공합니다.

자동 순회에는 전체 페이지 및 바이트 한도가 있습니다. 한도에 도달하면 날짜 또는 측정 항목 선택을 좁히거나 [저수준 API](/ko/docs/agent-api/)를 사용하여 수동으로 페이지를 탐색하세요.

## 진행 상황 및 표 출력

건강 값이 포함되지 않은 단계 및 페이지 진행 상황을 JSONL로 stderr에 기록합니다.

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSON이 완전한 출력입니다. 표 모드는 터미널 사용자를 위해 일부 정보를 생략하는 선택적 TSV 보기입니다.

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

표 바닥글에는 데이터 범위, 소스, 제한 사항, 완료 및 관련 없는 건너뜀 메모가 유지됩니다. 스크립트에 정확한 타입 지정 값 또는 증거가 필요하면 표 출력을 사용하지 마세요.

## 수면 세션

Apple Health 수면 단계는 자정을 넘고 소스별로 겹칠 수 있습니다. 수면 명령은 각 소유자 날짜를 하나의 숫자 합계로 취급하지 않고 안정적인 세션을 만듭니다.

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

정확한 날짜 및 전체 기록 선택도 사용할 수 있습니다.

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

각 세션은 다음을 보고할 수 있습니다.

- 안정적인 세션 식별 정보
- 소유자 날짜 및 현지 시간대
- 정확한 현지 및 UTC 시작·종료 타임스탬프
- 야간 수면 또는 낮잠 분류
- 선택한 단계 합계
- 관측 및 추적되지 않은 기간
- 완전성 및 제외 항목
- 세션 기준 고정 구간
- 인접 날짜 생리 데이터의 범위
- 소스 증거

세션 가져오기는 무손실 정규 수면 단계 구간과 완전한 정규 단계 측정 항목 집합을 요청합니다. Health.md는 경계 처리를 위해 기술적으로 인접한 소유자 날짜를 최대 하루만 읽은 뒤 관련 없는 날짜를 결과에서 제외합니다.

겹치는 단계 소스는 총수면 시간 계산에서 중복 제거됩니다. 집계 전용 캐시 컨텍스트는 `aggregated`로 표시되며 구간 관측 데이터 범위를 주장하지 않습니다. 고정 `first:4h` 구간은 일별 집계를 4시간에 나누어 배분하지 않습니다.

## 운동 및 수면 정렬

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

선택한 각 운동에 대해 Health.md는 36시간 이내의 가장 가까운 적격 직전 및 직후 수면 세션을 찾습니다. 다음을 보고합니다.

- 안정적인 운동 및 세션 ID
- 정확한 시간 간격
- 요청한 수면 구간
- 생리 샘플 수
- 단계 및 세션 데이터 범위
- 증거 및 제외 항목

이 작업은 결정론적 시간 정렬입니다. 운동이 수면 결과를 유발했거나 수면이 운동 성과를 유발했다고 주장하지 않습니다. 기술적으로 인접한 소유자 날짜를 최대 이틀만 읽으며 관련 없는 데이터는 반환하지 않습니다.

## 운동 목록

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

운동 목록은 안정적인 식별 정보, 정확한 타임스탬프, 타입이 지정된 세부 정보, 증거 및 누락 상태를 보존합니다. 결과는 시작 타임스탬프와 안정적인 운동 식별 정보 순으로 정렬됩니다. 고정된 전체 운동 제한은 없으며 페이지 제어가 각 응답을 제한합니다.

## 데이터 범위

질문이 “값이 무엇인가?”가 아니라 “어떤 데이터가 있는가?”일 때 데이터 범위를 사용하세요.

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

데이터 범위 결과는 요청 범위와 사용 가능한 범위, 고려한 날짜, 값이 있는 날짜 및 상태가 포함된 누락 구간을 반환합니다. 상태와 이유가 같은 인접 구간은 의미를 잃지 않고 압축될 수 있습니다.

일치하는 관측값이 없는 날짜는 `complete_empty`일 수 있습니다. 동기화된 적이 없는 날짜는 다른 상태입니다. 어느 것도 0이 되지 않습니다.

## 정확한 기간 비교

CLI는 측정 항목을 합산, 평균, 최솟값, 최댓값, 개수 또는 최신 값 중 무엇으로 처리할지 추측하지 않습니다. 각 측정 항목 ID 옆에 집계를 지정하세요.

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

지원되는 집계:

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

단위 또는 유형이 일치하지 않으면 암묵적으로 결합하지 않고 실패합니다. 누락된 기간에는 집계 값이 없습니다. 첫 기간 기준값이 0이면 절대 변화는 있지만 백분율 변화는 없으며 제한 사항에 `zero_baseline`이 포함됩니다.

방향은 사실만 나타냅니다. `increased`, `decreased`, `unchanged` 또는 `not_comparable`입니다. 더 좋거나 나쁘다는 뜻은 아닙니다.

## 훈련 증거 패킷

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

필요할 때만 구체적인 운동 세부 정보를 요청하세요.

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

운동 세부 정보를 선택하면 해당 요청에 필요한 무손실 범위를 요청합니다. 패킷에는 사실 값, 데이터 범위, 소스 설명자, 증거 로케이터 및 제한 사항이 포함됩니다.

패킷 ID는 의미적 콘텐츠의 결정론적 SHA-256 다이제스트입니다. 다른 시점에 같은 패킷을 다시 생성해도 생성 메타데이터는 달라질 수 있지만 의미적 ID는 유지됩니다.

계약 v1의 증거 패킷 종류에는 `daily_wellness`, `training` 및 `doctor_visit`가 있습니다. 현재 고수준 편의 명령은 훈련 패킷을 제공합니다. 정확한 요청 본문에는 저수준 API를 사용하세요.

## 날짜 소유권 및 시간대

쿼리 날짜는 압축 컨텍스트 `owner_date` 값입니다. 각 날짜에는 날짜를 구성할 때 사용한 정확한 반개구간 UTC 구간과 캡처 당시의 IANA 달력 시간대도 유지됩니다.

수면 세션은 현지 타임스탬프와 자정을 넘는 날짜를 유지합니다. 기술적 인접 읽기가 있으므로 Mac의 현재 시간대에 따라 데이터를 이동하지 않고 세션이 소유자 날짜 경계를 넘을 수 있습니다.

에이전트에 날짜에 민감한 질문을 할 때는 원하는 소유자 날짜를 포함하고 컴퓨터 시간대를 가정하지 말고 반환된 시간대를 확인하세요.

## 에이전트 답변에서 누락을 숨기지 않기

안전한 요약에는 다음이 유지되어야 합니다.

- 측정 항목 ID 및 정규 단위
- 날짜 범위 및 시간대
- 새 데이터, 캐시 또는 데이터 범위 재사용 모드
- 요청 범위 및 데이터 모음 상태
- 페이지 순회 완료 여부
- 증거 참조 또는 소스 다이제스트
- complete-empty 및 누락 구간
- 경고, 제한 사항 및 관련 없는 건너뜀

실패한 날짜를 평균으로 숨기거나, 부재를 0으로 취급하거나, 시간 정렬을 원인으로 설명하지 마세요.

## 관련 문서

<div class="related">
  <a href="/ko/docs/agents/"><span>아키텍처</span>로컬 에이전트 및 건강 컨텍스트: 설정, 암호화, 요청 범위, 증거 및 보존.</a>
  <a href="/ko/docs/mcp/"><span>MCP</span>로컬 MCP 도우미: 쿼리, 수면, 정렬, 운동, 데이터 범위, 비교 및 증거에 대응하는 타입 지정 도구.</a>
  <a href="/ko/docs/agent-api/"><span>원시 계약</span>루프백 쿼리 API: 정확한 요청, 단일 페이지 응답, 새로 고침 및 작업 라우트.</a>
  <a href="/ko/docs/reference/evidence-packets/"><span>참조</span>압축 쿼리 및 증거 패킷: 타입이 지정된 값, 커서, 작업, 데이터 범위 및 ID.</a>
</div>
