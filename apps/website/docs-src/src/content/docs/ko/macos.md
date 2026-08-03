---
title: "macOS 앱"
description: "Mac용 Health.md를 iPhone 내보내기 대상, 로컬 CLI 및 MCP 호스트, 암호화된 건강 컨텍스트 저장소, 기록 뷰어, 폴더 관리 주체로 사용하세요."
---

Mac용 Health.md는 두 가지 로컬 역할을 수행합니다.

1. iPhone 내보내기 작업을 수신하고 사용자가 선택한 폴더에 파일을 씁니다.
2. 로컬 에이전트가 사용하는 루프백 CLI, 쿼리 API, 암호화된 건강 컨텍스트 및 MCP 어댑터를 호스팅합니다.

Apple Health는 계속 iPhone에 있습니다. Mac 앱은 HealthKit을 직접 읽지 않습니다.

## 주요 영역

<div class="options">
<div class="option"><strong>동기화</strong><p>Mac이 검색 가능하며 iPhone 내보내기 작업을 받을 준비가 되었는지 표시합니다.</p></div>
<div class="option"><strong>대상 폴더</strong><p>Markdown, JSON, CSV, Bases, 롤업, ZIP 및 일일 노트 출력용 보안 범위 북마크를 저장합니다.</p></div>
<div class="option"><strong>예약</strong><p>Mac 측 예약 및 준비 상태를 표시합니다. HealthKit 데이터는 계속 iPhone에서 제공됩니다.</p></div>
<div class="option"><strong>기록</strong><p>데스크톱에서 작성한 파일의 내보내기 결과, 영속 진행 상태, 오류 및 재시도 컨텍스트를 추적합니다.</p></div>
<div class="option"><strong>설정</strong><p>대상 상태, 암호화된 컨텍스트 보존 제어 및 로컬 CLI 구성을 표시합니다.</p></div>
<div class="option"><strong>메뉴 막대</strong><p>Health.md가 로컬에서 계속 사용 가능한 동안 상태, 설정 및 앱에 빠르게 접근할 수 있습니다.</p></div>
<div class="option"><strong>CLI</strong><p>번들에 포함된 <code>healthmd</code> 및 <code>healthmd-mcp</code> 도우미를 설치하고, 설정 프롬프트를 복사하며, 선택 사항인 에이전트 스킬을 설치하고, 테스트된 명령을 표시합니다.</p></div>
</div>

## Mac 대상 설정

1. Mac에 Health.md를 설치하고 엽니다.
2. 로컬 디스크, iCloud Drive 또는 Obsidian 보관함 내부의 대상 폴더를 선택합니다.
3. iPhone의 동기화 탭에서 Mac 연결을 활성화합니다.
4. iPhone에서 연결된 Mac을 내보내기 대상으로 선택합니다.
5. 내보내기를 구성하고 내보내기를 탭합니다.

iPhone은 HealthKit 데이터와 실제 적용된 설정의 스냅샷을 캡처합니다. 현재 구현은 제한되고 체크섬으로 검증된 파티션을 전송합니다. Mac은 프로덕션 내보내기 도구를 사용하여 요청된 파일을 씁니다.

<div class="callout">
<strong>HealthKit 제한 사항.</strong>
<p style="margin-top:6px;">Mac은 자체적으로 Apple Health를 쿼리할 수 없습니다. 새로운 내보내기와 에이전트 컨텍스트를 사용하려면 연결된 iPhone 앱이 열려 있어야 합니다. 저장된 범위가 충분하면 새로운 iPhone 연결 없이도 캐시된 암호화 쿼리를 실행할 수 있습니다.</p>
</div>

## CLI 및 에이전트 설정

Mac 앱의 **CLI** 영역을 열어 다음 작업을 수행할 수 있습니다.

- 이 앱 번들에 있는 서명된 도우미의 정확한 경로 확인
- 별칭 또는 `~/.local/bin` 심볼릭 링크 명령 복사
- 에이전트 지원 설정 프롬프트 복사
- 선택 사항인 `healthmd-cli` 스킬을 사용자가 선택한 디렉터리에 설치
- 현재 상태, 진단, 추출, 쿼리, 수면, 훈련, 운동, 범위 및 내보내기 명령 확인
- 일반적인 준비 상태 오류 검토

