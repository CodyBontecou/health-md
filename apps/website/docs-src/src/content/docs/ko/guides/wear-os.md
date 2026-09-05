---
title: Wear OS 컴패니언
description: Health.md for Wear OS는 시계에 활동 및 회복 타일과 10가지 건강 컴플리케이션을 추가하며, 전화기는 계속 Health Connect의 권위로 남습니다.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.md는 전화기 앱과 동일한 Google Play 목록 아래에서 Wear OS 컴패니언을 제공합니다. 전화기가 유일한 Health Connect 권위로 남는 동안, 시계에 한눈에 보는 건강 화면을 추가하세요.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Google Play에서 다운로드</a>
    <a class="docs-button-secondary" href="/ko/docs/android/">Android 앱 가이드</a>
  </div>
</div>

## 시계에 표시되는 것

| 화면 | 얻는 것 |
|---|---|
| 일일 활동 타일 | 오늘의 활동 요약을 시계 화면 타일로 표시 |
| 회복 타일 | 오늘의 회복 요약을 시계 화면 타일로 표시 |
| 컴플리케이션(10가지) | 활동, 회복, 걸음, 이동, 운동, 수면, 안정 시 심박수, 평균 심박수, HRV, 혈중 산소를 시계 화면 컴플리케이션으로 표시 |

컴플리케이션은 대부분의 시계 화면에서 화면 편집기로 추가할 수 있고, 타일은 시계의 타일 캐러셀에 나타납니다.

## 작동 방식

- 시계 앱은 전화기 앱과 동일한 Play 목록 및 서명 ID로 배포됩니다.
- 건강 데이터는 Wear OS 데이터 레이어를 통해 전화기에서 시계로 비공개 집계 스냅샷으로 흐릅니다. 시계는 **Health Connect나 Health Services를 직접 감지하지 않으며**, 모든 측정 항목에서 전화기가 권위로 남습니다.
- 시계 화면은 전화기 앱이 푸시한 최신 스냅샷에서 새로 고쳐집니다. 계정도, 클라우드도 없고 건강 데이터가 기기를 벗어나지 않습니다.

## 요구 사항

- Health.md가 설치되고 Wear OS 시계와 페어링된 Android 전화기.
- 보고 싶은 측정 항목의 전화기 Health Connect 데이터.
- 시계의 Play Store 또는 컴패니언 전화기의 Play Store 목록에서 시계에 Health.md 설치.

## 설정

1. 시계에서 Play Store(또는 전화기 Play Store의 시계 섹션)를 열고 Health.md를 설치합니다.
2. 전화기 앱을 한 번 열어 스냅샷이 동기화되도록 합니다.
3. 시계 화면을 길게 누른 뒤 → **맞춤설정** → Health.md 컴플리케이션을 추가하거나, 타일 캐러셀로 스와이프하여 Health.md 타일을 고정합니다.

## 개인정보와 검증

컴패니언은 순수한 비공개 집계 전송 계약을 사용하므로 원시 레코드가 시계로 전송되지 않습니다. 릴리스 품질은 Wear OS 아티팩트가 출시되기 전에 에뮬레이터 스위트와 물리적 페어링 기기의 배터리·OEM QA 증거로 게이트됩니다. 전체 절차는 [Wear OS 구현 체크리스트](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md)를 참고하세요.
