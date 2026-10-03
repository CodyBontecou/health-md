---
title: "단축어 및 App Intents"
description: "출시된 7개 작업과 개발 소스의 Mac 컨텍스트 2개 작업을 단축어와 Siri에서 사용합니다."
---

<div class="availability preview"><strong>출시된 작업 7개 · 현재 소스 9개</strong><p>Mac 컨텍스트 작업 2개에는 호환되는 iPhone/Mac 빌드가 필요합니다. 정확한 릴리스 노트를 확인하세요.</p></div>

## 작업

- 어제, 지정 날짜, 범위 또는 최근 N일 내보내기
- 건강 요약 또는 마지막 내보내기 상태 가져오기
- 일정 켜기/끄기
- **Refresh Mac Health Context**(개발): 프로필에 연결된 암호화 컨텍스트의 내구성 있는 갱신
- **Get Mac Context Refresh Status**(개발): 상태와 job ID 가져오기

네 내보내기 작업은 선택적 **프로필**을 받습니다. 알 수 없는 이름은 대체 없이 실패합니다. 일반 단축어는 iPhone 폴더에 쓰며 API Endpoint나 Connected Mac으로 조용히 바뀌지 않습니다.

잠긴 상태 실행 허용은 HealthKit 잠금을 해제하지 않습니다. Health.md는 요청을 보류하고 **Health Export Needs Attention**을 표시합니다.

### 아침 자동화

1. 시간 자동화를 만듭니다.
2. **Export Yesterday's Health Data**를 추가합니다.
3. **Get Last Export Status**와 알림을 추가합니다.

어제에는 어젯밤 시작된 수면이 포함됩니다. [수면 날짜](/ko/docs/sleep-date-attribution/)를 참고하세요.

<div class="related"><a href="/ko/docs/export-profiles/"><span>프로필</span>안정적인 ID.</a><a href="/ko/docs/release-status/"><span>호환성</span>버전 확인.</a></div>
