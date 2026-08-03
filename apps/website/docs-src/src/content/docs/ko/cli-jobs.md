---
title: "영속 CLI 작업 및 자동화"
description: "기계 판독 가능 출력, 대기 시간 제한, 7일간 유지되는 영속 작업, 명시적 부분 상태, 재개 및 확인된 취소를 사용하여 healthmd를 안전하게 자동화합니다."
---

Health.md는 연결된 내보내기 및 컨텍스트 가져오기 작업을 영속 작업으로 취급합니다. 작업 수명은 작업을 시작한 프로세스와 별개입니다. 터미널이 닫히거나 네트워크 연결이 끊겨도 완료된 파티션은 폐기되지 않습니다.

명령에 더 좁은 규칙이 명시되지 않는 한 이 페이지는 파일 내보내기, 엄격한 원시 내보내기, 정규 추출 및 새로운 암호화 컨텍스트 가져오기에 적용됩니다.

## 핵심 규칙

제한 시간 초과 또는 연결 해제는 취소를 뜻하지 않습니다.

결과를 알 수 없을 때 중복 작업을 시작하지 마세요. 반환된 작업 ID를 저장하고 상태를 확인한 뒤 동일한 작업을 재개하세요.

내보내기, 원시 및 추출 작업은 최상위 수명 주기 명령을 사용합니다.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

암호화 컨텍스트 가져오기 작업은 로컬 에이전트 수명 주기를 사용합니다.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## 7일 수명

영속 작업에는 생성 7일 후로 고정된 `expires_at`이 있습니다. 진행되어도 연장되지 않습니다. 양쪽 피어는 변경 불가능한 요청과 안전한 재개에 필요한 커밋된 전송 상태를 유지합니다.

작업에는 다음이 유지될 수 있습니다.

- 정확한 날짜 또는 확인된 전체 기록 식별자
- 측정 항목, 카테고리, 소스 및 세부 정보 범위
- 백엔드 및 페어링된 기기 연결
- 설정 정책
- 원시 프로필 또는 추출 선택
- 파일 대상 식별 정보
- 요청 지문
- 세션 및 전송 매니페스트
- 파티션 다이제스트 체인
- 커밋된 파티션 및 바이트 경계
- 완료 또는 취소 확인

재개 시 이러한 필드를 다르게 해석할 수 없습니다.

## 상태는 단순한 실행 중 또는 완료가 아님

작업 응답에는 다음이 포함될 수 있습니다.

| 필드 | 의미 |
|---|---|
| `durable` | 작업에 복구 가능한 작업 상태가 있는지 여부 |
| `state` | 현재 영속 수명 주기 상태 |
| `job_id` | 안정적인 작업 식별자 |
| `session_id` | 연결된 전송 세션 식별자 |
| `paused` | 동일한 iPhone을 다시 연결해야 하는지 여부 |
| `processed_days` / `total_days` | 논리적 소유자 날짜 진행 상황 |
| `committed_partitions` | 수신 측에서 영속적으로 확인한 파티션 |
| `committed_bytes` | 안전하게 커밋된 페이로드 바이트 |
| `fraction_complete` | 건강 값이 포함되지 않은 진행률 |
| `expires_at` | 고정된 작업 만료 타임스탬프 |

상태 필드에는 날짜, ID, 개수, 바이트 및 안전한 오류가 포함됩니다. 건강 샘플은 포함하지 않아야 합니다.

## 명시적인 출력 계획으로 작업 시작

원시 내보내기:

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

정규 추출:

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

직접 생성 파일:

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

요청을 시작하기 전에 최종 출력 또는 대상을 선택하세요. 원시 작업은 출력 동작을 고정합니다. 직접 파일 작업은 정확한 대상 루트를 변경 불가능한 요청에 고정합니다.

## 재개

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

직접 모드에서는 원래 요청에 사용한 것과 동일한 백엔드, 기기, 전송, 포트 및 iPhone을 선택하세요.

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

연결이 끊긴 뒤 보류 중인 바이트는 폐기될 수 있습니다. 커밋된 파티션은 다시 전송되거나 재해석되지 않습니다. 수신 측은 모든 변경 불가능한 설명자가 일치할 때만 이미 커밋된 파티션을 허용합니다.

