---
title: "직접 휴대전화 CLI"
description: "수동 IP 또는 Tailscale을 통해 healthmd를 iPhone 또는 Android 휴대전화와 페어링한 뒤 Mac용 Health.md를 실행하지 않고 내보냅니다."
---

직접 백엔드는 명령을 Mac용 Health.md를 통해 라우팅하지 않고 `healthmd`를 iPhone 또는 Android에서 열린 Health.md 앱에 연결합니다. 휴대전화는 플랫폼 건강 저장소 — iPhone에서는 HealthKit, Android에서는 Health Connect — 를 읽고 보호된 저장소에 결과를 준비한 뒤 검증된 파티션을 CLI로 전송합니다.

```text
healthmd on the computer
  <-> authenticated encrypted Manual IP, Tailscale, or supported Nearby channel
Health.md on iPhone or Android -> HealthKit / Health Connect -> protected bounded spool
  -> raw snapshots, production-generated files, or (iPhone) canonical and typed query data
```

<div class="availability preview">
<strong>미리보기 · 이식 가능한 직접 CLI</strong>
<p>번들 Swift 직접 백엔드는 macOS에서 사용할 수 있으며 iPhone과 페어링합니다. 애플리케이션 프로토콜 v2를 사용하는 Android는 공개 패키지로 제공되는 크로스 플랫폼 Rust 미리보기의 일부입니다. 현재 iOS와 Android는 새로운 이식형 페어링에 동일한 선택자 3과 공통 QR을 사용합니다. 두 휴대전화 플랫폼에서 기본 실기기 연결은 확인되었지만 정확한 빌드의 전체 출시 매트릭스는 아직 완료되지 않았으므로, 이 워크플로는 계속 명시적으로 미검증 상태입니다.</p>
</div>

## 0.1.0-alpha.6 모바일 호환성

이 독립 실행형 표는 명시적으로 검증되지 않은 미리보기에 적용되는 호환성 매트릭스입니다. iPhone과 Android의 기본 실기기 연결은 확인되었지만, 전체 검증 매트릭스를 완료하고 증거를 보존한 공개 CLI/모바일 조합은 아직 없습니다.

| 모바일 소스 | 프로토콜 | 정확한 태그-SHA 대응 버전 / 미검증 호환성 하한 | 이식 가능한 Rust 작업 | 공개 상태 |
|---|---|---|---|---|
| 내보내기 지원 iPhone | 현재 선택기 3(기존 1) / 애플리케이션 v1 | iOS 3.3.0(빌드 202609032317) / iOS 3.0.3 | 상태, 원시, 추출, 파일, 재개, 취소 | 연결 확인됨, 전체 검증 대기 |
| 쿼리 지원 iPhone | 현재 선택기 3(기존 1) / 애플리케이션 v1 + 쿼리 v3 | iOS 3.3.0(빌드 202609032317) / iOS 3.0.3 | V1 및 19개 도구 로컬 MCP/쿼리 | 연결 확인됨, 전체 검증 대기 |
| Android | 현재 선택기 3(기존 2) / 애플리케이션 v2 | Android 1.8.2 (`versionCode 31`) / Android 1.5.4 (`versionCode 25`) | 상태, 제공자 고유 원시, 파일, 재개, 취소 | 연결 확인됨, 전체 검증 대기 |
| Android 타입 지정 MCP 쿼리 | 해당 없음 | 구현되지 않음 | 쿼리 도구에는 iPhone v3 필요 | 지원되지 않음 |

## 직접 모드 지원 기능

- 공유 선택자 3을 통한 일회성 페어링 및 iPhone(애플리케이션 프로토콜 v1) 또는 Android(애플리케이션 프로토콜 v2) 소스와의 신뢰된 재연결
- 로컬 신뢰 기기 확인 및 페어링 해제
- 실시간 휴대전화 준비 상태
- 엄격한 원시 내보내기 — iPhone에서는 스키마 v8 `healthmd.health_data`, Android에서는 제공자 고유의 Health Connect 스냅샷
- 선택적 정규 추출(iPhone 전용)
- 두 휴대전화 플랫폼 모두에서 프로덕션 생성 파일 내보내기
- 영속 로컬 작업 상태 및 재개
- 명시적 취소
- 직접 타입 지정 쿼리, 측정 항목 카탈로그, 증거, MCP Apps UI 및 PNG 대체 출력을 갖춘 동일 실행 파일의 `healthmd mcp serve` stdio 서버(iPhone 전용)

