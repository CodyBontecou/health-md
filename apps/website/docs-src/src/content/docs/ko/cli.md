---
title: "Health.md CLI"
description: "독립 실행형 healthmd CLI를 macOS, Linux, Windows에 설치하고 iPhone 또는 Android 기기와 직접 페어링하여 준비 상태 확인, 데이터 내보내기, 쿼리 실행, 영속 작업 관리를 수행합니다. Mac 앱이 필요 없습니다."
---

독립 실행형 `healthmd` CLI는 macOS, Linux, Windows에서 작동하며 iPhone(프로토콜 v1) 또는 Android(프로토콜 v2)에서 열린 Health.md 앱과 직접 페어링합니다. Mac용 Health.md를 전혀 필요로 하지 않고, 백엔드 선택도 존재하지 않으며, 컴퓨터에서 Apple Health나 Health Connect를 읽지 않습니다.

<div class="callout">
<strong>건강 데이터는 휴대전화에 유지됩니다.</strong>
<p style="margin-top:6px;">CLI는 컴퓨터에서 Apple Health 또는 Health Connect를 읽지 않습니다. iPhone 또는 Android에서 현재 열려 있는 Health.md 앱이 새로운 플랫폼 건강 읽기를 수행합니다. CLI는 검증된 결과 또는 파일을 받습니다.</p>
</div>

## 독립 CLI 설치

<div class="availability preview">
<strong>공개 미리보기 · 아직 검증된 안정 버전 아님</strong>
<p>크로스 플랫폼 Rust CLI는 공개 패키지로 제공되지만, 정확한 모바일 매트릭스는 여전히 실기기 출시 검증을 기다리고 있습니다.</p>
</div>

macOS 또는 Linux에서는 <code>brew install CodyBontecou/tap/healthmd</code>로 미리보기를 설치합니다. 출시 증거가 명시하는 정확한 모바일 빌드를 사용하세요. 패키지 게시는 모바일 호환성을 증명하지 않습니다.

독립 실행형 Rust CLI는 macOS, Linux, Windows에서 작동하고 Manual IP 또는 Tailscale 직접 연결을 사용하며 Mac 앱이 필요 없습니다. 프로토콜 v1으로 iPhone 소스와, 프로토콜 v2로 Android 소스와 페어링하며 Swift↔Rust 및 Kotlin↔Rust 자동 호환성 게이트를 갖춥니다. 프로토콜 호환성은 구현되었지만, 첫 검증된 안정 버전 전에 실기기 출시 QA를 완료해야 합니다. 체크섬 아카이브, PowerShell 설치 관리자, `cargo install healthmd-cli --locked`가 매 출시에 함께 제공됩니다.

이식 가능한 클라이언트는 iPhone과 Android에 대해 세 가지 데스크톱 플랫폼 모두에서 페어링, 상태, 원시 내보내기, 생성 파일 대상, 재개, 취소를 지원합니다. 정규 추출과 타입 지정 MCP 쿼리는 iPhone 기능입니다. Android 원시 스냅샷은 HealthKit 형식으로 변환되지 않고 공급자 고유의 Health Connect 계약을 유지합니다. Android 타입 지정 쿼리는 구현되지 않았습니다. 생성 파일 내보내기에서 휴대전화는 대상을 불투명한 레이블로 취급하고, 수신 CLI가 호스트 파일 시스템 아래에서 검증하고 영구적으로 바인딩합니다. Android 프로토콜 v2는 모든 CLI 운영 체제에서 파일 대상을 확정하며 생성 작업당 4,096개 파일로 제한합니다.

## 명령 목록

