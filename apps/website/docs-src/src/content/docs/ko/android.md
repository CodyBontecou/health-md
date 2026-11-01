---
title: "안드로이드 앱"
description: "Android용 Health.md 설정하세요. Health Connect 데이터를 내보내고, Storage Access Framework 폴더를 선택하고, 내보내기를 예약하고, Tasker 또는 adb를 사용하여 자동화하세요."
---

비공개 파일에
 <div class="docs-hero">
 <p class="docs-eyebrow"> Health Connect Android용 </p>
 <p> Health.md 기기에서 Health Connect 읽고 선택한 폴더에 Markdown , Obsidian 기본, JSON 또는 CSV를 씁니다. 이 폴더 내보내기 워크플로에는 Health.md 계정이 필요하지 않습니다. Google Play 액세스 옵션 및 F-Droid 포함 액세스는 아래에 설명되어 있습니다. </p>
 <div class="docs-actions">
 <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener"> Google Play </a>
 <a class="docs-button-secondary" href="#distribution-status"> F-Droid 게시 상태 </a>
 <a class="docs-button-secondary" href="/ko/docs/export/"> 내보내기 문서 읽기 </a>
 </div>
 <p id="distribution-status"> F-Droid 카탈로그 게시가 보류 중입니다. Google Play 에서 최신 Android 릴리스를 다운로드하세요. </p>
 </div>

<div class="reference-stats">
 <div> <strong> 106 </strong> <span> 선택 가능 Health Connect 메트릭 </span> </div>
 <div> <strong> 4 </strong> <span> 내보내기 형식 </span> </div>
 <div> <strong> 2 </strong> <span> Android 배포 채널 </span> </div>
 <div> <strong> 0 </strong> <span> Health.md 클라우드 계정 필요 </span> </div>
 </div>

## Android 앱의 기능

Android용 Health.md Health Connect 로컬 우선 건강 저널로 바꿔줍니다. 필요한 지표를 선택하고 출력을 미리 봅니다. 그런 다음 파일을 로컬 폴더, Obsidian 볼트, 동기화된 공급자 폴더 또는 쓰기 가능한 Android 문서 공급자로 내보냅니다.

<div class="options">
 <div class="option"> <strong> Health Connect 소스 </strong> <p> Android의 기기 내 Health Connect API를 통해 활동, 수면, 심장, 활력, 신체 측정, 영양, 운동 및 기타 카테고리를 읽습니다. </p> </div>
 <div class="option"> <strong> Obsidian -네이티브 출력 </strong> <p> 일일 메모, YAML/머리말, Obsidian 기본 친화적 메모, 개별 항목 및 Health.md Obsidian 플러그인과 호환되는 JSON을 작성합니다. </p> </div>
 <div class="option"> <strong> Android 기반 저장소 </strong> <p> 저장소 액세스 프레임워크를 사용하여 로컬 저장소, Obsidian , Google Drive, OneDrive, Syncthing 또는 다른 공급자에 의해 노출된 폴더를 선택할 수 있습니다. </p> </div>
 </div>

## 요구사항

- Android 9/API 28 이상.
- Health Connect 지원 장치 또는 에뮬레이터입니다.
- Health Connect Health Connect 에 쓰는 Android 앱, 웨어러블 또는 서비스의 데이터.
- 내보내기에 대한 쓰기 액세스를 허용하는 폴더 또는 문서 제공자입니다.

## 첫 번째 내보내기

1. Google Play 에서 현재 Health.md 릴리스를 설치합니다.
2. 열기 ** Health Connect ** 설정하고 Health.md 내보낼 카테고리만 부여합니다.
3. Android의 폴더 선택기를 통해 내보내기 대상을 선택하세요.
4. 형식을 선택하세요: Markdown , Obsidian 베이스, JSON, CSV 또는 임의의 조합.
5. 측정항목과 날짜 범위를 선택하세요.
6. 출력을 미리 봅니다.
7. 내보내기를 탭하고 폴더나 볼트에 생성된 파일을 확인하세요.

구독이 활성화된 Google Play 전화 릴리스에는 활성 평가판, 구독, 평생 또는 수동 내보내기를 위한 보존된 영구 액세스가 필요합니다. 해당 구독에는 7일 평가판이 포함됩니다. 평생에는 재판이 없습니다. F-Droid 빌드에는 구매 또는 복원 흐름 없이 무제한 액세스가 포함됩니다.

## Android의 목적지

Android는 iPhone → Mac 로컬 네트워크 대상을 사용하지 않습니다. 대신 Android의 저장소 액세스 프레임워크를 사용합니다.

| 목적지 | 안드로이드 상태 |
| --- | --- |
| 로컬 장치 폴더 | 폴더 선택기를 통해 지원됨 |
| Obsidian 금고 | Vault 폴더가 Android의 선택기에 노출된 경우 지원됩니다. |
| Google Drive, OneDrive, Syncthing, Obsidian Sync 및 유사한 공급자 | 공급자가 쓰기 가능한 폴더를 노출하는 경우 지원됩니다. |
| iPhone /Mac 로컬 네트워크 대상 | Apple 플랫폼별; 안드로이드에서는 사용되지 않습니다 |