`healthmd` 명령의 직접 백엔드는 Mac 앱의 암호화 컨텍스트 HTTP 라우트를 에뮬레이션하지 않습니다. 따라서 Mac 지향 `doctor`, 쿼리, 증거 및 새로 고침 하위 명령은 백엔드를 전환하지 않고 계속 `backend_unsupported`를 반환합니다. 새로운 직접 iPhone 타입 지정 분석에는 `healthmd mcp serve`를 사용하거나 `healthmd setup codex`를 실행하여 Codex를 자동 구성하고 페어링하세요. `healthmd mcp schema [TOOL]`은 정확한 중첩 MCP 입력 스키마와 예제를 로컬에 출력합니다. 수면에는 `healthmd_sleep_sessions`를 직접 사용하고, 정규 `extract` 출력을 타입 지정 쿼리 API로 취급하지 마세요.

## 요구 사항

- 직접 연결을 지원하는 `healthmd` 바이너리 및 일치하는 Health.md 빌드: iPhone(애플리케이션 프로토콜 v1) 또는 Android(애플리케이션 프로토콜 v2). Android 페어링에는 이식 가능한 Rust 클라이언트가 필요하며 번들 macOS 도우미는 iPhone과만 페어링합니다.
- 페어링 및 새 명령을 위해 휴대전화 포그라운드에 열린 Health.md
- iPhone에서 활성화된 **설정 > Mac 동기화 > Direct CLI 액세스** 또는 Android에서 활성화된 **설정 → Direct CLI**
- 플랫폼 건강 권한(HealthKit 또는 Health Connect), 보호된 데이터, 로컬 네트워크 권한 및 내보내기 할당량 사용 가능
- 수동 IP용으로 연결 가능한 컴퓨터 주소 및 TCP 포트 `17647`. Tailscale 주소도 사용 가능
- 생성 파일 모드를 위한 기존 절대 경로 대상

CLI가 리스너입니다. 휴대전화는 Direct CLI 액세스에 입력한 컴퓨터 주소로 연결합니다.

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

이식 가능한 Rust 클라이언트는 iOS와 Android에서 공통으로 사용하는 QR을 표시하고, 공유 20자리 코드, 후보 컴퓨터 주소, 리스너 포트 및 이전 iOS용 6자리 대체 코드를 stderr에 기록합니다. 번들 macOS 도우미는 기존 6자리 iPhone 코드만 계속 표시합니다. stdout은 최종 JSON 결과를 위해 계속 확보됩니다.

iPhone에서 다음을 수행합니다.

1. **Health.md > 설정 > Mac 동기화 > Direct CLI 액세스**를 열고 액세스를 활성화합니다.
2. **페어링 QR 스캔**을 탭하여 공통 QR을 스캔합니다. 명시적으로 스캔하면 곧바로 페어링이 시작됩니다.
3. 스캔할 수 없으면 **수동 IP**를 선택하고 주소, 포트 및 공유 20자리 코드를 입력합니다. 이전 CLI에서는 6자리 코드도 계속 사용할 수 있습니다.
4. 양쪽 모두 성공을 보고할 때까지 앱을 열어 둡니다.

## Android 휴대전화 페어링

1. Android 휴대전화에서 **Health.md > 설정 → Direct CLI**를 엽니다.
2. **페어링 QR 스캔**을 탭하여 공통 QR을 스캔합니다. 명시적으로 스캔하면 곧바로 페어링이 시작됩니다.
3. 카메라 또는 권한이 없으면 주소, 포트 및 동일한 공유 20자리 코드를 수동으로 입력합니다.
4. 앱을 열어 둡니다. Android는 활성 직접 세션을 위해 사용자가 시작한 표시되는 데이터 동기화 포그라운드 서비스를 실행합니다.

일회성 코드는 네트워크로 전송되거나 저장되지 않습니다. 페어링 후 재연결 신뢰는 Keychain 또는 Android Keystore로 보호됩니다.

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

이 명령은 로컬 신뢰를 읽거나 수정하며 휴대전화에 연결하지 않습니다. iPhone에서는 **페어링된 CLI 지우기**를 사용하여 상대편을 제거하고, Android에서는 **설정 → Direct CLI**에서 페어링을 제거하세요.

