---
title: "직접 iPhone CLI"
description: "수동 IP, Tailscale 또는 지원되는 근거리 전송을 통해 healthmd를 iPhone과 페어링한 뒤 Mac용 Health.md를 실행하지 않고 내보냅니다."
---

직접 백엔드는 명령을 Mac용 Health.md를 통해 라우팅하지 않고 `healthmd`를 열린 Health.md iPhone 앱에 연결합니다. iPhone이 HealthKit을 읽고 보호된 저장소에 결과를 준비한 뒤 검증된 파티션을 CLI로 전송합니다.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone -> HealthKit -> protected bounded spool / typed query evaluator
  -> canonical JSON, production-generated files, or bounded MCP query pages
```

<div class="availability preview">
<strong>미리보기 · 이식 가능한 직접 CLI</strong>
<p>번들 Swift 직접 백엔드는 macOS에서 사용할 수 있습니다. 크로스 플랫폼 Rust 클라이언트는 실제 iPhone 출시 QA와 첫 공개 패키지를 기다리는 알파 버전이며, Linux 및 Windows 명령은 준비된 워크플로를 설명합니다.</p>
</div>

## 직접 모드 지원 기능

- 일회성 페어링 및 신뢰된 재연결
- 로컬 신뢰 기기 확인 및 페어링 해제
- 실시간 iPhone 준비 상태
- 엄격한 원시 스키마 v7 내보내기
- 선택적 정규 추출
- 프로덕션에서 생성된 파일 내보내기
- 영속 로컬 작업 상태 및 재개
- 명시적 취소
- 직접 타입 지정 쿼리, 측정 항목 카탈로그, 증거, MCP Apps UI 및 PNG 대체 출력을 갖춘 동일 실행 파일의 `healthmd mcp serve` stdio 서버

`healthmd` 명령의 직접 백엔드는 Mac 앱의 암호화 컨텍스트 HTTP 라우트를 에뮬레이션하지 않습니다. 따라서 Mac 지향 `doctor`, 쿼리, 증거 및 새로 고침 하위 명령은 백엔드를 전환하지 않고 계속 `backend_unsupported`를 반환합니다. 새로운 직접 iPhone 타입 지정 분석에는 `healthmd mcp serve`를 사용하거나 `healthmd setup codex`를 실행하여 Codex를 자동 구성하고 페어링하세요. `healthmd mcp schema [TOOL]`은 정확한 중첩 MCP 입력 스키마와 예제를 로컬에 출력합니다. 수면에는 `healthmd_sleep_sessions`를 직접 사용하고, 정규 `extract` 출력을 타입 지정 쿼리 API로 취급하지 마세요.

## 요구 사항

- 직접 연결을 지원하는 `healthmd` 바이너리 및 일치하는 Health.md iPhone 빌드
- 페어링 및 새 명령을 위해 iPhone 포그라운드에 열린 Health.md
- iPhone에서 활성화된 **설정 > Mac 동기화 > Direct CLI 액세스**
- 사용 가능한 HealthKit 권한, 보호된 데이터, 로컬 네트워크 권한 및 내보내기 할당량
- 수동 IP용으로 연결 가능한 컴퓨터 주소 및 TCP 포트 `17647`. Tailscale 주소도 사용 가능
- 생성 파일 모드를 위한 기존 절대 경로 대상

CLI가 리스너입니다. iPhone은 Direct CLI 액세스에 입력한 컴퓨터 주소로 연결합니다.

## 전송 지원

| 전송 | macOS 번들 Swift 도우미 | 이식 가능한 Rust 클라이언트 |
|---|---:|---:|
| LAN의 수동 IP | 예 | macOS, Linux, Windows |
| Tailscale 주소 | 예 | macOS, Linux, Windows |
| 근거리 / MultipeerConnectivity | 예 | 아니요 |

근거리는 Apple의 암호화된 Multipeer 세션과 수동 IP에서 사용하는 것과 동일한 Health.md 애플리케이션 인증 및 암호화를 사용합니다. 이식 가능한 클라이언트는 근거리에 대해 `transport_unsupported`를 반환합니다.

## 수동 IP로 한 번 페어링

컴퓨터에서 리스너를 시작합니다.

```bash
healthmd direct pair --transport manual-ip
```

이 명령은 최종 JSON 결과를 위해 stdout을 비워 둔 채 6자리 코드, 후보 컴퓨터 주소 및 리스너 포트를 stderr에 기록합니다.

iPhone에서 다음을 수행합니다.

1. **Health.md > 설정 > Mac 동기화 > Direct CLI 액세스**를 엽니다.
2. Direct CLI 액세스를 활성화합니다.
3. **수동 IP**를 선택합니다.
4. 컴퓨터의 LAN 또는 Tailscale 주소를 입력합니다.
5. 포트 `17647`을 입력합니다. CLI가 다른 전역 `--port`를 사용한다면 해당 포트를 입력하세요.
6. 페어링 코드를 입력하고 페어링을 탭합니다.
7. 양쪽 모두 성공을 보고할 때까지 앱을 열어 둡니다.

페어링 코드는 10분 뒤 만료됩니다. 네트워크로 전송하거나 저장하지 않습니다.

필요하면 다른 포트를 사용하세요.

```bash
healthmd --port 18000 direct pair --transport manual-ip
healthmd --backend direct --port 18000 status
```

이후 상태, 내보내기, 재개 및 취소 명령에서도 동일한 명시적 포트를 계속 사용하세요.

## 근거리로 페어링

근거리는 번들 Swift 도우미에서만 사용할 수 있습니다.

```bash
healthmd direct pair --transport nearby
```

iPhone의 Direct CLI 액세스에서 근거리를 선택하고 표시된 코드를 입력한 뒤 페어링이 끝날 때까지 두 기기를 열어 둡니다. 실패한 근거리 작업이 수동 IP로 전환되지는 않습니다.

## 신뢰 기기

페어링은 Health.md Mac 앱의 동기화 관계와 별도의 신뢰를 만듭니다.

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

이 명령은 로컬 신뢰를 읽거나 수정하며 iPhone에 연결하지 않습니다. iPhone에서는 **페어링된 CLI 지우기**를 사용하여 상대편을 제거하세요.

둘 이상의 iPhone이 신뢰된 경우 원하는 설치를 명시적으로 선택하세요.

```bash
healthmd --backend direct --device DEVICE_UUID status
```

로컬 신뢰가 손상되었거나 교체된 설치에 속할 때만 `healthmd direct reset-trust --confirm`을 사용하세요. 모든 로컬 직접 페어링을 제거합니다. 다시 시작하기 전에 iPhone에서도 해당 페어링을 지우세요.

## 실시간 준비 상태 확인

```bash
healthmd --backend direct --transport manual-ip status
```

직접 상태 응답은 건강 값 없이 연결 및 안전 상태를 보고합니다. 작업 시작 전 다음 필드를 확인하세요.

| 필드 | 준비 상태 |
|---|---|
| `backend` | `direct` |
| `mac_app` | `bypassed` |
| `direct_cli.paired` | `true` |
| `iphone.connected` | `true` |
| `iphone.app_active` | 새 작업의 경우 `true` |
| `iphone.protected_data_available` | `true` |
| `iphone.can_trigger_raw_exports` | 원시 및 추출의 경우 `true` |
| `iphone.can_trigger_exports` | 생성 파일의 경우 `true` |

직접 상태의 대상은 선택되지 않은 상태로 유지됩니다. 파일 모드는 명령에 지정한 명시적 `--destination`만 사용합니다.

## 엄격한 원시 내보내기

범위 선택자 하나를 선택하세요.

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

검증된 JSON을 stdout으로 스트리밍하려면 `--output`을 생략하세요. 민감하거나 큰 응답에는 출력 파일이 더 안전합니다.

엄격한 원시는 `healthmd.raw_result` v1을 반환합니다. 여기에는 일반 스키마 v7 `healthmd.health_data` 날짜와 정규 소스 아카이브가 포함됩니다. 저장된 iPhone 설정을 변경하지 않고 일시적으로 무손실 세부 정보를 요청합니다. CLI는 결과를 노출하기 전에 정확한 날짜, 프로필, 스키마, 아카이브, 매니페스트, 다이제스트 체인, 최종 본문 다이제스트 및 완료 상태를 검증합니다.

complete-empty 날짜는 성공입니다. 요청한 데이터가 누락, 부분, 실패, 취소, 미지원 또는 건너뜀 상태면 `partial_success`와 0이 아닌 종료 코드가 발생합니다. 이를 허용하려면 `--allow-partial`을 명시해야 합니다.

## 정규 추출

직접 추출은 동일한 영속 원시 전송을 사용하지만 전송 래퍼 대신 선택된 소스 형태 데이터를 반환합니다.

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

측정 항목, 카테고리, 소스 및 세부 정보 선택은 HealthKit 읽기 전에 iPhone에 전달됩니다. 객체 선택자, JSON Pointer, JSONL 및 수신 확인은 [정규 추출](/ko/docs/cli-extract/)을 참조하세요.

## 프로덕션 생성 파일

직접 파일 모드는 iPhone에 Health.md의 프로덕션 내보내기 도구를 실행하도록 요청한 뒤 생성된 파일을 명시적 컴퓨터 대상으로 전송합니다.

```bash
mkdir -p "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

