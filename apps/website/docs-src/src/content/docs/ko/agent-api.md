---
title: "루프백 쿼리 API"
description: "HTTP 또는 저수준 healthmd agent 명령을 통해 Health.md의 버전 지정 로컬 쿼리, 증거, 새로 고침, 준비 상태, 측정 항목 및 영속 작업 라우트를 호출합니다."
---

Mac용 Health.md는 `/v1/agent/` 아래에 버전 지정 로컬 API를 제공합니다. 암호화 컨텍스트 쿼리, 증거 패킷, 요청 범위에 따른 iPhone 가져오기, 준비 상태 및 영속 가져오기 작업을 제공합니다.

API는 포트 `17645`의 루프백에 바인딩됩니다. 검증된 IPv4 또는 IPv6 루프백 피어만 허용합니다.

<div class="callout">
<strong>이 포트를 노출하지 마세요.</strong>
<p style="margin-top:6px;">bearer 토큰, 호출자 등록, 액세스 프로필 또는 권한 부여 데이터베이스가 없습니다. 루프백 도달 가능성이 전체 권한 부여 경계입니다. Health.md가 열려 있는 동안 모든 로컬 프로세스가 요청을 실행할 수 있습니다.</p>
</div>

## 라우트

| 메서드 | 라우트 | 목적 |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | 버전 지정 스키마, 범위 지원 및 페이지 한도 목록 표시 |
| `GET` | `/v1/agent/metrics` | 쿼리 가능한 정규 측정 항목 ID, 카테고리, 단위 및 요구 사항 반환 |
| `GET` | `/v1/agent/readiness` | 다음 조치와 함께 암호화 컨텍스트 및 새 iPhone 준비 상태 반환 |
| `POST` | `/v1/agent/query` | 제한된 타입 지정 쿼리 페이지 하나 실행 |
| `POST` | `/v1/agent/evidence` | 제한된 사실 기반 증거 패킷 페이지 하나 파생 |
| `POST` | `/v1/agent/refresh` | iPhone의 명시적 범위를 암호화된 Mac 컨텍스트로 가져오기 |
| `GET` | `/v1/agent/jobs/{id}` | 영속 로컬 가져오기 작업 확인 |
| `POST` | `/v1/agent/jobs/{id}/resume` | 변경 불가능한 가져오기 요청 재개 |
| `POST` | `/v1/agent/jobs/{id}/cancel` | 명시적 취소 요청 |

이전 `/v1/agent/profiles` 및 `/v1/agent/activity/query` 라우트는 `410 removed_endpoint`를 반환합니다.

직접 iPhone 백엔드는 이 HTTP 라우트를 호스팅하지 않습니다. 독립 실행형 `healthmd` 명령은 정규 추출 및 내보내기에 이를 사용하고, `healthmd mcp serve`는 iPhone 쿼리 프로토콜 v3를 통해 새 타입 지정 쿼리, 증거, 측정 항목 카탈로그, 준비 상태, 시각화 및 영속 내보내기 도구를 직접 구현합니다. 페어링과 MCP는 동일한 실행 파일 식별 정보를 사용하며, 새로 고침과 암호화된 Mac 컨텍스트는 이 HTTP API에만 해당합니다.

## CLI 어댑터 우선 사용

저수준 CLI는 요청 본문을 정확히 유지하고 루프백 전송 오류를 처리합니다.

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

`--json JSON`은 작은 본문에 사용하고, 그 밖에는 `--input`을 사용하세요. CLI는 이러한 명령에 제공한 JSON을 암묵적으로 넓히거나 좁히지 않습니다.

일반 워크플로에는 `healthmd query`, `healthmd sleep sessions` 또는 `healthmd compare` 같은 고수준 명령을 사용하세요. 선택자를 검증하고 타입 지정 작업을 대신 구성합니다.

## 쿼리 본문

`POST /v1/agent/query`는 최상위에서 `request`와 선택적 `detail_level`만 허용합니다.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

알 수 없는 래퍼 필드는 거부됩니다. 쿼리 요청 계약은 측정 항목, 소스, 날짜, 작업 및 페이지 제어를 정의합니다. `detail_level`은 `summary` 또는 `lossless`입니다.

응답은 `healthmd.query_response` v1입니다. 타입이 지정된 항목, 데이터 범위, 증거, 소스 설명자, 제한 사항 및 선택적 `next_cursor`가 포함됩니다.

