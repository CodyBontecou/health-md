---
title: "정규 건강 데이터 추출"
description: "healthmd extract를 사용하여 선택한 Apple Health 측정 항목을 가져오고, 명시적인 수신 확인과 함께 정규 스키마 v8 문서, 소스 레코드, JSON Pointer 프로젝션 또는 JSONL을 출력합니다."
---

`healthmd extract`는 스크립트와 에이전트를 위한 소스 데이터 명령입니다. iPhone에 선택한 측정 항목과 세부 정보만 가져오도록 요청하고, 영속 전송을 검증하며, 전송 엔벨로프를 제거한 뒤 정규 `healthmd.health_data` v8 문서 또는 명확히 표시된 프로젝션을 출력합니다.

정규 추출은 Mac 앱 백엔드와 iOS v1 다이렉트 프로토콜을 기반으로 하는 iPhone 기능입니다. Android 다이렉트 소스는 대신 공급자 고유의 Health Connect 스냅샷을 [raw 내보내기](/ko/docs/cli-direct/)로 반환합니다.

원본 Health.md 데이터가 필요하면 추출을 사용하세요. 세션, 비교, 운동 시점 정렬, 데이터 범위 또는 증거 패킷이 필요하면 [타입 지정 쿼리](/ko/docs/agent-queries/)를 사용하세요.

## 기본 구조

추출에는 다음이 필요합니다.

1. 하나 이상의 측정 항목, 카테고리, 객체 또는 `--all-metrics` 선택자
2. 하나의 날짜 선택자
3. 선택적 세부 정보, 객체, 필드, 형식, 출력, 제한 시간 및 부분 결과 설정

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

현재 정규 추출 소스는 `apple_health`입니다. 제공자 고유 사이드카는 자체 계약에 유지되며 합성 Apple Health 값으로 변환되지 않습니다.

## 좁은 요청으로 시작

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

iPhone 작업이 시작되기 전에 현재 카탈로그를 기준으로 측정 항목과 카테고리 이름을 검증합니다. 여러 선택자를 결합하려면 반복해서 지정하세요.

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## HealthKit 읽기 전에 선택 적용

추출은 저장된 전체 측정 항목 내보내기를 가져온 뒤 잘라내지 않습니다. CLI는 선택자를 변경 불가능한 `CanonicalHealthDataSelection`으로 해석하여 iPhone에 보냅니다. Health.md는 선택한 측정 항목을 뒷받침하는 일반 HealthKit 유형만 확인하고 읽습니다.

이 차이는 개인정보 보호, 성능 및 완전성에 중요합니다.

- 선택하지 않은 측정 항목은 가져오지 않습니다.
- 저장된 iPhone 측정 항목 환경설정은 변경되지 않습니다.
- 요약 요청은 숨겨진 소스 아카이브를 만들지 않습니다.
- 무손실 요청은 선택에 필요한 소스 유형만 가져옵니다.
- 선택은 영속 요청 지문의 일부가 됩니다.

객체 및 JSON Pointer 선택자는 캡처 후 출력 데이터를 좁힙니다. 측정 항목, 카테고리, 소스 및 세부 정보 선택자는 iPhone 가져오기 자체를 좁힙니다.

## 요약 및 무손실 세부 정보

기본값은 요약입니다.

```bash
healthmd extract --category Activity --last 7 --detail summary
```

요약 출력에는 타입이 지정된 일별 요약, 쿼리 진단 및 `raw_capture_status: not_requested`가 포함될 수 있습니다. 이 상태는 실제 동작을 그대로 나타냅니다. 명령이 정규 소스 레코드를 가져오지 않았다는 뜻입니다.

소스 객체, UUID, 정확한 타임스탬프, 출처 또는 아카이브 진단이 중요하면 무손실 세부 정보를 요청하세요.

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

`records` 같은 아카이브 지향 객체는 `--detail`을 생략해도 무손실 세부 정보를 뜻합니다.

## 객체 선택자

`--object`를 사용하여 선택한 각 날짜의 알려진 부분을 유지합니다. 현재 이름은 다음과 같습니다.

| 객체 | 일반적인 내용 |
|---|---|
| `sleep` | 일별 수면 요약 필드 |
| `activity` | 걸음 수, 에너지, 거리, 운동 및 관련 활동 요약 |
| `heart` | 심박수, 안정 시 심박수, HRV 및 관련 요약 |
| `vitals` | 혈압, 혈당, 체온, 산소 및 기타 활력 요약 |
| `body` | 체중, 신체 구성, 키 및 신체 측정값 |
| `nutrition` | 영양소 및 수분 섭취 요약 |
| `mindfulness` | 마음 챙기기 세션 및 정신 건강 요약 |
| `mobility` | 걷기, 보행 및 이동성 필드 |
| `hearing` | 오디오 노출 및 청력 필드 |
| `reproductive-health` | 생식, 임신 및 주기 필드 |
| `cycling` | 사이클링 요약 |
| `vitamins` / `minerals` | 영양소별 요약 |
| `symptoms` | 증상 데이터 |
| `medications` | 사용 가능하고 권한이 부여된 경우 약물 데이터 |
| `workouts` | 정규 운동 요약 객체 |
| `archive` | 정규 HealthKit 아카이브 엔벨로프 |
| `records` | 정규 소스 레코드. 무손실 세부 정보를 뜻함 |
| `external-records` | 공개 일별 데이터에 이미 있는 외부 레코드 |
| `query-results` | 쿼리별 캡처 결과 |
| `warnings` | 무결성 경고 |

예:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## JSON Pointer 프로젝션