공급자가 Android 선택기를 통해 쓰기 가능한 폴더를 노출하지 않으면 Health.md 해당 폴더에 안전하게 직접 쓸 수 없습니다. 지속적인 쓰기 액세스 권한을 부여하는 공급자 폴더를 선택하거나 로컬로 내보내고 선호하는 도구와 동기화하세요.

## 형식

Android 앱은 Apple 앱과 동일한 일반 파일 목표를 공유합니다.

| 체재 | 다음 용도로 사용하세요. |
| --- | --- |
| Markdown | 읽을 수 있는 일일 건강 요약, 템플릿 및 메모 |
| Obsidian Bases | Obsidian 데이터베이스 뷰에서 쿼리할 수 있는 머리글 우선 메모 |
| JSON | 스크립트, 대시보드, 노트북 및 Health.md Obsidian 플러그인을 위한 구조화된 일일 페이로드 |
| CSV | 스프레드시트 및 분석 워크플로우 |

Android JSON 내보내기는 Health.md 의 Obsidian 시각화와 호환되도록 설계되었습니다. Markdown 및 Bases 내보내기는 [형식 가이드](/ko/docs/format/)에 설명된 것과 동일한 머리말 중심 작업 흐름을 사용합니다.

## 스케줄링 및 자동화

구독이 활성화된 Google Play 전화 릴리스에서 예약된 내보내기에는 활성 평가판, 구독, 평생 또는 보존된 영구 액세스가 필요합니다. F-Droid 빌드에 포함되어 있습니다. Android의 알람 및 미리 알림 액세스 권한을 부여할 때 내구성이 뛰어난 WorkManager 작업을 백업으로 사용하여 정확한 일회성 알람을 사용합니다. 정확한 알람 액세스가 없으면 WorkManager 이 기본 스케줄러가 되므로 선택한 시간은 확실한 보장이 아니라 목표입니다. Health.md 내보내기 기록을 기록하고, 누락된 예약 날짜를 복구할 수 있으며, 실패한 실행을 다시 시도할 수 있습니다.

Tasker, adb 또는 기타 자동화 도구의 경우 Health.md 명시적 전용 브로드캐스트 인텐트를 노출합니다. 외부 호출자는 수신자 구성 요소를 직접 처리해야 합니다.

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

예:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

자동화는 고정된 대상, 형식, 지표, 회계 및 기록을 포함하여 기본적으로 활성 프로필을 사용합니다. 제공된 `PROFILE` extra는 안정적인 프로필 ID 또는 이름을 선택할 수 있습니다. 현재 설정을 사용하는 대신 알 수 없는 참조가 실패하여 닫혔습니다. 예약된 실행도 해당 프로필에 바인딩되어 있습니다. [프로필 내보내기](/ko/docs/export-profiles/)를 참조하세요.

### 백그라운드 준비 및 예약된 취소

- 무인 내보내기에 대한 백그라운드 Health Connect 읽기를 허용합니다. 그렇지 않으면 Health.md 열어 상태 데이터 읽기를 완료하세요.
- Android가 활성 작업, 포그라운드 서비스 상태, 결과 및 복구 작업을 표시할 수 있도록 알림을 활성화 상태로 유지하세요.
- 정확한 알람 일정을 원하는 경우에만 알람 및 미리 알림을 부여하세요. 이것이 없으면 지속 가능한 WorkManager 작업을 계속 사용할 수 있지만 선택한 시간은 대략적인 것입니다.
- 예약된 실행을 취소하면 해당 시도만 중지됩니다. 완료된 날짜는 완전한 상태로 유지되고, 해결되지 않은 날짜는 다시 시도할 수 있으며, 반복 일정은 활성화된 상태로 유지됩니다.

## 건강 소스

Health Connect 은 두 채널 모두의 로컬 내보내기 경로입니다. Google Play 빌드에는 Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar 및 WHOOP와 같은 생태계를 위한 건강 소스 설정 영역도 포함되어 있습니다. 해당 생태계가 Health Connect 에 쓰는 경우 두 빌드 모두 결과 Health Connect 레코드를 내보낼 수 있습니다. 직접 클라우드 제공자 가져오기 및 OAuth 콜백은 Play 전용입니다. F-Droid 공급자 카탈로그에는 Health Connect 만 포함됩니다.

Health Connect 이 Android에서 선호하는 건강 데이터 레이어이기 때문에 Google Fit은 지원되는 제공자 표면에서 의도적으로 제외되었습니다.

### 정확한 현지 날짜 단계