대상은 이미 존재해야 하고 절대 경로여야 하며 심볼릭 링크를 통해 해석되어서는 안 됩니다. 직접 모드는 추측하거나 Mac 앱 북마크를 사용하지 않습니다. `--output`은 원시 또는 추출 출력용이고 `--destination`은 생성 파일용입니다.

기본적으로 요청은 저장된 형식, Health 하위 폴더, 파일 이름, 템플릿, 쓰기 모드, 일일 노트 주입 및 일일 노트만 옵션을 유지합니다. 해당 작업에서는 롤업과 요약 전용 모드를 억제합니다. 반복 가능한 `--metric` 또는 `--category` 옵션과 `--detail`은 작업의 측정 항목 및 세부 정보 범위만 대체합니다. `--use-iphone-settings`는 저장된 모든 설정을 반영하며 선택자와 함께 사용할 수 없습니다.

iPhone은 JSON, CSV, Markdown, ZIP, 데이터 사전, 롤업, 개별 레코드, 일별 메모 및 제공자 사이드카를 준비할 수 있습니다. CLI는 커밋 전에 각 상대 경로, 바이트 수, 다이제스트, 파일 매니페스트, 대상 식별 정보 및 요청 지문을 검증합니다. 경로 순회, 심볼릭 링크 상위 경로, 루트 변경, 경로 충돌 및 다이제스트 변경을 거부합니다. 덮어쓰기는 원자적으로 수행됩니다. 추가 및 Markdown 병합은 재실행 시 콘텐츠가 중복되지 않도록 저장된 계획을 사용합니다.