[`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json)에서 완전한 합성 응답을 확인하세요.

## 커서 계속 사용

다음 페이지를 요청하려면 동일한 의미적 요청을 보내고 반환된 커서를 `page.cursor`에 넣습니다.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

`next_cursor`가 없어질 때까지 따라가세요. 커서는 인증되며 요청 및 암호화된 데이터 모음의 리비전에 연결됩니다. Health.md는 수정되거나 일치하지 않거나 오래된 커서를 거부합니다.

페이지 한도는 전체 기록 또는 결과 제한을 두지 않고 각 요청을 보호합니다.

## 증거 본문

`POST /v1/agent/evidence`는 동일한 래퍼를 사용합니다. 작업은 패킷 종류와 명시적으로 선택한 세부 정보가 포함된 `derive_packet`입니다.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

응답은 페이지로 나뉜 쿼리 응답으로 유지되며 `healthmd.evidence_packet` v1 조각을 포함합니다. 사실에는 타입이 지정된 값과 증거가 포함됩니다. 패킷에는 사실 관측만 제공한다는 제한 사항이 포함됩니다.

완전한 합성 응답은 [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json)을 참조하세요.

## 새로 고침 본문

새로 고침은 명시적 범위만 가져옵니다. 본문에는 날짜, 측정 항목, 소스, 세부 정보 수준 및 유한한 대기 시간을 지정할 수 있습니다.

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Mac은 현재 카탈로그에 대해 범위를 검증하고 변경 불가능한 정규 선택으로 변환합니다. iPhone은 선택된 일반 HealthKit 유형만 읽습니다. 요청 범위 설정은 저장된 iPhone 내보내기 환경설정을 변경하지 않습니다.

새로 고침은 전용 `encrypted_context` 전송 모드를 사용합니다.

- 내보내기 파일을 쓰지 않습니다.
- 파일 내보내기 할당량을 사용하지 않습니다.
- 제한되고 재개 가능한 파티션을 전송합니다.
- Mac은 결정론적 압축 소유자 날짜를 각각 커밋한 뒤 확인합니다.
- 정확한 요청이 영속 작업과 함께 유지됩니다.

제공자 전용 범위에는 Apple Health 읽기가 필요하지 않습니다. 제공자 고유 기록은 제공자 고유 증거로 유지되며 합성 Apple Health 측정 항목으로 변환되지 않습니다.

## 사용 가능한 모든 항목 선택

측정 항목 및 날짜 선택자는 `all_available`을 사용할 수 있습니다.

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

iPhone은 선택한 Apple Health 레코드 중 가장 이른 날짜와 오늘까지의 모든 소스 기준 달력 날짜를 확인합니다. 제공자 가져오기는 제공자 고유 기록 커서를 따릅니다. 재개 시 요청이 바뀌지 않도록 확인된 식별자를 전송 전에 고정합니다.

고정된 날짜 또는 결과 제한은 없습니다. 파티션, 페이지, 하루 단위 복호화, 디스크 공간 및 유한 대기가 리소스를 제한합니다.

## 영속 가져오기 작업

새로 고침 대기 시간이 초과되어도 작업은 계속될 수 있습니다. 응답에는 작업 ID와 안전한 진행 상황이 포함됩니다.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

작업은 생성 7일 후 만료됩니다. 재개는 동일한 요청, Mac, iPhone, 소스 범위 및 커밋된 경계를 재사용합니다.

취소는 iPhone 확인 후에만 최종 상태가 됩니다. iPhone을 사용할 수 없으면 작업이 취소 대기 상태로 남을 수 있습니다.

## 직접 HTTP 호출

CLI 사용을 권장하지만 로컬 소프트웨어가 HTTP를 직접 호출할 수도 있습니다.

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

리스너는 제한된 헤더와 JSON 본문, 명시적 메서드 및 콘텐츠 유형, 수신 기한 및 유한한 요청 동작을 적용합니다.

직접 HTTP 클라이언트를 동일한 Mac에 유지하세요. LAN 바인딩, 프록시, 터널 또는 원격 HTTP MCP 래퍼를 추가하지 마세요.

## 타입 지정 값 및 누락 상태

쿼리 결과는 타입과 단위를 보존합니다. 값은 수량, 기간, 개수, 문자열, 카테고리, Boolean, 타임스탬프, 달력 날짜, 중첩 배열 또는 알 수 없는 향후 타입 지정 값일 수 있습니다.

누락 상태에는 complete-empty, partial, failed, unsupported, skipped, cancelled, not requested, legacy unavailable, redacted 및 not synchronized가 포함됩니다. 소비자는 이를 0으로 강제 변환해서는 안 됩니다.

데이터 범위에는 요청 범위와 사용 가능한 범위, 고려한 날짜, 값이 있는 날짜 및 상태가 포함된 압축 누락 구간이 포함됩니다.

## 오류 처리

오류는 안정적인 코드, 메시지, 재시도 가능 여부 및 타입이 지정된 세부 정보가 포함된 `healthmd.query_error` v1을 사용합니다. 다음에 대한 개별 오류가 있습니다.

- 잘못된 페이지 제어
- 잘못되거나 변조된 커서
- 커서와 쿼리 불일치
- 오래된 데이터 모음 리비전
- 잘못된 날짜 범위
- 측정 항목 또는 소스 검증
- 단위 또는 집계 불일치
- 지원되지 않는 작업
- 증거 범위 위반
- iPhone 또는 암호화 저장소 준비 상태
- 영속 작업 상태

결과를 알 수 없는 새로 고침을 무작정 재시도하지 마세요. 먼저 작업 상태를 확인하세요.

## 관련 문서

<div class="related">
  <a href="/ko/docs/agents/"><span>개요</span>로컬 에이전트 및 건강 컨텍스트: 설정, 암호화 저장소, 범위 및 보고 규칙.</a>
  <a href="/ko/docs/agent-queries/"><span>고수준</span>타입 지정 쿼리 활용법: 일반적인 측정 항목, 수면, 운동 및 증거 질문을 위한 검증된 명령.</a>
  <a href="/ko/docs/mcp/"><span>도구</span>로컬 MCP 서버: stdio 구성, 타입 지정 도구, 페이징 및 샌드박스 제한.</a>
  <a href="/ko/docs/reference/api-and-cli/"><span>참조</span>API 및 CLI 계약: 내보내기, 추출, 쿼리, 직접 백엔드 및 운영 제한.</a>
  <a href="/ko/docs/reference/evidence-packets/"><span>데이터 계약</span>압축 쿼리 및 증거 패킷: 유형, 커서, 작업 및 결정론적 패킷 ID.</a>
</div>
