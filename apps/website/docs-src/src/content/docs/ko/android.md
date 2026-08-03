---
title: Android 앱
description: Android용 Health.md를 설정하고, Health Connect 데이터를 Markdown, Obsidian Bases, JSON, CSV로 내보내며, Storage Access Framework 폴더를 선택하고, 내보내기를 예약하고, Tasker 또는 adb로 자동화하세요.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Health Connect에서 비공개 파일로</p>
  <p>Android용 Health.md는 기기 내 Health Connect 데이터를 읽고 Markdown, Obsidian Bases, JSON 또는 CSV 형식으로 사용자가 선택한 폴더에 저장합니다. Health.md 계정도, 건강 데이터 클라우드도, 구독도 필요하지 않습니다.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Google Play에서 다운로드</a>
    <a class="docs-button-secondary" href="/ko/docs/export/">내보내기 문서 읽기</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>선택 가능한 Health Connect 측정 항목</span></div>
<div><strong>4</strong><span>내보내기 형식</span></div>
<div><strong>10</strong><span>무료 수동 내보내기 작업</span></div>
<div><strong>0</strong><span>필요한 Health.md 클라우드 계정</span></div>
</div>

## Android 앱의 기능

Android용 Health.md는 Health Connect를 로컬 우선 건강 일지로 바꿔 줍니다. 관심 있는 측정 항목을 선택하고 결과를 미리 본 다음, 로컬 폴더, Obsidian 보관함, 동기화된 제공자 폴더 또는 쓰기 권한을 부여하는 Android 문서 제공자로 깔끔한 파일을 내보낼 수 있습니다.

<div class="options">
  <div class="option"><strong>Health Connect 데이터 소스</strong><p>Android의 기기 내 Health Connect API를 통해 활동, 수면, 심장, 활력 징후, 신체 측정값, 영양, 운동 및 기타 카테고리의 데이터를 읽습니다.</p></div>
  <div class="option"><strong>Obsidian 네이티브 출력</strong><p>일일 노트, YAML 프론트매터, Obsidian Bases에 적합한 노트, 개별 항목 및 Health.md Obsidian 플러그인과 호환되는 JSON을 작성합니다.</p></div>
  <div class="option"><strong>Android 네이티브 저장소</strong><p>Storage Access Framework를 사용하므로 로컬 저장소, Obsidian, Google Drive, OneDrive, Syncthing 또는 기타 제공자가 노출하는 폴더를 선택할 수 있습니다.</p></div>
</div>

## 요구 사항

- Android 9 / API 28 이상.
- Health Connect를 지원하는 기기 또는 에뮬레이터.
- Health Connect에 데이터를 기록하는 Android 앱, 웨어러블 또는 서비스의 Health Connect 데이터.
- 내보내기 파일에 대한 쓰기 권한을 허용하는 폴더 또는 문서 제공자.

## 첫 내보내기

1. Google Play에서 Health.md를 설치합니다.
2. **Health Connect** 설정을 열고 Health.md에서 내보낼 카테고리에만 권한을 부여합니다.
3. Android 폴더 선택기를 통해 내보내기 대상을 선택합니다.
4. Markdown, Obsidian Bases, JSON, CSV 중 하나 이상을 형식으로 선택합니다.
5. 측정 항목과 날짜 범위를 선택합니다.
6. 결과를 미리 봅니다.
7. 내보내기를 탭하고 폴더 또는 보관함에서 생성된 파일을 확인합니다.

무료 요금제에는 수동 내보내기 작업 10회가 포함되어 있어 무제한 내보내기를 잠금 해제하기 전에 권한, 폴더 접근, 형식 및 Obsidian 워크플로를 테스트할 수 있습니다.

## Android의 대상 위치

Android는 iPhone → Mac 로컬 네트워크 대상을 사용하지 않습니다. 대신 Android의 Storage Access Framework를 사용합니다.

| 대상 위치 | Android 지원 상태 |
|---|---|
| 로컬 기기 폴더 | 폴더 선택기를 통해 지원 |
| Obsidian 보관함 | 보관함 폴더가 Android 선택기에 표시되는 경우 지원 |
| Google Drive, OneDrive, Syncthing, Obsidian Sync 및 유사한 제공자 | 제공자가 쓰기 가능한 폴더를 노출하는 경우 지원 |
| iPhone/Mac 로컬 네트워크 대상 | Apple 플랫폼 전용이며 Android에서는 사용되지 않음 |

제공자가 Android 선택기를 통해 쓰기 가능한 폴더를 노출하지 않으면 Health.md에서 해당 위치에 직접 안전하게 쓸 수 없습니다. 영구 쓰기 권한을 부여하는 제공자 폴더를 선택하거나 로컬로 내보낸 후 원하는 도구로 동기화하세요.