RFC 6901 JSON Pointer와 함께 `--field`를 반복하여 정확한 값 또는 상태 항목을 출력합니다.

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Pointer 결과는 프로젝션이며 완전한 일별 문서가 아닙니다. 소스 스키마와 날짜를 참조하지만 하위 트리가 전체 내보내기처럼 보이도록 `schema: healthmd.health_data`를 포함하지는 않습니다.

선택한 경로가 없으면 complete-empty 또는 해당 날짜의 불완전 상태로 보고됩니다. Health.md는 값의 부재를 0으로 변환하지 않습니다.

## JSON 출력

기본 JSON 출력에는 다음 데이터 컬렉션 중 하나가 포함됩니다.

- 완전한 정규 일별 문서용 `health_data`
- 객체 또는 Pointer 결과용 `projections`

또한 다음을 기록하는 `healthmd.extract_receipt`가 포함됩니다.

- 해석된 선택 및 날짜 범위
- 소스 및 세부 정보 수준
- 일별 결과
- 유지된 항목 및 캡처 수
- 누락 날짜
- 부분 또는 실패 진단
- 출력 완료 상태

수신 확인은 프로토콜 메타데이터입니다. 소스 스키마를 대체하지 않습니다.

## JSONL 출력

스트림 처리에는 JSONL을 사용하세요.

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

각 줄은 하나의 데이터 항목입니다. 수신 확인은 건강 데이터 스트림에 섞이지 않습니다.

- `--output`을 사용하면 `OUTPUT.receipt.json`에 기록됩니다.
- `--output`이 없으면 stderr에 기록됩니다.

따라서 파이프라인을 예측 가능하게 유지할 수 있습니다.

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

stderr에는 수신 확인과 건강 값이 없는 진행 상황이 포함되므로 stderr를 JSONL 파서에 파이프하지 마세요.

## 완전, 비어 있음 및 부분 결과

Health.md는 다음 상태를 구분합니다.

| 상태 | 의미 |
|---|---|
| `success` | complete-empty 분기를 포함하여 요청한 모든 분기가 완료됨 |
| `complete_empty` | 요청 범위가 표현되었지만 관측값이 없음 |
| `partial_success` | 요청한 데이터 일부가 유지되었지만 하나 이상의 요청 분기가 불완전함 |
| `failed` | 요청한 분기가 실패함 |
| `unsupported` | 플랫폼 또는 HealthKit이 요청한 분기를 지원하지 않음 |
| `skipped` | Health.md가 의도적으로 해당 분기를 쿼리하지 않음 |
| `cancelled` | iPhone이 취소를 확인함 |
| `missing` | 요청한 날짜 또는 분기가 표현되지 않음 |

부분 추출은 기본적으로 유지된 데이터를 출력하지 않습니다. 소비자가 불완전한 범위를 수락하고 보존하도록 설계된 경우에만 `--allow-partial`을 추가하세요.

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

이 플래그는 출력 및 종료 동작을 변경합니다. 진단을 제거하거나 부분 데이터를 완전한 데이터로 바꾸지 않습니다.

## Mac 앱 및 직접 백엔드

명령은 두 백엔드 모두에서 작동합니다.

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

두 경로 모두 동일한 공개 일별 스키마와 엄격한 검증을 사용합니다. 전송, 페어링, 저장소 및 작업 레코드는 다릅니다. 두 경로 모두 iPhone 소스를 필요로 하며, Android 다이렉트 백엔드는 정규 추출을 구현하지 않습니다.

## 긴 기록

`--all`에는 고정 날짜 제한이 없습니다.

```bash
healthmd extract --metric steps --all --output all-steps.json
```

iPhone은 선택한 레코드 중 가장 이른 날짜를 확인하고, 그 날짜부터 오늘까지의 모든 소스 기준 달력 날짜를 고정한 뒤 제한된 파티션을 전송합니다. CLI는 제한 없는 메모리 응답 하나를 만들지 않고 디스크에서 조립하고 검증합니다.

데이터 모음이 크면 JSONL 또는 더 좁은 선택을 사용하세요. 사용 가능한 디스크 공간과 비정상적으로 데이터가 밀집된 하루는 여전히 실질적인 제한입니다.

## 개인정보 보호 체크리스트

- 건강 데이터가 포함된 결과에는 `--output`을 우선 사용하세요.
- 출력 및 수신 확인 파일을 Apple Health 소스와 동일한 수준으로 보호하세요.
- 건강 명령 주변에서 셸 추적을 사용하지 마세요.
- 페이로드가 CI 로그 및 에이전트 기록에 들어가지 않게 하세요.
- 문제 해결 시 수신 확인, 개수, 상태, 스키마 및 누락 필드만 확인하세요.
- 대상 소비자가 임시 내보내기를 안전하게 커밋한 뒤 삭제하세요.

## 관련 문서

<div class="related">
  <a href="/ko/docs/cli/"><span>CLI</span>Health.md CLI: 설정, 백엔드 선택, 명령 목록 및 출력 규칙.</a>
  <a href="/ko/docs/agent-queries/"><span>파생 보기</span>타입 지정 쿼리 활용법: 측정 항목 계열, 수면, 훈련, 운동, 비교 및 증거.</a>
  <a href="/ko/docs/reference/daily-records/"><span>스키마</span>일별 레코드: 완전한 스키마 v8 일별 문서 계약.</a>
  <a href="/ko/docs/reference/canonical-healthkit-records/"><span>소스 아카이브</span>정규 Apple Health 레코드: 식별, 출처, 관계 및 페이로드.</a>
  <a href="/ko/docs/reference/api-and-cli/"><span>프로토콜</span>API 및 CLI 참조: 추출 요청, 수신 확인, 엄격한 검증 및 종료 동작.</a>
</div>
