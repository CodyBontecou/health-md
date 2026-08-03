---
title: Health.md로 시작하세요.
description: Apple Health 또는 Health Connect 데이터를 내보내고, 서명된 Mac 도우미를 로컬 에이전트에 연결하고, 버전이 지정된 Health.md 계약을 기반으로 구축하세요.
---

<div class="docs-hero" data-strand-stage>
  <canvas class="docs-dna" data-three-strand aria-hidden="true"></canvas>
  <div class="docs-hero-copy">
    <p class="docs-eyebrow">현재 이용 가능 · 서명된 Mac 도우미</p>
    <p>휴대폰에서 건강 데이터를 내보내거나, 서명된 Mac 도우미를 통해 로컬 에이전트를 연결하거나, 버전이 지정된 계약을 기반으로 구축하세요. HealthKit 읽기는 iPhone에서, Health Connect 읽기는 Android에서 이루어집니다.</p>
    <div class="docs-command" aria-label="Health.md에 번들로 포함된 준비 상태 확인 명령"><span aria-hidden="true">$</span> "/Applications/Health.md.app/Contents/Helpers/healthmd" doctor</div>
    <p class="docs-command-note">다른 위치에 설치했나요? <strong>Mac용 Health.md → CLI</strong>에서 번들 도우미 경로를 복사하세요.</p>
    <div class="docs-actions">
      <a class="docs-button" href="/ko/docs/iphone-first-export/">첫 iPhone 내보내기</a>
      <a class="docs-button-secondary" href="/ko/docs/configuration/">에이전트 연결</a>
      <a class="docs-button-secondary" href="/ko/docs/reference/">계약 살펴보기</a>
    </div>
  </div>
</div>

<div class="agent-path" aria-label="Health.md 목표 선택">
  <a href="/ko/docs/iphone-first-export/"><span>01 · 내보내기</span><strong>iPhone에서 시작</strong>Apple Health 접근을 허용하고, 폴더를 선택하고, 출력을 미리 본 다음 첫 내보내기를 실행하세요.</a>
  <a href="/ko/docs/configuration/"><span>02 · 질문</span><strong>로컬 에이전트 연결</strong>Codex, Claude 또는 다른 stdio 클라이언트에서 서명된 Mac MCP 도우미를 사용하세요.</a>
  <a href="/ko/docs/reference/"><span>03 · 구축</span><strong>안정적인 계약 사용</strong>스키마, 레코드, 증거, 생성된 픽스처 및 정확한 엔벨로프를 통합하세요.</a>
</div>

<div class="reference-stats">
<div><strong>21</strong><span>번들 Mac MCP 도구</span></div>
<div><strong>4</strong><span>내보내기 형식</span></div>
<div><strong>v7</strong><span>공개 내보내기 스키마</span></div>
<div><strong>0</strong><span>필수 Health.md 클라우드 경유 횟수</span></div>
</div>

<p class="docs-section-kicker">현재 이용 가능 · macOS</p>

## 5분 만에 로컬 에이전트 시작하기

Mac에서 Health.md를 연 다음, 페어링된 iPhone에서 Health.md를 열고 연결될 때까지 기다리세요. 번들 도우미는 건강 값을 반환하지 않고 준비 상태를 확인하고, 수면 측정 항목을 나열하며, 하루 범위의 쿼리를 실행합니다.

```bash
HMD="/Applications/Health.md.app/Contents/Helpers/healthmd"
"$HMD" doctor
"$HMD" metrics list --category Sleep
"$HMD" query --category Sleep --yesterday
```

준비가 완료된 `doctor` 결과는 `healthmd.cli_doctor` 스키마를 사용하며, 설정이 완료되지 않은 경우 다음 작업을 포함합니다. Codex 또는 Claude를 사용하려면 [에이전트 구성](/ko/docs/configuration/)으로 이동하여 별도의 서명된 `healthmd-mcp` 도우미를 클라이언트에 지정하세요.

<p class="docs-section-kicker">목표별 선택</p>

## 구성 및 연결

<div class="related">
  <a href="/ko/docs/configuration/"><span>현재 이용 가능 · Mac</span>구성 — Codex, Claude 또는 다른 stdio 클라이언트를 서명된 MCP 도우미에 연결하세요.</a>
  <a href="/ko/docs/mcp/"><span>현재 이용 가능 · Mac</span>MCP 서버 및 앱 — 번들로 포함된 21개 도구를 살펴보고, 비공개 시각화를 렌더링하며, 이식 가능한 미리보기를 이해하세요.</a>
  <a href="/ko/docs/cli/"><span>현재 이용 가능 · Mac</span>Health.md CLI — 번들 도우미를 설치하고, 준비 상태를 검사하고, 데이터를 쿼리하며, 이식 가능한 미리보기를 구분하세요.</a>
  <a href="/ko/docs/agents/"><span>아키텍처</span>에이전트 컨텍스트 — 요청 범위, 로컬 신뢰, 암호화된 컨텍스트, 증거, 보존 및 개인정보 보호를 알아보세요.</a>