파일 작업은 재개 중 대체 대상을 허용하지 않습니다. 원래 루트가 변경되면 Health.md는 다른 폴더에 쓰지 않고 안전하게 실패합니다.

## 취소

작업을 만든 수명 주기를 사용하세요.

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

취소는 두 단계로 진행됩니다.

1. CLI가 영속 취소 요청을 기록하고 전송합니다.
2. iPhone이 취소를 확인하여 최종 상태로 만듭니다.

iPhone을 사용할 수 없으면 작업은 `cancellation_pending` 상태로 유지됩니다. 동일한 iPhone을 다시 열고 취소를 재시도하세요. 로컬 의도만을 근거로 작업이 취소되었다고 보고하지 마세요.

Ctrl-C를 수신한 프로세스는 최종 취소 상태를 꾸며내지 않고 종료해야 합니다. 취소하려는 경우 명시적 취소 명령을 사용하세요.

## 출력 채널

Health.md는 명령 결과와 진행 상황을 분리합니다.

| 채널 | 내용 |
|---|---|
| stdout | 버전이 지정된 JSON 명령 결과, 오류 또는 요청한 JSON/JSONL 스트림 |
| stderr | 일반 텍스트 페어링 지침, 건강 값이 포함되지 않은 진행 상황, 스트리밍 시 JSONL 수신 확인 및 사용법 텍스트 |
| `--output PATH` | 원자적으로 커밋된 건강 데이터 포함 JSON 또는 JSONL |
| `OUTPUT.receipt.json` | JSONL 파일 출력용으로 건강 값이 포함되지 않은 추출 수신 확인 |

`--help`는 일반 텍스트입니다. 실행 전 인수 오류는 stderr를 사용하고 종료 코드 2를 반환합니다. 명령 실행 후 런타임 실패는 기계 판독 가능 JSON을 사용합니다.

자동화 파서에서 stdout과 stderr를 합치지 마세요.

## 종료 상태 및 데이터 상태

프로세스 종료 상태는 하나의 신호일 뿐입니다. 성공했다고 판단하기 전에 응답을 파싱하세요.

| 결과 | 기본 종료 동작 |
|---|---|
| 완전한 성공 | 0 |
| 요청 범위가 complete-empty | 0 |
| 검증된 부분 엄격 원시 또는 추출 | 0이 아님 |
| 명시적 `--allow-partial`을 사용한 부분 결과 | 0, 하지만 응답은 부분 상태 유지 |
| 인수 오류 | 종료 코드 2, stderr의 일반 텍스트 |
| 검증 또는 전송 실패 | 구조화된 런타임 오류와 함께 0이 아님 |

`--allow-partial`은 허용 정책이지 데이터 복구가 아닙니다. 누락된 날짜, 실패한 쿼리, 지원되지 않는 유형 및 경고가 모두 계속 표시됩니다.

## 페이지 순회는 작업 완료와 별개

타입 지정 쿼리 응답은 페이지로 나뉩니다. 새 가져오기 작업이 완료되어도 쿼리에 다음 페이지가 있을 수 있습니다.