| 명령 | 용도 |
|---|---|
| `healthmd status` | 실시간 준비 상태 또는 로컬 영속 작업 확인 |
| `healthmd export` | 생성 파일 쓰기 또는 엄격한 원시 JSON 반환 |
| `healthmd extract` | 선택한 정규 `healthmd.health_data` 객체 획득(iPhone) |
| `healthmd query` | 고정된 타입 지정 쿼리 작업 실행(iPhone) |
| `healthmd resume` | 불변 영속 내보내기 작업 재개 |
| `healthmd cancel` | 명시적 취소 요청 |
| `healthmd direct ...` | 직접 휴대전화 신뢰 페어링, 나열, 제거 |
| `healthmd mcp ...` | 고정 MCP 도구 표면 제공 또는 확인 |
| `healthmd setup codex` | Codex 구성과 iPhone 페어링을 한 번에 수행 |

직접 명령은 iPhone(프로토콜 v1) 또는 Android(프로토콜 v2) 소스와 페어링합니다. 정규 `extract`와 모든 타입 지정 쿼리 명령은 iPhone 기능이며, Android 직접 소스는 공급자 고유의 Health Connect 원시 스냅샷과 생성 파일을 반환합니다.

```bash
# 준비 상태와 로컬 신뢰
healthmd status
healthmd direct devices

# 플랫폼 고유 원시 내보내기. --output을 생략하면 검증된 JSON/NDJSON을 stdout으로 스트리밍
healthmd export --yesterday --raw --output yesterday.json
healthmd export --last 7 --raw --output week.json

# MCP와 동일한 작업 레지스트리를 통한 타입 지정 쿼리(iPhone)
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'

# 범위 지정 정규 추출(iPhone)
healthmd extract --category Sleep --last 7 --output sleep.json

# 모든 CLI 운영 체제에서 프로덕션 생성 파일
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"

# 영속 작업
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --output resumed.json
healthmd cancel JOB_UUID
```

### 이식 가능한 프로필 기반 파일 내보내기

독립 직접 CLI는 지원되는 두 휴대전화 플랫폼에서 저장된 프로필을 안정 ID로 해석할 수 있습니다. 프로필은 고정된 출력 설정을 제공하고, 컴퓨터 대상은 계속 명시됩니다.

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination "$HOME/Documents/HealthVault"
```

`--profile PROFILE_ID`은 `--use-device-settings`나 측정 항목/카테고리 선택기와 결합할 수 없으며, 알 수 없는 ID는 라이브 설정을 사용하지 않고 안전하게 실패합니다. ID는 iPhone 또는 Android의 **설정 → 내보내기 프로필 → 프로필 ID**에서 복사하세요. 자동화와 대상 동작은 [내보내기 프로필](/ko/docs/export-profiles/)을 참고하세요.

이식 가능한 직접 클라이언트는 MCP 래퍼 없이 지원되는 모든 iPhone 타입 지정 작업을 호출할 수 있습니다.

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

## 번들 Mac 도우미

Mac용 Health.md는 앱 안에 서명된 자체 Swift 도우미 `healthmd`와 `healthmd-mcp`를 함께 제공합니다. 이 도우미는 Mac 앱의 기능이지 독립 CLI의 백엔드가 아닙니다. 기본적으로 실행 중인 Mac 앱의 루프백 서버와 통신해 암호화된 로컬 쿼리, MCP 도구, Mac용 Health.md에서 이미 선택한 대상 폴더를 제공하며, `--backend direct`로 선택하는 호환 직접 iPhone 모드도 갖춥니다. 두 클라이언트는 모드를 자동으로 전환하지 않습니다.

<div class="availability available">
<strong>지금 사용 가능 · Mac용 Health.md</strong>
<p>서명된 Swift CLI 및 MCP 도우미는 출시된 Mac 앱에 포함되어 있습니다.</p>
</div>

Mac 앱을 열고 **CLI**를 선택하면 설치된 복사본 경로, 설정 명령, 에이전트 프롬프트, 선택적 에이전트 스킬 설치 관리자를 볼 수 있습니다.

앱 번들의 일반 경로는 다음과 같습니다.

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

한 번의 셸 세션에서 별칭을 사용하려면:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

또는 사용자 소유 bin 디렉터리에 영구 심볼릭 링크를 만듭니다.

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

셸에 아직 포함되어 있지 않다면 `~/.local/bin`을 `PATH`에 추가하세요.

```bash
export PATH="$HOME/.local/bin:$PATH"
```

MCP stdio 루프를 시작하지 않고 도우미를 확인합니다.

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor`는 Mac, 암호화 컨텍스트, iPhone 준비 상태를 담은 `healthmd.cli_doctor` JSON을 반환합니다. 건강 값은 출력하지 않습니다.

