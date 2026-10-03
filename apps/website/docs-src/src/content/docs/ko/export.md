---
title: "내보내기"
description: "내보내기 탭은 기본 작업 공간입니다. HealthKit과 보관함의 연결 상태를 확인하고, 대상을 선택하고, 지정한 날짜 범위의 일회성 내보내기를 실행할 수 있습니다."
---

<p>내보내기 탭은 준비 상태 확인, 대상 선택, 날짜 범위 선택 후 미리보기 또는 내보내기라는 세 가지 간단한 결정으로 구성됩니다.</p>

## 상태 배지 확인
<div class="options">
<div class="option"><strong>건강 배지</strong><p>초록색 점 = HealthKit 승인됨. 빨간색 = 권한이 부여되지 않음. 탭하면 iOS 권한 시트를 다시 표시합니다(설치당 처음 한 번만 작동하며, 그 이후에는 iOS에서 아무 반응도 나타나지 않으므로 설정 → 개인정보 보호 및 보안 → 건강에서 직접 수정해야 합니다).</p></div>
<div class="option"><strong>보관함 배지</strong><p>초록색 점 = 보관함 폴더가 선택됨. 탭하여 보관함을 다시 선택하거나 변경할 수 있습니다. 레이블에는 폴더 이름이 표시됩니다.</p></div>
</div>
<p>HealthKit, 출력 형식, 선택한 대상이 준비될 때까지 <em>내보내기</em> 작업은 비활성화된 상태로 유지됩니다. 이렇게 하면 대상을 지정하지 않고 내보내려는 가장 일반적인 오류를 방지할 수 있습니다.</p>

## 내보내기 대상 선택
<p>내보내기 대상 카드에서 데이터가 저장될 위치를 결정합니다.</p>

<div class="options">
<div class="option"><strong>iPhone 로컬 폴더</strong><p>이 기기에서 선택한 폴더나 Obsidian 보관함에 직접 기록합니다.</p></div>
<div class="option"><strong>연결된 Mac</strong><p>수집한 일별 데이터와 정확한 설정 스냅샷을 근처의 Mac 앱으로 전송합니다. iPhone은 HealthKit을 읽고, Mac은 선택한 형식으로 렌더링하여 파일을 기록합니다.</p></div>
<div class="option"><strong>API 엔드포인트</strong><p>사용자가 구성한 HTTP(S) 엔드포인트로 iPhone에서 직접 JSON 엔벨로프를 POST합니다. <a href="/ko/docs/api-endpoint/">API 엔드포인트 보기</a>.</p></div>
</div>

## 날짜 범위 선택
<p>날짜 사전 설정은 일반적인 사용 방식을 지원합니다.</p>

<div class="options">
<div class="option"><strong>오늘</strong><p>현재 날짜를 내보냅니다. 출력 형식을 테스트할 때 유용합니다.</p></div>
<div class="option"><strong>어제</strong><p>하루가 완전히 종료된 상태이므로 가장 안전한 일별 내보내기 선택입니다.</p></div>
<div class="option"><strong>전체 기간</strong><p>Health.md가 찾을 수 있는 가장 이른 HealthKit 데이터부터 소급하여 채웁니다.</p></div>
<div class="option"><strong>사용자 지정</strong><p>특정 범위의 시작일과 종료일을 선택합니다.</p></div>
</div>

## 미리보기 또는 내보내기
<div class="options">
<div class="option"><strong>미리보기</strong><p>실제로 기록하기 전에 생성될 파일과 내용을 보여 줍니다.</p></div>
<div class="option"><strong>내보내기</strong><p>내보내기를 실행하고 기본 화면에 진행 상황을 표시하며 결과를 기록에 저장합니다.</p></div>
</div>

## 데이터 세부 수준 선택

<div class="options">
<div class="option"><strong>요약</strong><p>읽기, 노트 및 대시보드에 적합한 간결한 일일 합계와 롤업입니다.</p></div>
<div class="option"><strong>상세 시계열</strong><p>선택된 타임스탬프 샘플과 구간입니다. 측정 항목이 적절한 세부 정보를 제공하면 Apple과 Android 모두에서 사용할 수 있습니다.</p></div>
<div class="option"><strong>무손실 건강 기록</strong><p>정규 HealthKit 소스 레코드 아카이브입니다. 이 수준은 Apple 전용이며 Android는 Health Connect 레코드를 HealthKit 아카이브로 변환하지 않습니다.</p></div>
</div>