앱은 사용자의 조작 없이 셸 시작 파일을 편집하거나 시스템 디렉터리에 설치하지 않습니다.

다음 명령으로 시작하세요.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

백엔드 선택은 [Health.md CLI](/ko/docs/cli/)를, 쿼리 아키텍처는 [로컬 에이전트](/ko/docs/agents/)를 참조하세요.

## 암호화된 건강 컨텍스트

새 쿼리 및 증거 요청은 전용 컨텍스트 가져오기 모드를 사용합니다. iPhone은 정확히 요청된 측정 항목, 소스, 날짜 및 세부 정보 범위를 읽습니다. 내보내기 파일을 만들거나 저장된 내보내기 환경설정을 변경하지 않습니다.

Mac은 압축된 소유자 날짜를 각각 독립적으로 인증된 AES-256-GCM 블롭에 저장합니다. 잠금 해제 시에만 접근할 수 있고 이 기기에서만 사용 가능한 키체인 항목에 무작위 암호화 키가 보관됩니다. 파일 이름은 무작위이며 날짜나 측정 항목 이름을 드러내지 않습니다.

설정에는 암호화된 소유자 날짜 수와 날짜 범위가 표시됩니다. 다음 두 작업은 서로 독립적으로 보존을 제어합니다.

- **이전 컨텍스트 삭제**는 선택한 경계 이전의 소유자 날짜만 제거합니다.
- **암호화된 모든 컨텍스트 삭제**는 모든 컨텍스트 파일과 전용 키체인 키를 제거합니다.

컨텍스트 보존 기능은 Apple Health 데이터, 내보내기 파일, Mac 대상 북마크 또는 연결된 제공자 자격 증명을 삭제하지 않습니다.

## 루프백 API 경계

Mac 앱은 로컬 상태, 내보내기, 쿼리, 증거, 새로 고침 및 영속 작업 경로를 위해 `127.0.0.1` 및 `::1`의 포트 `17645`에서 수신 대기합니다.

Bearer 토큰이나 에이전트 등록은 없습니다. 앱이 열려 있는 동안 모든 로컬 프로세스에서 API를 호출할 수 있습니다. 이 포트를 다른 컴퓨터에 노출하거나 프록시 또는 터널링하지 마세요.

샌드박스에서 실행되는 `healthmd-mcp` 도우미는 정규 HTTP 루프백 엔드포인트만 허용하며 셸, 임의 파일, SQL, URL 가져오기, 리소스, 프롬프트, 루트 또는 샘플링 없이 도구를 제공합니다.

## Direct CLI 액세스는 별도입니다

iPhone의 **Direct CLI 액세스** 설정은 직접 연결을 지원하는 CLI와 iPhone 사이에 별도의 신뢰 관계를 생성합니다. 원시 내보내기, 정규 추출, 생성된 파일, 상태, 재개 및 취소 작업에서 Mac 앱을 우회할 수 있습니다.

직접 모드는 Mac 앱의 암호화된 쿼리 컨텍스트를 사용하지 않습니다. 대신 이식 가능한 `healthmd mcp serve`는 페어링과 동일한 실행 파일 ID를 사용하여 포그라운드의 iPhone에서 새 타입 지정 쿼리를 직접 실행합니다. 페어링 및 플랫폼 지원에 관한 내용은 [직접 iPhone CLI](/ko/docs/cli-direct/)를 참조하세요.

## 관련 문서

<div class="related">
  <a href="/ko/docs/sync/"><span>대상</span>Mac 동기화: 로컬 파일 내보내기를 위해 iPhone과 Mac을 페어링합니다.</a>
  <a href="/ko/docs/cli/"><span>터미널</span>Health.md CLI: 도우미를 설치하고 백엔드를 선택하여 명령을 실행합니다.</a>
  <a href="/ko/docs/agents/"><span>로컬 컨텍스트</span>에이전트: 범위가 지정된 가져오기, 암호화된 저장소, 증거 및 보존.</a>
  <a href="/ko/docs/mcp/"><span>도구</span>로컬 MCP 서버: 설정, 도구 카탈로그 및 샌드박스 경계.</a>
  <a href="/ko/docs/scheduling/"><span>워크플로</span>예약: 반복되는 내보내기를 자동화합니다.</a>
</div>
