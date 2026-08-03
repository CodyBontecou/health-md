---
title: "Health.md CLI"
description: "Mac 앱 또는 직접 iPhone 백엔드를 선택하고, healthmd를 설치하며, 준비 상태를 확인하고, 파일을 내보내고, 정규 Apple Health 데이터를 추출하고, 타입 지정 쿼리와 영속 작업 자동화를 실행합니다."
---

`healthmd` 명령에는 두 가지 작동 모드가 있습니다. 암호화된 로컬 쿼리, MCP 도구 또는 Mac용 Health.md에서 이미 선택한 대상 폴더가 필요하면 Mac 앱 백엔드를 사용하세요. Mac 앱을 실행하지 않고 원시 데이터나 생성된 파일이 필요하면 직접 iPhone 백엔드를 사용하세요.

<div class="callout">
<strong>HealthKit은 iPhone에 유지됩니다.</strong>
<p style="margin-top:6px;">어느 CLI 백엔드도 컴퓨터에서 Apple Health를 읽지 않습니다. 현재 열려 있는 Health.md iPhone 앱이 새로운 HealthKit 읽기를 수행합니다. CLI는 검증된 결과 또는 파일을 받습니다.</p>
</div>

## 백엔드 선택

| 기능 | Mac 앱 백엔드 | 직접 iPhone 백엔드 |
|---|---|---|
| 번들 Mac 도우미의 기본값 | 예 | 아니요, `--backend direct`로 선택 |
| Mac용 Health.md를 열어야 함 | 예 | 아니요 |
| 새 데이터를 위해 iPhone에서 Health.md를 열어야 함 | 예 | 예 |
| 파일 대상 | Mac 앱에서 선택한 폴더 | 기존 절대 경로 `--destination` |
| 엄격한 원시 내보내기 | 예 | 예 |
| 정규 `healthmd extract` | 예 | 예 |
| 암호화된 컨텍스트, 타입 지정 쿼리 및 증거 | 예 | 아니요 |
| `healthmd-mcp` | 예 | 아니요 |
| 수동 IP 또는 Tailscale | Mac 동기화 또는 명시적 직접 모드 | 예 |
| 근거리 직접 전송 | 번들 Swift 도우미만 | 이식 가능한 Rust 클라이언트에서는 지원하지 않음 |

백엔드 및 전송 선택은 절대로 암묵적으로 대체되지 않습니다. 직접 명령이 쿼리를 충족하기 위해 Mac 앱으로 전환할 수 없으며, 실패한 근거리 연결이 수동 IP로 전환될 수도 없습니다.

## 번들 Mac 도우미 설치

<div class="availability available">
<strong>현재 사용 가능 · Mac용 Health.md</strong>
<p>서명된 Swift CLI 및 MCP 도우미는 출시된 Mac 앱에 포함됩니다.</p>
</div>

Mac용 Health.md에는 서명된 `healthmd` 및 `healthmd-mcp` 도우미가 포함되어 있습니다. Mac 앱을 열고 **CLI**를 선택하면 설치된 앱의 경로, 설정 명령, 에이전트 프롬프트 및 선택적 에이전트 스킬 설치 프로그램을 볼 수 있습니다.

일반적인 앱 번들 경로는 다음과 같습니다.

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

한 셸 세션에서 별칭을 사용하려면 다음을 실행합니다.

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

또는 사용자가 소유한 bin 디렉터리에 영구 심볼릭 링크를 만듭니다.

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

셸에 `~/.local/bin`이 아직 포함되지 않았다면 `PATH`에 추가합니다.

```bash
export PATH="$HOME/.local/bin:$PATH"
```