## 실제로 "내보내기"를 실행하면 이루어지는 작업
<ol>
<li>범위 내 각 날짜의 선택된 요약을 수집하고, 상세 시계열에서는 호환 샘플을 추가하며, 무손실 건강 기록에서는 정규 소스 레코드와 쿼리 진단도 추가합니다.</li>
<li>선택한 형식(Markdown, Bases, JSON 또는 CSV)과 템플릿을 적용합니다.</li>
<li><code>{vault}/{subfolder}/</code>에 날짜별로 파일 하나를 기록하거나, 연결된 Mac 워크플로를 통해 파일을 전송하거나, 버전이 지정된 JSON 엔벨로프를 API 엔드포인트로 POST합니다.</li>
<li><em>개별 추적</em>이 활성화된 경우 파일 기반 대상에 대해 정규 아카이브에서 선택된 항목별 Markdown 파일을 생성합니다.</li>
<li><em>일일 노트 주입</em>이 활성화된 경우 선택한 요약 필드를 일일 노트에 병합합니다.</li>
</ol>

<p>JSON과 CSV는 정규 레코드를 보존할 수 있습니다. Markdown과 Bases는 가독성을 유지하며 아카이브를 포함하는 대신 간결한 수집 진단을 제공합니다. 정확한 스키마와 생략 규칙은 <a href="/ko/docs/reference/">전체 내보내기 참조</a>를 확인하세요.</p>

## 중지, 취소 및 재시도

중지 또는 취소는 현재 시도만 끝냅니다. 완료된 파일과 날짜는 유지되고 미해결 날짜는 다시 시도할 수 있습니다. 예약 실행을 취소해도 반복 일정은 비활성화되지 않습니다.

## 프로필과 신뢰할 수 있는 기록

저장된 프로필은 실행에 사용할 설정과 대상을 고정합니다. 프로필 인식 예약 실행과 자동화의 기록 행에는 실행 당시 프로필이 남고, 기록에는 실제 대상의 개인정보 보호 레이블도 유지됩니다. 수동 내보내기 행은 프로필 이름을 생략할 수 있습니다. 이후 이름이나 대상을 변경해도 기존 기록은 다시 작성되지 않습니다. 없는 프로필 참조는 안전하게 실패합니다. [내보내기 프로필](/ko/docs/export-profiles/)을 참조하세요.

## 탭 막대

<p>화면 하단의 네 탭(내보내기, 예약, 동기화, 설정)에서 앱의 모든 기능을 사용할 수 있습니다. 나머지 항목은 설정에서 한두 단계 안에 찾을 수 있습니다.</p>

<div class="callout">
<strong>잠금 해제 후 이용할 수 있는 기능.</strong>
<p style="margin-top:6px;">Apple 플랫폼의 무료 한도는 수동 또는 예약 내보내기 작업 10회에 함께 적용됩니다. Full Access는 이 한도를 없애고 Mac 대상 워크플로와 단축어를 잠금 해제합니다. Android는 수동 작업 10회만 무료이며 예약에는 평생 구매가 필요합니다. Apple 구매 정보는 <a href="/ko/docs/paywall/">결제 화면 페이지</a>를 확인하세요.</p>
</div>

## 관련 항목

<div class="related">
  <a href="/ko/docs/export-profiles/"><span>프로필</span>독립적인 대상, 설정, 일정 및 자동화 ID를 저장합니다.</a>
  <a href="/ko/docs/scheduling/"><span>일상적 사용</span>예약 — 내보내기를 다시 탭할 필요가 없도록 자동화합니다.</a>
  <a href="/ko/docs/api-endpoint/"><span>통합</span>API 엔드포인트 — 선택한 JSON을 자체 서비스로 직접 전송합니다.</a>
  <a href="/ko/docs/format/"><span>사용자 정의</span>형식 사용자 정의 — 각 파일의 모양을 변경합니다.</a>
  <a href="/ko/docs/shortcuts/"><span>고급 기능</span>단축어 — Siri, 자동화 또는 다른 앱에서 내보내기를 실행합니다.</a>
  <a href="/ko/docs/reference/"><span>참조</span>내보내기 참조 — 스키마, 정규 레코드, 진단 및 생성된 예시입니다.</a>
</div>