### 번들 도우미 명령

| 명령 | 용도 |
|---|---|
| `healthmd export --iphone ...` | Mac 앱을 통해 생성 파일 쓰기 또는 엄격한 원시 JSON 반환 |
| `healthmd status` | Mac/iPhone 준비 상태 또는 영속 작업 확인 |
| `healthmd doctor` | Mac, 암호화 컨텍스트, iPhone 준비 상태 설명 |
| `healthmd metrics list` | 정규 쿼리 가능 측정 항목 카탈로그 반환 |
| `healthmd query` | 선택한 타입 지정 측정 항목 획득 및 쿼리 |
| `healthmd sleep sessions` | 일급 수면 세션과 고정 창 반환 |
| `healthmd training align` | 운동을 이전 및 이후 수면과 정렬 |
| `healthmd workouts` | 증거가 포함된 타입 지정 운동 나열 |
| `healthmd coverage` | 날짜 및 측정 항목 커버리지 또는 누락 확인 |
| `healthmd compare` | 호출자가 선택한 집계로 정확한 기간 비교 |
| `healthmd evidence training` | 사실 기반 훈련 증거 패킷 작성 |
| `healthmd resume` / `healthmd cancel` | 영속 작업 관리 |
| `healthmd agent ...` | 저수준 루프백 쿼리/작업 API 호출 |
| `healthmd --backend direct ...` | 도우미의 호환 직접 iPhone 모드 |

도우미의 직접 모드에서 Mac 컨텍스트 쿼리, 증거, doctor, 측정 항목, 새로 고침 하위 명령은 Mac 앱으로 전환하지 않고 `backend_unsupported`를 반환합니다.

### 첫 Mac 앱 워크플로

1. 파일을 쓸 계획이라면 Mac에서 Health.md를 열고 대상 폴더를 선택합니다.
2. 페어링된 iPhone에서 Health.md를 열고 Mac 연결을 기다립니다.
3. 준비 상태를 확인합니다.
4. 큰 기록을 요청하기 전에 작은 명령을 실행합니다.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

새 쿼리는 제공된 측정 항목, 소스, 날짜, 요약 또는 무손실 세부 사항만 획득합니다. iPhone에 저장된 내보내기 설정은 변경하지 않습니다.

### 번들 도우미의 파일 및 원시 내보내기

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

현재 달력 일수 상한은 없습니다. `--all`은 iPhone이 선택한 소스의 가장 오래된 사용 가능한 레코드를 찾아 해석된 범위를 고정하고 제한된 파티션으로 처리합니다. 사용 가능한 저장 공간과 비정상적으로 밀도 높은 하루가 실질적인 한계입니다.

`--raw`는 iPhone 기본 설정을 변경하지 않고 일시적으로 정규 무손실 소스 레코드를 요청합니다. 생성 파일을 쓰지 않고 연결된 공급자 사이드카도 포함하지 않습니다.

## 정규 추출인가 파생 쿼리인가?

소스 원래 형태의 데이터가 필요하면 `extract`를 사용하세요.

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

타입 지정되고 증거에 연결된 뷰가 필요하면 쿼리 명령을 사용하세요. 독립 CLI는 고정된 타입 지정 작업을 제공하고, 번들 Mac 도우미는 아래의 고급 셸도 추가로 제공합니다.

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}'
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v8은 Apple의 공개 소스 계약입니다. 쿼리, 증거, 작업, 영수증 스키마는 전송 또는 파생 뷰를 설명하며 소스 스키마를 대체하지 않습니다. 정규 추출은 iPhone 기능이며, Android 직접 소스는 대신 원시 내보내기를 통해 공급자 고유의 Health Connect 스냅샷을 노출합니다.