`--all-pages`를 사용하지 않으면 `next_cursor`를 확인하세요. 다음 페이지가 있으면 고수준 CLI는 전체 순회를 완료했다고 주장하지 않고 `partial_success`를 보고합니다.

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages`는 불투명 커서를 따라가고 반복을 확인하며 전체 페이지 및 바이트 한도를 적용합니다. 한도에 도달하면 범위를 좁히거나 저수준 API를 사용하여 수동으로 페이지를 탐색하세요. 숨겨진 전체 결과 제한은 없지만 한 번의 호출은 제한됩니다.

## 새 데이터, 캐시 및 범위 재사용

고수준 쿼리 명령은 기본적으로 iPhone의 새 데이터를 가져옵니다.

```bash
healthmd query --metric resting_heart_rate --last 30
```

오래된 컨텍스트를 허용할 수 있을 때만 캐시된 데이터를 사용하세요.

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Health.md가 요청 날짜에 대해 측정 항목을 고려한 완전한 요약 범위를 확인한 뒤에만 가져오기를 건너뛰려면 `--reuse-covered`를 사용하세요.

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

재사용 단축 경로는 무손실 데이터나 새로 투영한 수면 세션 작업에는 적용되지 않습니다. 다른 제공자의 데이터나 오래된 블롭을 이 요청이 새로 완료되었다는 증거로 취급하지 않습니다.

## 셸 예제

이 예제는 건강 페이로드를 보호된 파일에 보관하고 안전한 상태 필드만 출력합니다. GNU `timeout`이 설치되어 있다고 가정합니다. 다른 자동화 호스트에서는 자체 프로세스 시간 제한을 적용해야 합니다.

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

건강 JSON을 스트리밍하거나 민감한 경로가 포함될 수 있는 명령 주변에서 `set -x`를 활성화하지 마세요.

## 결과를 알 수 없을 때 에이전트 동작

에이전트 또는 스케줄러는 다음 순서를 따라야 합니다.

1. 구조화된 오류와 작업 ID를 읽습니다.
2. 로컬에서 `status --job`을 실행합니다.
3. 작업이 일시 중지, 최종 상태, 만료 또는 확인 대기 중인지 확인합니다.
4. 새 작업 또는 확인이 필요하면 동일한 iPhone을 다시 엽니다.
5. 동일한 백엔드와 기기로 기존 작업을 재개합니다.
6. 이전 결과가 확인되었거나 만료를 명시적으로 수락한 뒤에만 새 작업을 시작합니다.

파일 커밋 자체가 멱등적이어도 변경 작업을 무작정 재시도하면 소스 작업이 중복될 수 있습니다.

## 일반적인 기계 판독 가능 오류

| 코드 | 의미 | 안전한 대응 |
|---|---|---|
| `timed_out` | 작업 완료 전에 명령의 대기가 중지됨 | 반환된 작업을 확인하고 재개 |
| `job_not_found` | 해당 ID의 로컬 영속 레코드가 없음 | 새로 시작하기 전에 백엔드와 상태 디렉터리 확인 |
| `job_expired` | 고정된 7일 기한이 지남 | 간격을 기록하고 적절하면 새 요청 생성 |
| `direct_export_paused` | 직접 작업에 페어링된 iPhone이 다시 필요함 | iPhone을 다시 열고 재개 |
| `direct_cancellation_pending` | 로컬 취소 의도에 iPhone 확인이 없음 | iPhone을 다시 열고 취소 재시도 |
| `invalid_direct_raw_response` | 엄격한 원시 검증 실패 | 출력을 사용하지 않음 |
| `invalid_direct_file_receipt` | 파일 매니페스트 또는 커밋 수신 확인 검증 실패 | 파일을 수동으로 복구하거나 추가하지 않음 |
| `partial_canonical_extraction` | 요청한 추출이 불완전함 | 수신 확인을 살펴보고 허용할 때만 부분 결과 선택 |
| `unvalidated_response_too_large` | 현재 검증 범위에서 결과 하나를 노출할 수 없음 | 범위를 좁히거나 적합한 출력 모드 사용 |
| `stale_cursor` | 페이지 커서 발급 후 암호화 컨텍스트가 변경됨 | 현재 데이터 모음에 대해 쿼리 다시 시작 |

## 페이로드를 기록하지 않는 진행 상황

고수준 쿼리 단계 및 페이지 순회에는 `--progress-json`을 사용하세요.

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

진행 상황 JSONL에는 단계, 페이지 수, 항목 수, 날짜 및 안전한 진단이 포함될 수 있습니다. 건강 값은 포함하지 않아야 합니다. 최종 결과와 분리하고 적절한 보존 정책을 적용하세요.

## 관련 문서

<div class="related">
  <a href="/ko/docs/cli/"><span>설정</span>Health.md CLI: 설치, 백엔드 선택 및 명령 출력 이해.</a>
  <a href="/ko/docs/cli-direct/"><span>직접</span>직접 iPhone CLI: 페어링, 제한된 백그라운드 시간, 명시적 대상 및 신뢰할 수 있는 재개.</a>
  <a href="/ko/docs/agent-queries/"><span>페이징</span>타입 지정 쿼리 활용법: 새 데이터 및 캐시 모드, 페이지 순회, 데이터 범위 및 수신 확인.</a>
  <a href="/ko/docs/reference/generated/cli/exit-codes/"><span>생성된 계약</span>CLI 종료 코드: 프로덕션에서 생성된 상태 및 오류 동작.</a>
</div>
