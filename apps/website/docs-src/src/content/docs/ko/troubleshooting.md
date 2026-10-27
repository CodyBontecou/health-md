---
title: "Apple Health 내보내기에 데이터가 없나요? 문제 해결"
description: "Apple Health·Health Connect의 빈 내보내기, 누락된 수면, CSV 상세도, 파일 저장 오류와 일정 지연을 확인 가능한 하루로 점검합니다."
---

Apple Health 또는 Health Connect 내보내기에 데이터가 빠졌다면 먼저 **읽기 문제**와 **파일 저장 문제**를 구분하세요. 누락된 데이터는 측정값 0을 뜻하지 않습니다.

## 확인할 수 있는 하루부터 시작하기

1. Apple Health 또는 Health Connect에서 기록된 값과 날짜를 확인하세요. 시계나 원본 앱의 동기화가 끝날 때까지 기다리세요.
2. Health.md에서 활성 프로필, 지표, 날짜 범위, 형식과 대상을 확인하세요. 완료된 하루의 지원 지표 하나로 시작하세요.
3. 휴대폰 잠금을 풀고 Health.md를 열어, 가능하면 미리보기를 확인하세요. 그런 다음 내보내고 실제 결과와 대상을 확인하세요. 미리보기만으로 파일 저장을 확인할 수는 없습니다.

[iPhone 첫 내보내기](/ko/docs/iphone-first-export/) 또는 [Android 설정](/ko/docs/android/)을 참고하세요.

## 원본에는 데이터가 있지만 내보내기는 비어 있음

iPhone에서는 Apple Health에서 Health.md에 허용한 범주를 확인하세요. **HealthKit은 읽기 권한이 거부되었는지 앱에 알려주지 않습니다**. 빈 결과만으로 접근 제한과 일치하는 기록이 없는 상태를 구분할 수 없습니다. 권한 요청 성공도 모든 읽기 범주의 허용을 뜻하지 않습니다. [Apple 권한 문서](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)를 참고하세요.

Android에서는 원본 앱이 실제로 Health Connect에 기록을 썼는지, Health.md가 해당 지원 유형을 읽을 수 있는지 확인하세요. 다른 앱 안에만 보이는 데이터는 내보낼 수 없을 수 있습니다. [Google 점검 안내](https://support.google.com/android/answer/13770384)를 참고하세요.

동기화나 권한 변경 후 지표와 날짜를 다시 확인하세요. 누락된 값을 0으로 바꾸지 마세요.

구조화된 결과가 `complete_empty`라면 미지원, 부분적, 건너뜀, 실패 결과와 구분하세요. 측정값 0을 입증하거나 읽기 권한 결정을 알려주는 상태가 아닙니다.

## 오늘에 지난밤 수면이 없음

Health.md는 Apple과 Android 모두 수면을 **시작한 날**에 배정합니다. 화요일 아침에는 **어제**인 월요일, 또는 월요일과 화요일을 내보내세요. 원본 동기화가 늦으면 시작일을 다시 내보내세요. [수면 날짜](/ko/docs/sleep-date-attribution/)를 참고하세요.

## 미리보기에는 데이터가 있지만 폴더는 비어 있음

iPhone에서는 활성 프로필 대상이 로컬 폴더, Connected Mac 또는 API Endpoint인지 확인하세요. 파일은 폴더, 하위 폴더, 파일명과 작성·건너뜀·실패 결과를 확인하세요. 건너뛴 파일은 선택한 쓰기 동작 때문일 수 있습니다. 사용할 수 없는 폴더를 다시 선택하고 파일 공급자를 확인한 뒤 재시도하세요. [폴더와 보관함](/ko/docs/folder-vault/) 및 [프로필](/ko/docs/export-profiles/)을 참고하세요.

## CSV에 예상한 측정 기록 대신 합계만 있음

iPhone의 Summary와 Detailed Time-Series는 상세도가 다릅니다. 기간을 늘리기 전에 Data Detail과 지표를 확인하세요. 메타데이터는 건강 측정값이 아닙니다. 단위를 유지하고 일별 합계와 원본 기록을 구분하세요. Lossless Health Records에는 별도의 수집 상태가 있으며 요약만으로 완전한 수집을 입증할 수 없습니다. [형식과 범위 참조](/ko/docs/reference/export-formats/)를 참고하세요.

## 예약한 내보내기가 도착하지 않음

iOS 백그라운드 작업과 Android WorkManager의 시간은 목표이며 전달을 보장하지 않습니다. 잠금을 풀고 Health.md를 연 뒤, 새 실행 전에 기록과 대기 중 복구를 확인하세요. 알림은 저장 성공의 증거가 아닙니다. [iPhone 일정과 복구](/ko/docs/scheduling/) 또는 [Android 자동화](/ko/docs/android/)를 참고하세요.

## CLI 시간 초과

시간 초과는 승인된 작업을 취소하지 않습니다.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

완전성을 주장하기 전에 상태, 누락 날짜, 범위, `next_cursor`, 버전, 제한을 확인하세요. `--allow-partial`은 종료 정책만 바꿉니다.

## 건강 기록을 공유하지 않고 도움 요청하기

앱·OS 버전, 플랫폼, 형식과 함께 빈 데이터, 건너뛴 출력, 쓰기 실패 중 어떤 문제인지 알려 주세요. 공유 전 화면과 로그의 개인정보를 가리세요. 건강값, 이동 경로, 임상 문서, 토큰, 페어링 코드, 비공개 경로를 공개하지 마세요.

<div class="related"><a href="/ko/docs/cli-jobs/"><span>작업</span>재개 및 취소.</a><a href="/ko/docs/release-status/"><span>버전</span>호환성.</a></div>
