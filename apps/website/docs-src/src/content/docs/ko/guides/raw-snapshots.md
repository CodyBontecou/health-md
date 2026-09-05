---
title: 원시 API 스냅샷
description: Health Connect 레코드와 Fitbit, Oura, WHOOP, Withings 공급자 응답을 유형별 매니페스트와 체크섬이 포함된 변경 불가능하고 버전 관리되는 JSON 또는 NDJSON 스냅샷으로 내보냅니다.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · 아카이브급 내보내기</p>
  <p>Raw API Snapshot은 마이그레이션 및 아카이브 워크플로를 위한 Health.md for Android의 별도 내보내기 제품입니다. 선택한 범위마다 네이티브 레코드를 보존하는 변경 불가능하고 버전 관리되는 JSON 또는 NDJSON 아티팩트 하나를 생성합니다.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Google Play에서 다운로드</a>
    <a class="docs-button-secondary" href="/ko/docs/android/">Android 앱 가이드</a>
  </div>
</div>

## 원시 스냅샷이란

호환성 내보내기는 Health Connect 레코드를 읽기 쉬운 일일 `HealthData` 요약으로 변환합니다. 원시 스냅샷은 이 변환을 완전히 건너뜁니다:

- **Health Connect 스냅샷**은 고정된 AndroidX API가 노출하는 모든 필드를 보존합니다. 네이티브 식별자와 메타데이터, 나노초 타임스탬프, null 허용 소스 오프셋, 원시 열거형 값, 중첩 샘플, 단계, 경로, 계획된 운동 구조까지 포함합니다.
- **Fitbit, Oura, WHOOP, Withings 스냅샷**은 성공한 공급자 응답의 정확한 바이트를 보존하고 엔드포인트 페이지네이션과 서버 측 집계를 공개합니다. 지원되지 않는 공급자는 정규화되거나 Health Connect 데이터로 조용히 대체되지 않고 보고됩니다.
- 모든 아티팩트는 유형별 상태, 문제, 개수, 체크섬을 담은 **매니페스트**로 끝납니다. 폴더 내보내기에는 추가로 `.sha256` 사이드카 파일이 제공됩니다.

원시 스냅샷은 앱이 고정한 공급자 API 기준으로 API 완전하지만, 공급자 데이터베이스의 트랜잭션 백업이 아닙니다. 접근할 수 없는 레코드, API가 노출하지 않는 원래 단위, 삭제된 레코드, 설치된 SDK에 알려지지 않은 필드는 복구할 수 없습니다.

## 대상 설정 전 미리보기

원시 스냅샷은 대상을 구성하지 않고도 미리 볼 수 있습니다. 미리보기는 공급자 네이티브 읽기 전체를 백업 없는 비공개 저장소에서 수행하고, 메모리에는 제한된 머리·꼬리 텍스트만 유지하며, 임시 아티팩트를 아무것도 업로드하지 않고 삭제합니다.

## 전달 규칙

원시 API 업로드는 호환성 API 내보내기보다 의도적으로 더 엄격합니다:

| 규칙 | 이유 |
|---|---|
| HTTPS 전용 | 스트리밍되는 아티팩트가 평문으로 전송되지 않음 |
| 리디렉션 거부 | 아티팩트와 자격 증명이 다른 오리진으로 재생될 수 없음 |
| 스키마·내보내기·체크섬 헤더 | 수신 엔드포인트가 수락한 내용을 검증할 수 있음 |
| 시도 후 임시 비공개 아티팩트 삭제 | 기기에 사본이 남지 않음 |

## 증분 아카이브

별도로 버전 관리되는 `healthmd.raw-changes` 백엔드는 Health Connect 변경 토큰과 삭제 표시(톰스톤)를 사용하여 향후 증분 아카이브 워크플로를 지원하므로, 전체 스냅샷이 유일한 아카이브 전략일 필요가 없습니다.

## 요구 사항

- Raw API Snapshot 제품이 포함된 Health.md for Android.
- 선택한 레코드 유형의 Health Connect 권한, 또는 공급자 스냅샷을 위한 연결된 Fitbit, Oura, WHOOP, Withings 계정.
- 스냅샷을 업로드하는 경우 HTTPS 엔드포인트. 로컬 폴더 내보내기에는 전송 요구 사항이 없습니다.

## 더 알아보기

- [원시 스냅샷 v1 계약](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-snapshot-v1.md)
- [원시 레코드 v1 계약](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-record-v1.md)
- [원시 변경 v1 계약](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/export-contract/raw-changes-v1.md)