MCP stdio 루프를 시작하지 않고 CLI를 확인합니다.

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor`는 Mac, 암호화된 컨텍스트 및 iPhone 준비 상태가 담긴 `healthmd.cli_doctor` JSON을 반환합니다. 건강 값은 출력하지 않습니다.

## 이식 가능한 CLI 상태

<div class="availability preview">
<strong>미리보기 · 아직 공개 패키지로 제공되지 않음</strong>
<p>크로스 플랫폼 Rust CLI는 실물 iPhone 출시 QA와 첫 번째 적격 패키지를 기다리고 있습니다.</p>
</div>

독립 실행형 Rust CLI는 `0.1.0-alpha.1`로 개발 중입니다. macOS, Linux 및 Windows에서 실행되고 기본적으로 직접 수동 IP 또는 Tailscale 연결을 사용하며 Mac 앱이 필요하지 않습니다. 프로토콜 호환성과 언어 간 픽스처는 구현되었지만 첫 공개 출시 전에 실물 iPhone 출시 QA와 공개 패키징을 완료해야 합니다.

출시되기 전까지는 번들 Mac 도우미를 사용하세요. 공개되지 않은 Homebrew, crates.io, GitHub 설치 프로그램 또는 다운로드 URL에 의존하지 마세요.

이식 가능한 클라이언트는 세 플랫폼 모두에서 원시 내보내기, 정규 추출, 페어링, 상태, 재개, 취소 및 생성 파일 대상을 지원합니다. 프로토콜 v1 파일 내보내기에서 iPhone은 대상을 불투명한 대상 레이블로 취급하고, 수신 CLI는 호스트 파일 시스템에서 이를 검증해 영속적으로 결합합니다.

## 명령 목록

| 명령 | 목적 | 백엔드 |
|---|---|---|
| `healthmd status` | 실시간 준비 상태 또는 로컬 영속 작업 하나 확인 | 둘 다 |
| `healthmd doctor` | Mac, 암호화된 컨텍스트 및 iPhone 준비 상태 설명 | Mac 앱 |
| `healthmd metrics list` | 쿼리 가능한 정규 측정 항목 카탈로그 반환 | Mac 앱 |
| `healthmd extract` | 선택한 정규 `healthmd.health_data` 객체 가져오기 | 둘 다 |
| `healthmd query` | 선택한 타입 지정 측정 항목을 가져와 쿼리 | Mac 앱 |
| `healthmd sleep sessions` | 일급 객체인 수면 세션 및 고정 구간 반환 | Mac 앱 |
| `healthmd training align` | 운동을 직전 및 직후 수면과 시간순으로 대조 | Mac 앱 |
| `healthmd workouts` | 증거와 함께 타입이 지정된 운동 목록 표시 | Mac 앱 |
| `healthmd coverage` | 날짜 및 측정 항목 범위 또는 누락 확인 | Mac 앱 |
| `healthmd compare` | 호출자가 선택한 집계로 정확한 기간 비교 | Mac 앱 |
| `healthmd evidence training` | 사실 기반 훈련 증거 패킷 생성 | Mac 앱 |
| `healthmd export` | 생성 파일을 쓰거나 엄격한 원시 JSON 반환 | 둘 다 |
| `healthmd resume` | 변경 불가능한 영속 내보내기 작업 재개 | 둘 다 |
| `healthmd cancel` | 명시적 취소 요청 | 둘 다 |
| `healthmd agent ...` | 저수준 루프백 쿼리 및 작업 API 호출 | Mac 앱 |
| `healthmd direct ...` | 직접 iPhone 신뢰 페어링, 목록 표시 및 제거 | 직접 |

## 첫 번째 Mac 앱 워크플로

1. Mac에서 Health.md를 열고 파일을 쓸 예정이라면 대상 폴더를 선택합니다.
2. 페어링된 iPhone에서 Health.md를 열고 Mac 연결을 기다립니다.
3. 준비 상태를 확인합니다.
4. 긴 기록을 요청하기 전에 작은 명령을 실행합니다.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

새 쿼리는 지정된 측정 항목, 소스, 날짜 및 요약 또는 무손실 세부 정보만 가져옵니다. 저장된 iPhone 내보내기 설정은 변경하지 않습니다.

## 파일 및 원시 내보내기

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings
```

현재 날짜 수 상한은 없습니다. `--all`은 iPhone에 선택한 소스 레코드 중 가장 이른 날짜를 찾도록 요청하고, 확인된 범위를 고정한 뒤 제한된 파티션으로 처리합니다. 사용 가능한 저장 공간과 비정상적으로 데이터가 밀집된 하루는 여전히 실질적인 제한입니다.

`--raw`는 iPhone 환경설정을 변경하지 않고 일시적으로 정규 무손실 소스 레코드를 요청합니다. 생성 파일을 쓰지 않으며 연결된 제공자 사이드카를 포함하지 않습니다.

## 정규 추출 또는 파생 쿼리

