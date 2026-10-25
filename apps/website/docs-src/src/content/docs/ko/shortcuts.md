---
title: "단축어 및 App Intents"
description: "단축어와 Siri에서 Health.md 작업 7개를 사용합니다. Mac 컨텍스트 새로 고침 작업은 제안 단계이며 사용할 수 없습니다."
---

<div class="availability preview"><strong>소스에 등록된 작업 7개</strong><p>Refresh Mac Health Context와 Get Mac Context Refresh Status는 제안 단계이며 구현되지 않았고 개발 버전에서도 사용할 수 없습니다. <a href="https://github.com/CodyBontecou/health-md/issues/173">이슈 #173</a>을 확인하세요. 제공하려면 구현, 검증 및 정확한 Apple 릴리스 노트가 필요합니다.</p></div>

## 작업

- 어제, 지정 날짜, 범위 또는 최근 N일 내보내기
- 건강 요약 또는 마지막 내보내기 상태 가져오기
- 일정 켜기/끄기

### 제안된 Mac 컨텍스트 작업 (사용 불가)

요청된 **Refresh Mac Health Context** 작업은 명시적인 프로필 및 날짜 범위, 인증된 호환 장치, 내구성 있는 컨텍스트 수집을 사용하며 내보내기 파일을 만들거나 파일 내보내기 할당량을 소비하지 않아야 합니다. **Get Mac Context Refresh Status**는 복구 가능한 작업 ID와 함께 대기 중/완료/실패 상태를 보고해야 합니다. 이는 요구 사항이며 현재 앱에서 지원되는 작업 이름, 매개변수 또는 결과가 아닙니다.

컴퓨터 측 MCP 새로 고침은 iOS 개인 자동화를 제공하지 않습니다. 일반 내보내기 단축어로 대체하지 마세요. 여전히 iPhone 폴더로 내보냅니다. 어떤 자동화도 잠자는 Mac을 깨우거나 보호된 HealthKit 데이터를 우회한다고 약속할 수 없습니다. 이 기능을 검증하려면 잠자기 해제 후 실제 iPhone에서 자동화 QA를 수행해야 합니다.

네 내보내기 작업은 선택적 **프로필**을 받습니다. 알 수 없는 이름은 대체 없이 실패합니다. 일반 단축어는 iPhone 폴더에 쓰며 API Endpoint나 Connected Mac으로 조용히 바뀌지 않습니다.

잠긴 상태 실행 허용은 HealthKit 잠금을 해제하지 않습니다. Health.md는 요청을 보류하고 **Health Export Needs Attention**을 표시합니다.

### 아침 자동화

1. 시간 자동화를 만듭니다.
2. **Export Yesterday's Health Data**를 추가합니다.
3. **Get Last Export Status**와 알림을 추가합니다.

어제에는 어젯밤 시작된 수면이 포함됩니다. [수면 날짜](/ko/docs/sleep-date-attribution/)를 참고하세요.

<div class="related"><a href="/ko/docs/export-profiles/"><span>프로필</span>안정적인 ID.</a><a href="/ko/docs/release-status/"><span>호환성</span>버전 확인.</a></div>