일일 걸음 수 합계는 정확한 지역별-현지-일 경계를 사용합니다. 집계 전에 Health.md 은 현지 자정에 겹치는 Health Connect 간격을 잘라내고 분할합니다. 따라서 여행 및 일광 절약 시간제 변경으로 인해 잘못된 날짜로 단계가 이동되지 않습니다.

## 배포, 가격, 전환

- ** Google Play :** 구독 지원 전화 릴리스는 개별 주간/연간 구독 및 평생 구독을 제공합니다. 적격한 최초 구독자는 7일 평가판을 받은 후 Google Play 통해 취소할 때까지 표시된 가격으로 자동 갱신됩니다. 체험판 없이 평생 1회 즉시 요금이 청구됩니다. 현지 자유 수출 허용량이 남아 있지 않습니다. 기존 영구 액세스 권한은 유지됩니다. 구매 복원은 구매 Google 계정을 사용합니다. 앱을 삭제하거나 Lifetime을 구매해도 구독이 취소되지는 않습니다. 이전에 출시된 빌드에는 이전 허용량이 표시될 수 있습니다. 현재 릴리스는 전화 전용입니다. Wear OS 컴패니언은 이후 자격 주기로 연기됩니다.
- ** F-Droid :** 무제한 액세스가 포함됩니다. 무료 카운터, 청구 종속성, 페이월, 구매 또는 복원 작업이 없습니다.
- ** F-Droid 범위:** Health Connect 만 해당, Wear OS 통합, 직접 클라우드 제공자 OAuth, Play 검토, 기여 분석 또는 Health.md 온보딩 원격 측정이 없습니다.
- **공유 결과:** 두 채널 모두 동일한 Health Connect 캡처, 내보내기, 스키마, 자동화 작업 및 직접 장치 프로토콜을 사용합니다.
- **전환:** Google Play 및 F-Droid 서로 다른 서명 키를 사용하므로 채널을 변경하려면 먼저 앱을 제거해야 합니다.

채널 스위치는 구매, 설정, 기록, 자격 증명 또는 개인 전송 상태를 마이그레이션하지 않습니다. 내보낸 파일은 선택한 대상에 남아 있습니다.

Google Play 결제 연결이 일시적으로 끊어지면 Play 빌드가 자동으로 다시 연결되고 자격 상태를 새로 고칩니다. 일시적인 서비스 손실로 인해 프리미엄이 영구적으로 제거되지는 않습니다. 연결이 복구된 후에도 계정이 해결되지 않은 경우에만 구매 복원을 사용하세요.

## 개인정보 보호 모델

Android용 Health.md 은 로컬 우선입니다.

- Health Connect 레코드는 Android 기기에서 읽습니다.
- 내보내기는 선택한 폴더에 직접 기록됩니다.
- 코어 폴더 내보내기 및 직접 장치 쿼리는 기본적으로 Health.md 서버 복사본을 생성하지 않습니다.
- 설정 및 내보내기 기록은 기기에 유지됩니다.
- 청구는 Play 빌드에서 Google Play 에 의해 처리됩니다. F-Droid 에는 청구 없이 무제한 액세스가 포함되며 Health.md 원격 분석 코드 또는 원격 분석 ID/상태가 포함되어 있지 않습니다.
- 공급자 지원 폴더는 해당 공급자의 자체 조건에 따라 동기화됩니다.

가장 엄격한 로컬 설정을 원하는 경우 로컬 장치 폴더로 수동 내보내기를 실행하고 예약된 내보내기 및 공급자 지원 동기화를 비활성화된 상태로 둡니다.

별도의 선택형 Health.md Cloud 파일럿은 단일 소유자 전용이며 의도적으로 업로드한 API 내보내기만 보관합니다. 공개 가입은 없으며 기기 자동 동기화도 없습니다. 이 폴더 워크플로는 파일럿에 업로드하지 않습니다. 보관, 삭제, 용량 제한 및 백업이 없어 발생할 수 있는 손실 위험은 [개인정보 처리방침](/privacy-policy.html)을 참고하세요.

## 관련 문서

<div class="related">
 <a href="/ko/docs/export-profiles/"> <span> 프로필 </span> 독립적인 대상, 출력 설정, 일정 및 안정적인 자동화 ID를 저장합니다. </a>
 <a href="/ko/docs/export/"> <span> 내보내기 </span> 수동 내보내기 흐름, 날짜 범위, 미리 보기, 기록 및 파일 출력. </a>
 <a href="/ko/docs/metrics/"> <span> 측정항목 </span> Health.md 에서 측정항목 선택 및 카테고리가 작동하는 방식. </a>
 <a href="/ko/docs/format/"> <span> 형식 </span> Markdown , 베이스, JSON, CSV, 단위, 파일 이름 및 머리말. </a>
 <a href="/ko/docs/visualizations-roadmap/"> <span> Obsidian </span> 내보낸 JSON 및 Markdown 이 Health.md 시각화를 강화하는 방법. </a>
 </div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;"> 최종 업데이트 날짜: 2026-10-04 </p>