생성 파일 대상은 macOS 및 Linux에서 작동합니다. 프로토콜 v1은 Windows에서 이를 거부합니다. Windows 직접 사용자는 원시 내보내기 및 추출을 사용할 수 있습니다.

## 포그라운드 및 백그라운드 동작

페어링 및 새 작업에는 iPhone 앱이 포그라운드에 있어야 합니다. Direct CLI 액세스는 iOS를 헤드리스 내보내기 서버로 바꾸지 않으며 필요할 때 앱을 깨울 수도 없습니다.

내보내기가 이미 연결된 상태에서 앱이 백그라운드로 이동하면 Health.md는 제한된 iOS 백그라운드 실행 시간을 요청합니다. 해당 시간 안에 내보내기가 끝날 수 있습니다. iOS가 시간을 만료시키면 연결이 닫히고 영속 작업이 일시 중지됩니다. Health.md를 다시 열고 동일한 작업을 재개하세요.

iPhone은 직접 작업 중 전역 활동 배너를 표시합니다. 건강 값을 표시하지 않고 캡처 및 전송 단계, 완료된 날짜, 바이트 진행 상황, 일시 중지 또는 완료 상태를 포함합니다.

## 영속 재개 및 취소

직접 작업은 생성 7일 후 만료됩니다. 제한 시간, Ctrl-C, 프로세스 종료, 연결 해제 및 백그라운드 시간 만료로 취소되지 않습니다.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