소스 형태의 데이터가 필요하면 `extract`를 사용하세요.

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

타입이 지정되고 증거가 연결된 보기가 필요하면 쿼리 명령을 사용하세요.

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7은 공개 소스 계약입니다. 쿼리, 증거, 작업 및 수신 확인 스키마는 전송 또는 파생 보기를 설명합니다. 소스 스키마를 대체하지 않습니다.

## 기계 판독 가능 동작

명령은 기본적으로 버전 지정 JSON을 stdout이나 명시적인 `--output` 경로에 출력합니다. 정규 추출은 JSONL을 선택할 수 있고, 고수준 쿼리는 의도적으로 일부 정보를 생략한 표 출력을 선택할 수 있습니다. 건강 값이 포함되지 않은 진행 상황은 stderr로 전달될 수 있습니다. `--help`는 일반 텍스트입니다. 명령 시작 전 인수 오류는 종료 코드 2와 함께 stderr에 일반 텍스트로 표시됩니다.

프로세스가 성공적으로 종료되었다는 사실만으로 건강 데이터의 완전성을 입증할 수 없습니다. 다음을 확인하세요.

- 최상위 상태
- 요청 범위 상태
- 일별 및 쿼리별 결과
- 누락 구간
- `next_cursor` 또는 순회 수신 확인
- 소스 스키마 및 버전
- 제한 사항 및 경고

complete-empty 결과는 Health.md가 요청 범위를 표현했지만 관측값을 찾지 못했다는 뜻입니다. 0, 누락, 실패, 건너뜀 또는 미지원과는 다릅니다.

## 안전한 자동화

자동화 호스트의 프로세스 제한 시간을 사용하고 프롬프트가 없어야 하는 명령에서는 stdin을 닫으세요. GNU `timeout`이 있는 시스템에서는 다음과 같이 실행합니다.

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

시간 초과, Ctrl-C, 프로세스 종료, 네트워크 손실 및 iOS 백그라운드 시간 소진은 영속 작업을 취소하지 않습니다. 중복 작업을 시작하지 말고 작업 ID를 확인하여 재개하세요.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

iPhone의 확인 응답이 있어야만 취소가 최종 상태가 됩니다.

## 개인정보 보호 규칙

원시 및 무손실 출력에는 정확한 타임스탬프, 경로, 임상 레코드, 약물, 기분 항목, ECG 값, 출처 및 첨부 파일이 포함될 수 있습니다. 터미널 출력보다 출력 파일을 우선하세요. 페이로드를 이슈 보고서, 에이전트 기록, CI 로그 또는 셸 추적에 붙여 넣지 마세요.

로컬 쿼리 API에는 bearer 토큰, 등록, 액세스 프로필 또는 권한 부여 데이터베이스가 없습니다. 루프백 도달 가능성이 전체 액세스 경계입니다. Mac 앱이 열려 있는 동안 모든 로컬 프로세스가 사용할 수 있으므로 포트 `17645`를 다른 컴퓨터에 프록시하거나 노출하지 마세요.

## 다음 가이드

<div class="related">
  <a href="/ko/docs/cli-direct/"><span>Mac 앱 불필요</span>직접 iPhone CLI: 페어링, 전송, 원시 및 파일 내보내기, 백그라운드 동작, 플랫폼 지원.</a>
  <a href="/ko/docs/cli-extract/"><span>소스 데이터</span>정규 추출: 측정 항목, 객체, 세부 정보, JSON Pointer, JSONL 및 수신 확인을 선택합니다.</a>
  <a href="/ko/docs/cli-jobs/"><span>자동화</span>영속 작업: 시간 초과, 재개, 취소, 부분 결과 및 안전한 스크립팅.</a>
  <a href="/ko/docs/agents/"><span>에이전트</span>로컬 에이전트 워크플로: 암호화된 컨텍스트, 직접 범위, 타입 지정 명령 및 증거.</a>
  <a href="/ko/docs/mcp/"><span>MCP</span>샌드박스 stdio 도우미를 구성하고 도구 경계를 검토합니다.</a>
  <a href="/ko/docs/reference/api-and-cli/"><span>계약</span>API 및 CLI 참조: 정확한 라우트, 스키마, 응답 및 생성된 픽스처.</a>
</div>