둘 이상의 휴대전화가 신뢰된 경우 원하는 설치를 명시적으로 선택하세요.

```bash
healthmd --backend direct --device DEVICE_UUID status
```

로컬 신뢰가 손상되었거나 교체된 설치에 속할 때만 `healthmd direct reset-trust --confirm`을 사용하세요. 모든 로컬 직접 페어링을 제거합니다. 다시 시작하기 전에 휴대전화에서도 해당 페어링을 지우세요.

## 실시간 준비 상태 확인

```bash
healthmd --backend direct --transport manual-ip status
```

직접 상태 응답은 건강 값 없이 연결 및 안전 상태를 보고합니다. 이식 가능한 클라이언트는 소스를 `source` 아래에 보고하며 `platform`은 `ios` 또는 `android`입니다. 번들 도우미는 아래의 `iphone` 필드를 노출합니다. 작업 시작 전 다음 필드를 확인하세요(iPhone 소스 표시).

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

Android 소스는 iPhone 트리거 플래그 대신 `platform: "android"`와 함께 `app_active`, `protected_data_available`, `export_in_progress` 및 사용 가능한 원시 제품을 보고합니다.

## 엄격한 원시 내보내기(iPhone)

범위 선택자 하나를 선택하세요.

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct export --last 7 --raw --output week.json
healthmd --backend direct export \
  --from 2026-07-01 --to 2026-07-07 --raw --output range.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

검증된 JSON을 stdout으로 스트리밍하려면 `--output`을 생략하세요. 민감하거나 큰 응답에는 출력 파일이 더 안전합니다.

iPhone 엄격한 원시는 `healthmd.raw_result` v1을 반환합니다. 여기에는 일반 스키마 v8 `healthmd.health_data` 날짜와 정규 소스 아카이브가 포함됩니다. 저장된 iPhone 설정을 변경하지 않고 일시적으로 무손실 세부 정보를 요청합니다. CLI는 결과를 노출하기 전에 정확한 날짜, 프로필, 스키마, 아카이브, 매니페스트, 다이제스트 체인, 최종 본문 다이제스트 및 완료 상태를 검증합니다.

complete-empty 날짜는 성공입니다. 요청한 데이터가 누락, 부분, 실패, 취소, 미지원 또는 건너뜀 상태면 `partial_success`와 0이 아닌 종료 코드가 발생합니다. 이를 허용하려면 `--allow-partial`을 명시해야 합니다.

## 제공자 고유 원시 내보내기(Android)

이식 가능한 Rust 클라이언트는 기본적으로 직접 모드이므로 Android 원시 명령은 `--backend` 플래그를 생략합니다.

```bash
healthmd export --last 7 --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson
```

`--provider`는 하나의 명시적 제공자를 지정하며 기본값은 `health_connect`입니다. `--raw-format`의 기본값은 대용량 스냅샷에 권장되는 형태인 NDJSON입니다. 메모리 내 JSON 검증은 64 MiB로 제한됩니다. 측정 항목 선택은 `--metric`과 `--all-metrics`를 지원하지만 정규 또는 생성 파일 선택자는 지원하지 않습니다. 해당 기능은 iPhone에만 남아 있습니다.

Android 원시 스냅샷은 Health Connect 제공자 고유 계약을 유지합니다. HealthKit 형태의 `healthmd.health_data` 날짜로 변환되지 않으며, 관련되어 있지만 서로 다른 통계는 고유한 정체성을 유지합니다.

## 정규 추출

직접 추출은 동일한 영속 원시 전송을 사용하지만 전송 래퍼 대신 선택된 소스 형태 데이터를 반환합니다. 이 기능은 iPhone 전용입니다.

```bash
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json

healthmd --backend direct extract \
  --metric workouts --last 14 --object records \
  --detail lossless --output workout-records.json
```

측정 항목, 카테고리, 소스 및 세부 정보 선택은 HealthKit 읽기 전에 iPhone에 전달됩니다. 객체 선택자, JSON Pointer, JSONL 및 수신 확인은 [정규 추출](/ko/docs/cli-extract/)을 참조하세요.

