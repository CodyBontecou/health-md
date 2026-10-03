---
title: "Health.md 문제 해결"
description: "빈 내보내기, 누락된 수면, 연결되지 않는 전화, 일정, 폴더, 부분 결과, 시간 초과를 진단합니다."
---

기기 1대, 하루, 한 범주, 한 대상부터 시작합니다. 건강 데이터, 경로, 임상 문서, 토큰, 페어링 코드, 비공개 경로를 이슈에 올리지 마세요.

## 빈 데이터

Apple Health 또는 Health Connect에서 값을 확인하고 권한을 검토한 뒤 하루·한 범주를 내보냅니다. `complete_empty`, 권한 없음, 미지원, 건너뜀, 부분, 실패를 구분하세요. 누락은 0이 아닙니다.

## 오늘에 지난밤 수면이 없음

수면은 밤이 시작된 날에 속합니다. 화요일 아침에는 **어제** 또는 월요일과 화요일을 내보냅니다. [수면 날짜](/ko/docs/sleep-date-attribution/)를 참고하세요.

## 파일과 일정

vault, 폴더 권한, 하위 폴더, 템플릿, 프로필을 확인합니다. iOS 백그라운드와 WorkManager 시간은 목표이며 보장이 아닙니다. 잠금을 풀고 복구를 사용하세요.

## CLI 시간 초과

시간 초과는 승인된 작업을 취소하지 않습니다.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

완전성을 주장하기 전에 상태, 누락 날짜, 범위, `next_cursor`, 버전, 제한을 확인하세요. `--allow-partial`은 종료 정책만 바꿉니다.

<div class="related"><a href="/ko/docs/cli-jobs/"><span>작업</span>재개 및 취소.</a><a href="/ko/docs/release-status/"><span>버전</span>호환성.</a></div>
