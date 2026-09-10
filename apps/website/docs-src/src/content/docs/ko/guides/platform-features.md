---
title: 플랫폼별 기능
description: Health.md가 iPhone, iPad, Mac, Android, Wear OS, CLI에서 제공하는 기능 — 공유 기능과 플랫폼 간 정직한 차이.
---

<div class="docs-hero">
  <p class="docs-eyebrow">플랫폼 개요</p>
  <p>Health.md가 iPhone, iPad, Mac, Android, Wear OS, CLI에서 무엇을 하는지 — 플랫폼이 허용하는 곳에서는 공유하고, 다른 곳에서는 정직하게 안내합니다.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone과 Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

**Wear OS 항목은 예정된 기능이며 현재 Google Play 릴리스에는 포함되지 않습니다.**

범례: ✓ 사용 가능 · ◐ 행에 명시된 플랫폼 차이가 있는 사용 가능 · △ 계획 중 또는 QA 중 · ? 가용성을 주장하지 않음 · — 해당 플랫폼에서는 사용 불가.

CLI는 별도의 건강 데이터 플랫폼 열이 아닙니다. CLI 기능은 자동화 행에 나타나며 iPhone 또는 Android 소스의 의미 체계를 유지합니다.

## 설정 및 권한

| 기능 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 건강 데이터 권한(읽을 항목을 정확히 선택) | ✓ Apple Health 유형 | ◐ 페어링된 iPhone / Mac 대상 경유로 읽기 | ✓ Health Connect 카테고리 | — |
| 내보내기 대상 선택 | ✓ Obsidian 보관함, iCloud Drive, 파일 | ✓ 로컬 폴더 | ✓ 모든 Android 폴더 제공자(Drive, OneDrive, Syncthing, Obsidian Sync…) | — |
| 샘플 미리보기가 포함된 온보딩 | ✓ | ✓ | ✓ | — |
| Share My Setup(기기 간 환경설정 이동) | △ QA 중 | △ QA 중 | △ QA 중 | — |

## 읽기 및 내보내기

| 기능 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Markdown, Obsidian Bases, JSON, CSV로 일일 내보내기 | ✓ | ✓(파일이 iPhone에서 도착) | ✓ | — |
| 225개 이상의 Apple Health 측정 항목 / 106개의 Health Connect 측정 항목 | ✓ | ✓ | ✓ | — |
| 쓰기 전 미리보기 | ✓ | ✓ | ✓ | — |
| 독립적인 설정을 가진 저장된 내보내기 프로필 | ✓ iPhone에서 관리. ? iPad 관리는 주장하지 않음 | ? 관리는 주장하지 않음 | ✓ Android에서 관리 | — |
| 주간 / 월간 / 연간 롤업 요약 | ✓ | ✓ | △ 계획됨. 별도로 검토된 Android 스키마 프로필 필요(현행 v4/v5는 변경 없음) | — |
| 내보내기 기록 및 재시도 | ✓ | ✓ | ✓ | — |
| 일정을 비활성화하지 않고 진행 중인 실행을 중지 또는 취소 | ✓ 완료된 날짜는 보존되고, 미해결 날짜는 재시도 가능 | ✓ | ✓ 완료된 날짜는 보존되고, 미해결 날짜는 재시도 가능 | — |
| 1회 실행 ZIP 아카이브 | ✓ | ✓ | — | — |
| 요약 데이터 상세 | ✓ | ✓ | ✓ | — |
| 선택된 측정 항목의 상세 시계열 | ✓ | ✓ | ✓ | — |
| 무손실 건강 기록의 정규 소스 아카이브 | ✓ `healthmd.healthkit_records` | ✓ | — Apple 전용. 대신 원시 API 스냅샷 참조 | — |
| 원시 API 스냅샷 내보내기(변경 불가능한 JSON/NDJSON) | — | — | ✓ Health Connect + Fitbit, Oura, WHOOP, Withings | — |

## 고급 데이터