## 형식

Android 앱은 Apple 앱과 동일하게 일반 파일을 지향합니다.

| 형식 | 용도 |
|---|---|
| Markdown | 읽기 쉬운 일일 건강 요약, 템플릿 및 노트 |
| Obsidian Bases | Obsidian 데이터베이스 보기에서 쿼리할 수 있는 프론트매터 중심 노트 |
| JSON | 스크립트, 대시보드, 노트북 및 Health.md Obsidian 플러그인용 구조화된 일일 페이로드 |
| CSV | 스프레드시트 및 분석 워크플로 |

Android JSON 내보내기는 Health.md의 Obsidian 시각화와 호환되도록 설계되었습니다. Markdown 및 Bases 내보내기는 [형식 가이드](/ko/docs/format/)에 설명된 것과 동일한 프론트매터 중심 워크플로를 사용합니다.

## 예약 및 자동화

Android의 알람 및 리마인더 접근 권한을 부여하면 예약된 내보내기에 일회성 정확한 알람을 사용하며, 영속 WorkManager 작업을 대체 수단으로 사용합니다. 정확한 알람 접근 권한이 없으면 WorkManager가 기본 스케줄러가 되므로 선택한 시간은 보장된 실행 시각이 아니라 목표 시간이 됩니다. Health.md는 내보내기 기록을 저장하고, 누락된 예약 날짜를 복구하며, 실패한 실행을 다시 시도할 수 있게 해 줍니다.

Tasker, adb 또는 기타 자동화 도구를 위해 Health.md는 명시적 브로드캐스트 인텐트만 제공합니다. 외부 호출자는 수신기 구성 요소를 직접 지정해야 합니다.

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

자동화에는 현재 내보내기 설정, 선택한 폴더, 형식, 측정 항목 선택, 무료 내보내기 사용량 계산 및 기록이 적용됩니다.

## 건강 데이터 소스

Health Connect가 기본 로컬 내보내기 경로입니다. Android 앱에는 Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar 및 WHOOP 같은 생태계를 위한 건강 데이터 소스 설정 영역도 포함되어 있습니다. 해당 생태계가 Health Connect에 데이터를 기록하면 Health.md는 생성된 Health Connect 기록을 내보낼 수 있습니다. 클라우드 제공자에서 직접 가져오려면 제공자 인증이 필요하며 추가 설정 또는 이용 가능 여부에 제약이 있을 수 있습니다.

Health Connect가 Android의 권장 건강 데이터 계층이므로 Google Fit은 지원 제공자 목록에서 제외됩니다.

## 가격 및 구매 복원

- Android 앱에는 무료 수동 내보내기 작업 10회가 포함됩니다.
- Google Play Billing을 통한 일회성 평생 구매로 무제한 내보내기와 예약 자동화를 잠금 해제할 수 있습니다.
- 구독과 반복 청구는 없습니다.
- 구매 전에 Google Play에 현재 현지 가격이 표시됩니다.
- 구매 복원은 Premium을 구매한 Google 계정을 사용합니다.

## 개인정보 보호 모델

Android용 Health.md는 로컬 우선 방식입니다.

- Health Connect 기록은 Android 기기에서 읽습니다.
- 내보내기 파일은 사용자가 선택한 폴더에 직접 저장됩니다.
- Health.md는 건강 데이터 클라우드 서비스를 운영하지 않습니다.
- 설정과 내보내기 기록은 기기에 유지됩니다.
- 결제는 Google Play에서 처리합니다.
- 제공자 기반 폴더는 해당 제공자의 약관에 따라 동기화됩니다.

가장 엄격한 로컬 설정을 원한다면 로컬 기기 폴더로 수동 내보내기를 실행하고 예약된 내보내기와 제공자 기반 동기화를 비활성화한 상태로 두세요.

## 관련 문서

<div class="related">
  <a href="/ko/docs/export/"><span>내보내기</span>수동 내보내기 절차, 날짜 범위, 미리보기, 기록 및 파일 출력.</a>
  <a href="/ko/docs/metrics/"><span>측정 항목</span>Health.md 전반에서 측정 항목 선택과 카테고리가 작동하는 방식.</a>
  <a href="/ko/docs/format/"><span>형식</span>Markdown, Bases, JSON, CSV, 단위, 파일 이름 및 프론트매터.</a>
  <a href="/ko/docs/visualizations-roadmap/"><span>Obsidian</span>내보낸 JSON과 Markdown으로 Health.md 시각화를 구현하는 방식.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">최종 업데이트: 2026-08-03</p>