휴대전화 앱이 포그라운드에 있는 동안 신뢰된 직접 세션은 일시적인 연결 해제 후 제한된 횟수와 지연으로 자동 재연결할 수 있습니다. 백그라운드 앱을 깨우거나 접근을 보장하지 않습니다. 앱이 포그라운드가 아니면 Health.md를 다시 연 뒤 재개하세요.

## 프로덕션 생성 파일

직접 파일 모드는 휴대전화에 Health.md의 프로덕션 내보내기 도구를 실행하도록 요청한 뒤 생성된 파일을 명시적 컴퓨터 대상으로 전송합니다.

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

생성 파일 대상은 iPhone 프로토콜 v1과 Android 프로토콜 v2 모두 모든 CLI 운영 체제 — macOS, Linux 및 Windows — 에서 작동합니다. Android는 생성 작업당 파일 수를 4,096개로 제한합니다.

Android 프로토콜 v2 파일 작업은 기기에 저장된 선택 또는 `--profile PROFILE_ID`에서 출력 설정을 가져오며 CLI 측정 항목, 카테고리 및 세부 정보 선택자는 거부됩니다. 두 휴대전화 플랫폼 모두에서 `--profile`은 고정된 출력 설정을 확인하고, 필수 `--destination`은 계속 컴퓨터의 명시적 폴더를 지정합니다.
안정 ID와 안전한 프로필 동작은 [내보내기 프로필](/ko/docs/export-profiles/).

## 포그라운드 및 백그라운드 동작

페어링 및 새 작업에는 휴대전화 앱이 포그라운드에 있어야 합니다. Direct CLI 액세스는 휴대전화를 헤드리스 내보내기 서버로 바꾸지 않으며 필요할 때 앱을 깨울 수도 없습니다.

iPhone에서는 내보내기가 이미 연결된 상태에서 앱이 백그라운드로 이동하면 Health.md가 제한된 iOS 백그라운드 실행 시간을 요청합니다. 해당 시간 안에 내보내기가 끝날 수 있습니다. iOS가 시간을 만료시키면 연결이 닫히고 영속 작업이 일시 중지됩니다. Health.md를 다시 열고 동일한 작업을 재개하세요.

Android에서는 활성 직접 세션이 사용자가 시작한 표시되는 데이터 동기화 포그라운드 서비스를 실행합니다. 페어링 및 새 작업을 위해 앱을 포그라운드에 유지하세요.

iPhone에서는 직접 작업 중 전역 활동 배너가 캡처 및 전송 단계, 완료된 날짜, 바이트 진행 상황, 일시 중지 또는 완료 상태를 건강 값 없이 포함합니다.

휴대전화 앱이 포그라운드에 있는 동안 신뢰된 직접 세션은 일시적인 연결 해제 후 자동으로 다시 연결할 수 있습니다. 재시도 지연은 짧은 최대값까지 점차 늘어납니다. 이 동작은 백그라운드 앱을 깨우거나 접근을 보장하지 않습니다. 앱이 더 이상 포그라운드에 없다면 재개하기 전에 Health.md를 다시 여세요.

120초로 제한된 대기 창은 사용자가 휴대폰 잠금을 해제하고 Health.md를 여는 동안 동일한 요청을 유지합니다. `--wake-timeout SECONDS`로 조정하며 `0`은 비활성화합니다. MCP는 `HEALTHMD_WAKE_TIMEOUT`을 사용합니다. 배포된 alpha.6 바이너리는 대기만 수행합니다. 이후 공식 빌드에서는 등록된 iPhone에 Health.md의 알림 전용 깨우기 서비스를 통해 최선형 APNs 알림을 한 번 보냅니다. Android와 등록되지 않은 iPhone은 계속 대기만 합니다. 알림은 사용자의 현존을 복원할 수 있지만 HealthKit 읽기를 승인하거나 Worker를 통해 건강 범위를 전송하지 않습니다.

## 영속 재개 및 취소