재개는 원래 날짜, 설정, 대상, 요청 지문, 기기 및 파티션 경계를 유지합니다. 재개 중 파일 작업을 다른 대상으로 지정할 수 없습니다.

취소는 영속 요청을 기록하지만 iPhone이 확인해야만 최종 상태가 됩니다. iPhone을 사용할 수 없으면 상태는 `cancellation_pending`으로 유지됩니다. 동일한 iPhone을 다시 열고 취소를 재시도하세요.

## 보안 모델

- 페어링은 임시 Curve25519 키 합의와 6자리 코드에 연결된 트랜스크립트 증명을 사용합니다.
- 재연결은 저장된 임의 비밀과 두 설치 식별 정보를 증명합니다.
- 연결할 때마다 새 키와 nonce를 파생합니다.
- 메시지와 바이너리 프레임은 단조 증가 시퀀스 확인과 ChaCha20-Poly1305를 사용합니다.
- 파티션은 SHA-256 매니페스트와 연결된 다이제스트 경계를 사용합니다.
- iPhone 신뢰는 키체인에 저장됩니다.
- 이식 가능한 신뢰는 키체인, Secret Service 또는 Windows Credential Manager를 사용하며 일반 텍스트로 대체되지 않습니다.
- 스풀 및 저널은 비공개 애플리케이션 저장소를 사용하고 플랫폼이 지원하는 경우 백업에서 제외됩니다.

수동 IP는 로컬 네트워크 또는 Tailscale에서도 암호화됩니다. Tailscale도 네트워크 경로를 보호하지만 Health.md 애플리케이션 인증을 대체하지는 않습니다.

## 일반적인 오류

| 오류 | 조치 |
|---|---|
| `direct_not_paired` | 이 CLI 설치를 iPhone과 페어링하세요. |
| `direct_device_selection_required` | 원하는 신뢰 기기를 `--device`로 전달하세요. |
| `direct_trust_invalid` | 진단을 보존하세요. 복구가 불가능할 때만 신뢰를 초기화하세요. |
| `direct_iphone_unavailable` | 앱의 포그라운드 상태, 액세스 토글, 주소, 포트, 권한 및 LAN 또는 Tailscale 연결을 확인하세요. |
| `direct_export_paused` | 작업을 확인하고 iPhone을 다시 연 뒤 재개하세요. |
| `direct_cancellation_pending` | 페어링된 iPhone을 다시 열고 취소를 재시도하세요. |
| `transport_unsupported` | 이식 가능한 클라이언트에서는 수동 IP 또는 Tailscale을 사용하세요. |
| `backend_unsupported` | 쿼리, 증거, doctor, 측정 항목 또는 MCP에는 Mac 앱 백엔드를 사용하세요. |
| `invalid_direct_raw_response` | 출력을 사용하지 마세요. 검증 진단을 보존하세요. |
| `invalid_direct_file_receipt` | 파일을 수동으로 복구하지 마세요. 작업을 확인하고 재개하세요. |
| `job_expired` | 7일 상태 수명이 끝났습니다. 새 작업을 시작하기 전에 확인하세요. |

## 관련 문서

<div class="related">
  <a href="/ko/docs/cli/"><span>개요</span>Health.md CLI: 번들 도우미를 설치하고 올바른 백엔드를 선택합니다.</a>
  <a href="/ko/docs/cli-extract/"><span>데이터</span>정규 추출: 소스 형태의 Health.md 데이터를 선택하고 출력합니다.</a>
  <a href="/ko/docs/cli-jobs/"><span>안정성</span>영속 작업 및 자동화: 재개, 취소, 부분 결과 및 스크립팅.</a>
  <a href="/ko/docs/reference/connected-mac-iphone-protocol/"><span>프로토콜</span>연결된 Mac 및 iPhone 참조: 기능, 제한된 전송 및 결과 상태.</a>
</div>