## 기계 판독 가능 동작

명령은 기본적으로 stdout 또는 명시적 `--output` 경로에 버전이 지정된 JSON을 사용합니다. 정규 추출은 JSONL을 선택할 수 있고, 고급 쿼리는 의도적으로 손실 있는 표를 선택할 수 있습니다. 건강 값이 없는 진행 상황은 stderr를 사용할 수 있습니다. `--help`는 일반 텍스트입니다. 명령 시작 전 인수 오류는 종료 코드 2와 함께 stderr에 일반 텍스트로 표시됩니다.

프로세스 정상 종료만으로 완전한 건강 데이터를 증명할 수 없습니다. 다음을 확인하세요.

- 외부 상태.
- 요청 범위 상태.
- 날짜별, 쿼리별 결과.
- 누락된 구간.
- `next_cursor` 또는 순회 영수증.
- 소스 스키마와 버전.
- 제한과 경고.

완전히 빈 결과는 Health.md가 요청된 범위를 표현했고 관찰을 찾지 못했다는 뜻입니다. 0, 누락, 실패, 건너뜀, 미지원과 같지 않습니다.

## 안전한 자동화

자동화 호스트의 프로세스 시간 제한을 사용하고, 입력을 요청하지 않아야 하는 명령은 stdin을 닫아 두세요. GNU `timeout`이 있는 시스템에서는:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

시간 초과, Ctrl-C, 프로세스 종료, 네트워크 손실, 소진된 iOS 백그라운드 시간은 영속 작업을 취소하지 않습니다. 작업 ID를 확인하고 중복을 시작하는 대신 재개하세요.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

iPhone이 확인 응답을 해야만 취소가 최종적입니다.

## 개인정보 규칙

원시 및 무손실 출력에는 정확한 타임스탬프, 경로, 임상 기록, 약물, 기분 항목, ECG 값, 출처, 첨부 파일이 포함될 수 있습니다. 터미널 출력보다 파일 출력을 선호하세요. 페이로드를 문제 보고서, 에이전트 기록, CI 로그, 셸 트레이스에 붙여넣지 마세요.

번들 Mac 도우미의 로컬 쿼리 API에는 전달자 토큰, 등록, 액세스 프로필, 권한 데이터베이스가 없습니다. 루프백 도달 가능성이 전체 액세스 경계입니다. Mac 앱이 열려 있는 동안 모든 로컬 프로세스가 사용할 수 있으므로 포트 `17645`를 프록시하거나 다른 컴퓨터에 노출하지 마세요.

## 다음 가이드

<div class="related">
  <a href="/ko/docs/cli-direct/"><span>Mac 앱 불필요</span>직접 휴대전화 CLI: iPhone 또는 Android와 페어링, 전송 방식, 원시 및 파일 내보내기, 백그라운드 동작, 플랫폼 지원.</a>
  <a href="/ko/docs/cli-extract/"><span>소스 데이터</span>정규 추출: 측정 항목, 객체, 세부 사항, JSON 포인터, JSONL, 영수증 선택.</a>
  <a href="/ko/docs/cli-jobs/"><span>자동화</span>영속 작업: 시간 초과, 재개, 취소, 부분 결과, 안전한 스크립팅.</a>
  <a href="/ko/docs/agents/"><span>에이전트</span>로컬 에이전트 워크플로: 암호화 컨텍스트, 직접 범위, 타입 지정 명령, 증거.</a>
  <a href="/ko/docs/mcp/"><span>MCP</span>샌드박스된 stdio 도우미를 구성하고 도구 경계를 검토합니다.</a>
  <a href="/ko/docs/reference/api-and-cli/"><span>계약</span>API 및 CLI 참조: 정확한 라우트, 스키마, 응답, 생성 픽스처.</a>
</div>