직접 작업은 생성 7일 후 만료됩니다. 제한 시간, Ctrl-C, 프로세스 종료, 연결 해제 및 백그라운드 시간 만료로 취소되지 않습니다.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct resume JOB_UUID --timeout 300 --output recovered.json
healthmd --backend direct cancel JOB_UUID
```

재개는 원래 날짜, 설정, 대상, 요청 지문, 기기 및 파티션 경계를 유지합니다. 재개 중 파일 작업을 다른 대상으로 지정할 수 없습니다.

취소는 영속 요청을 기록하지만 페어링된 휴대전화가 확인해야만 최종 상태가 됩니다. 휴대전화를 사용할 수 없으면 상태는 `cancellation_pending`으로 유지됩니다. 동일한 휴대전화를 다시 열고 취소를 재시도하세요.

## 보안 모델

- 현재 이식형 페어링은 임시 키 합의와 iOS/Android 공용 고엔트로피 20자리(~66비트) 코드에 연결된 선택자 3 트랜스크립트 증명을 사용합니다. 기존 Apple 선택자 1 및 Android 선택자 2 흐름은 바이트 단위 호환성을 유지합니다.
- QR 전달은 정규 비공개 LAN/Tailscale 주소에 대해 명시적인 앱 내 스캐너에서만 허용됩니다. 외부 사용자 지정 URL 열기로는 페어링을 승인할 수 없습니다.
- 재연결은 저장된 임의 비밀과 두 설치 식별 정보를 증명합니다.
- 연결할 때마다 새 키와 nonce를 파생합니다.
- 메시지와 바이너리 프레임은 단조 증가 시퀀스 확인과 ChaCha20-Poly1305를 사용합니다.
- 파티션은 SHA-256 매니페스트와 연결된 다이제스트 경계를 사용합니다.
- iPhone 신뢰는 키체인에 저장되며 Android 재연결 신뢰는 Keystore에 기반합니다.
- 이식 가능한 신뢰는 키체인, Secret Service 또는 Windows Credential Manager를 사용하며 일반 텍스트로 대체되지 않습니다.
- 스풀 및 저널은 비공개 애플리케이션 저장소를 사용하고 플랫폼이 지원하는 경우 백업에서 제외됩니다.

수동 IP는 로컬 네트워크 또는 Tailscale에서도 암호화됩니다. Tailscale도 네트워크 경로를 보호하지만 Health.md 애플리케이션 인증을 대체하지는 않습니다.

## 일반적인 오류

| 오류 | 조치 |
|---|---|
| `direct_not_paired` | 이 CLI 설치를 사용할 모바일 소스와 페어링하세요. |
| `direct_device_selection_required` | 원하는 신뢰 기기를 `--device`로 전달하세요. |
| `direct_trust_invalid` | 진단을 보존하세요. 복구가 불가능할 때만 신뢰를 초기화하세요. |
| `direct_iphone_unavailable` | 앱의 포그라운드 상태, 액세스 토글, 주소, 포트, 권한 및 LAN 또는 Tailscale 연결을 확인하세요. |
| `direct_export_paused` | 작업을 확인하고 페어링된 휴대전화를 다시 연 뒤 재개하세요. |
| `direct_cancellation_pending` | 페어링된 휴대전화를 다시 열고 취소를 재시도하세요. |
| `transport_unsupported` | 이식 가능한 클라이언트에서는 수동 IP 또는 Tailscale을 사용하세요. |
| `backend_unsupported` | 쿼리, 증거, doctor, 측정 항목 또는 MCP에는 Mac 앱 백엔드를 사용하세요. |
| `invalid_direct_raw_response` | 출력을 사용하지 마세요. 검증 진단을 보존하세요. |
| `invalid_direct_file_receipt` | 파일을 수동으로 복구하지 마세요. 작업을 확인하고 재개하세요. |
| `job_expired` | 7일 상태 수명이 끝났습니다. 새 작업을 시작하기 전에 확인하세요. |

## 관련 문서

<div class="related">
  <a href="/ko/docs/cli/"><span>개요</span>Health.md CLI: 번들 도우미를 설치하고 올바른 백엔드를 선택합니다.</a>
  <a href="/ko/docs/android/"><span>Android</span>Android용 Health.md: Health Connect 소스, 폴더 대상 및 기기 내 자동화.</a>
  <a href="/ko/docs/cli-extract/"><span>데이터</span>정규 추출: 소스 형태의 Health.md 데이터를 선택하고 출력합니다(iPhone).</a>
  <a href="/ko/docs/cli-jobs/"><span>안정성</span>영속 작업 및 자동화: 재개, 취소, 부분 결과 및 스크립팅.</a>
  <a href="/ko/docs/reference/connected-mac-iphone-protocol/"><span>프로토콜</span>연결된 Mac 및 iPhone 참조: 기능, 제한된 전송 및 결과 상태.</a>
</div>
