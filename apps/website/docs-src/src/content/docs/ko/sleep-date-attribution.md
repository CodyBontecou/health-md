---
title: "수면 날짜와 일일 노트"
description: "야간 수면이 시작일에 속하는 이유와 아침에 내보낼 범위를 설명합니다."
---

Health.md는 수면 세션을 **시작한 날짜**에 배정합니다. 월요일 23:45부터 화요일 7:30까지 잔 수면은 월요일 요약에 속합니다. Health Connect가 기상일을 표시하더라도 Apple과 Android는 같은 규칙을 사용합니다.

| 목적 | 내보내기 |
|---|---|
| 화요일 아침 지난밤 수면 | **어제**(월요일) |
| 화요일 활동 | **오늘** |
| 둘 다 | 월요일과 화요일 |

읽기 쉬운 일일 요약은 밤 전체를 함께 둡니다. 정규 원본 레코드는 원래 시작·종료 시간을 보존하고 시작일 아카이브에 속하며, Health.md는 인위적으로 둘로 나누지 않습니다. 세션 의미가 필요하면 `healthmd_sleep_sessions`를 사용하세요.

Daily Note Injection과 API Endpoint도 같은 배정을 사용합니다. 원본 동기화가 늦으면 시작일을 다시 내보내세요. 현재 기상일로 재배정하는 설정은 없습니다.

<div class="related"><a href="/ko/docs/scheduling/"><span>자동화</span>아침에 어제를 포함.</a><a href="/ko/docs/troubleshooting/"><span>도움말</span>빈 데이터와 지연 확인.</a></div>