| 기능 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 개별 항목 추적(운동, 수면 단계, 바이탈) | ✓ | ✓ | ✓ | — |
| 운동 세부 정보(제공 시 전체 그래프 및 경로 포함) | ✓ | ✓ | ✓ | — |
| 기분 / State of Mind 내보내기 | ✓ | ✓ | —(Health Connect에 해당하는 기능 없음) | — |
| 복용량 기록 이벤트 | ✓ | ✓ | —(Health Connect에 해당하는 기능 없음) | — |
| 혈압, 혈당, 산소, 온도 측정값 | ✓ | ✓ | ✓ | — |
| 서드파티 제공자 데이터 | ◐ 내보내기 내 WHOOP 섹션(베타) | ◐ | ✓ 제공자 기본 원시 스냅샷 | — |

일부 데이터는 플랫폼 간에 의도적으로 **동등한 것으로 취급하지 않습니다**. 심박변동도는 Apple에서는 SDNN, Android와 WHOOP에서는 RMSSD이며, Health.md는 이를 섞지 않고 별개의 측정 항목으로 유지합니다. Apple Watch의 손목 온도와 Health Connect의 피부 온도도 마찬가지로 별도로 유지됩니다.

## 자동화 및 통합

| 기능 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 반복 예약 내보내기 | ✓ 알림 + APNs 폴백 | ✓ | ✓ WorkManager(+선택적 정확한 알람), 부팅 후 복구 | — |
| 시스템 자동화 | ✓ 단축어 / Siri / App Intents | — | ✓ Tasker, adb, 명시적 브로드캐스트 인텐트 | — |
| 자체 HTTP(S) API 엔드포인트로 내보내기 전송 | ✓ | — | ✓ 헤더 암호화 저장 포함 | — |
| 독립 실행형 CLI(`healthmd`) 페어링 | ✓ 포그라운드 직접 서비스 | ✓ 번들 + 독립 실행형 | ✓ 20자리 코드 페어링 | — |
| 직접 CLI 요청 웨이크 | ✓ 제한된 대기 + 옵트인 APNs | ✓ CLI 개시자 | ◐ 제한된 대기. FCM은 계획됨 | — |
| AI 에이전트용 MCP 서버 | ◐ Mac을 통해 번들로 제공. 타입 지정 휴대용 직접 MCP는 iPhone 전용 | ✓ `healthmd-mcp` 번들 | — 타입 지정 직접 MCP 미지원 | — |

## 기기와 한눈에 보는 화면

| 기능 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 홈 화면 위젯 | ✓ 요약, 활동 링, 심박 범위, 수면 | — | ✓ 요약, 활동, 심박 범위, 수면(일어선 시간 대신 걸음 수) | — |
| 내보내기 진행 상황 실시간 활동 | ✓ | — | — | — |
| 시계 화면 | ✓ 워치 앱 + 10가지 컴플리케이션 | — | — | △ 1.10.0 예정 |
| Mac을 내보내기 대상으로 사용(암호화된 로컬 전송) | ✓ iPhone이 전송 | ✓ 수신 | — | — |

## 구매 및 개인정보

| 기능 | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| 무료 등급 | ✓ 수동 또는 예약 내보내기 10회 | — | ✓ 수동 내보내기 10회 | — |
| 잠금 해제 | ✓ 일회성 평생 구매(개인 / 가족) | ◐ 동일한 Apple 잠금 해제 | ✓ 일회성 평생 구매, 예약 포함 | — |
| 로컬 우선 프라이버시 | ✓ Health.md 건강 데이터 클라우드 없음 | ✓ | ✓ | △ 예정 |
| 의료진 보고서(진료용 PDF 1부) | ✓ | — | ✓ | — |

Health.md는 건강 데이터 클라우드를 운영하지 않습니다. 건강 데이터는 사용자가 선택한 대상, 암호화된 로컬 컨텍스트, 그리고 범위가 한정된 비공개 전송 상태에만 존재할 수 있습니다. 폴더, Mac, API 엔드포인트, CLI 대상은 모두 명시적으로 구성됩니다. 프로필과 예약은 생성된 기기에 로컬로 남습니다. 각 플랫폼의 워크플로는 [내보내기 프로필](/ko/docs/export-profiles/), [Android 가이드](/ko/docs/android/), [iPhone 내보내기 가이드](/ko/docs/export/)를 참고하세요.