</div>

<p class="docs-section-kicker">일상 작업</p>

## 쿼리, 추출 및 자동화

<div class="related">
  <a href="/ko/docs/agent-queries/"><span>타입 지정 쿼리</span>측정 항목, 수면 세션, 운동, 비교, 데이터 범위 및 사실 기반 증거를 요청하세요.</a>
  <a href="/ko/docs/cli-direct/"><span>미리보기 · 이식 가능한 CLI</span>iPhone 직접 액세스 — 독립 실행형 패키지가 출시되기 전에 수동 IP 또는 Tailscale 페어링 방식을 알아보세요.</a>
  <a href="/ko/docs/cli-extract/"><span>소스 데이터</span>정규 추출 — 선택한 스키마 v7 일별 데이터, 소스 레코드, 프로젝션 또는 JSONL을 가져오세요.</a>
  <a href="/ko/docs/cli-jobs/"><span>신뢰할 수 있는 실행</span>영속 작업 — 시간 초과, 알 수 없는 결과, 재개, 취소 및 부분 결과를 안전하게 처리하세요.</a>
  <a href="/ko/docs/agent-api/"><span>저수준</span>루프백 API — 정확한 쿼리, 증거, 커서, 새로 고침 및 영속 작업 경로를 사용하세요.</a>
  <a href="/ko/docs/reference/integration-recipes/"><span>패턴</span>통합 레시피 — 계약을 약화하지 않고 Health.md 출력을 구문 분석하고 검증하세요.</a>
</div>

<p class="docs-section-kicker">안정적인 인터페이스</p>

## 데이터 계약 및 구조

<div class="related">
  <a href="/ko/docs/reference/"><span>계약 맵</span>내보내기 참조 — 스키마, 측정 항목, 형식, 레코드 및 상호 운용성 픽스처를 살펴보세요.</a>
  <a href="/ko/docs/reference/api-and-cli/"><span>자동화</span>API 및 CLI 계약 — 엔벨로프, 경로, 종료 동작 및 생성된 예제를 검사하세요.</a>
  <a href="/ko/docs/reference/evidence-packets/"><span>에이전트 결과</span>쿼리 및 증거 — 타입이 지정된 값, 데이터 범위, 누락 상태, 작업 및 결정론적 식별자를 확인하세요.</a>
  <a href="/ko/docs/reference/daily-records/"><span>스키마 v7</span>일별 레코드 — 공개 소스 문서와 그 소유권 규칙을 이해하세요.</a>
  <a href="/ko/docs/shared-metric-registry/"><span>용어</span>측정 항목 레지스트리 — 안정적인 크로스 플랫폼 측정 항목 ID, 카테고리, 단위 및 프로필 메타데이터를 사용하세요.</a>
  <a href="/ko/docs/reference/generated/"><span>기계 판독 가능</span>생성된 아티팩트 — 정규 필드, 픽스처, 메시지 인벤토리 및 CLI 계약을 여세요.</a>
</div>

<p class="docs-section-kicker">제품 워크플로</p>

## 앱 및 내보내기

<div class="related">
  <a href="/ko/docs/iphone-first-export/"><span>여기에서 시작 · iPhone</span>첫 내보내기 — Apple Health 접근을 허용하고, 폴더를 선택하고, 출력을 미리 보고, 작성된 파일을 확인하세요.</a>
  <a href="/ko/docs/android/"><span>Android</span>Health Connect — 문서 제공자 폴더를 선택하고 플랫폼 자동화를 구성하세요.</a>
  <a href="/ko/docs/export/"><span>파일</span>내보내기 — Markdown, CSV, JSON 또는 Obsidian Bases로 명시적인 날짜 범위를 실행하세요.</a>
  <a href="/ko/docs/format/"><span>구조</span>형식 사용자 정의 — 단위, 날짜, 프론트매터, 파일 이름 및 쓰기 동작을 제어하세요.</a>
  <a href="/ko/docs/scheduling/"><span>백그라운드</span>예약 — 일별 및 주별 내보내기 동작과 플랫폼 제한을 이해하세요.</a>
  <a href="/ko/docs/shortcuts/"><span>자동화</span>단축어 및 App Intents — Apple 워크플로에서 내보내기, 요약 및 상태 확인을 실행하세요.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:12px; font-family:var(--sl-font-mono);">문서 구조 업데이트: 2026-08-02</p>
