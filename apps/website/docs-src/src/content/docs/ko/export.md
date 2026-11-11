---
title: "내보내다"
description: "Apple Health 데이터를 지금 또는 예약에 따라 내보냅니다. 아카이브에서 준비 상태를 확인하고, 지금 내보내기에서 범위를 고르고, 자동화마다 대상을 설정하세요."
---

<p>iPhone의 Health.md에는 <strong>아카이브</strong>, <strong>자동화</strong>, <strong>설정</strong>의 세 탭과 둥근 <strong>지금 내보내기</strong> 버튼이 있습니다. iPad에서는 탭이 사이드바로 이동합니다.</p>

## 아카이브에서 준비 상태 확인하기
<p><strong>아카이브</strong> 캘린더는 각 자동화가 처리한 건강 데이터 날짜를 보여 줍니다. 내보내기를 막는 문제가 있으면 상단의 <strong>확인 필요</strong> 카드에 원인이 표시됩니다.</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.md는 앱의 설정 상태를 보여 줄 뿐, 모든 카테고리에 대한 읽기 접근이 확인된 것은 아닙니다. HealthKit은 거부된 읽기 권한을 알려 주지 않습니다. Apple Health에서 카테고리를 확인하세요. 결과가 비어 있으면 접근이 거부되었거나 데이터가 없는 것일 수 있습니다. <a href="/ko/docs/troubleshooting/">누락된 데이터 문제 해결</a>.</p></div>
<div class="option"><strong>폴더</strong><p><strong>설정 → 폴더</strong>에서 폴더를 선택하거나 다시 선택하세요. 폴더를 옮긴 뒤 iOS가 접근 권한을 잃으면 Health.md가 다시 선택하라고 요청합니다. 아무것도 삭제되지 않습니다.</p></div>
</div>

## 자동화의 내보내기 대상 선택하기
<p>각 자동화에는 고유한 대상이 있습니다. <strong>자동화</strong>를 열고 자동화를 선택한 다음 <strong>출력</strong>을 여세요.</p>

<div class="options">
<div class="option"><strong>로컬 폴더</strong><p>이 기기에서 선택한 폴더나 Obsidian 보관함에 직접 기록합니다.</p></div>
<div class="option"><strong>연결된 Mac</strong><p>수집한 일별 데이터와 설정의 정확한 스냅샷을 가까운 Mac 앱으로 보냅니다. iPhone이 HealthKit을 읽고, Mac이 선택한 형식을 만들어 파일을 기록합니다.</p></div>
<div class="option"><strong>API 엔드포인트</strong><p>JSON 봉투를 iPhone에서 직접 설정한 HTTP(S) 엔드포인트로 POST합니다. <a href="/ko/docs/api-endpoint/">API 엔드포인트 보기</a>.</p></div>
<div class="option"><strong>Agent Data 게이트웨이</strong><p>내보낸 각 파일을 변경 없이 게이트웨이의 수집 엔드포인트에 업로드합니다.</p></div>
</div>

## 지금 내보내기에서 범위 선택하기
<p><strong>지금 내보내기</strong>를 탭하고, 자동화가 여러 개라면 하나를 고른 다음 범위를 선택하세요.</p>

<div class="options">
<div class="option"><strong>어제</strong><p>하루가 끝났기 때문에 매일 내보내기에 가장 안전한 선택입니다.</p></div>
<div class="option"><strong>7일 / 30일</strong><p>어제까지의 최근 1주 또는 1개월입니다. 30일 이상이면 먼저 확인을 요청합니다.</p></div>
<div class="option"><strong>사용자 지정</strong><p>특정 범위의 시작일과 종료일을 선택합니다.</p></div>
</div>
<p><strong>기록 예정</strong>에는 대상과 내보내기가 다루는 대략적인 파일 수와 일수가 표시됩니다. <strong>날짜 범위 요약만</strong>은 일별 파일 대신 요약 파일 하나만 기록합니다. 오늘과 전체 기간은 <strong>자동화 → 모든 내보내기 설정</strong>에서 계속 사용할 수 있습니다.</p>

## 미리보기 또는 내보내기
<div class="options">
<div class="option"><strong>미리보기</strong><p>무엇이든 기록하기 전에 생성될 파일과 내용을 보여 줍니다.</p></div>
<div class="option"><strong>내보내기</strong><p>내보내기를 실행하고, 탭 막대 위에 취소 버튼과 함께 진행 상황을 표시하며, 결과를 기록과 아카이브 캘린더에 남깁니다.</p></div>
</div>

## 데이터 세부정보 수준을 선택하세요.

<div class="options">
 <div class="option"> <strong> 요약 </strong> <p> 읽기, 메모 및 대시보드에 대한 일일 합계 및 롤업을 간략하게 표시합니다. </p> </div>
 <div class="option"> <strong> 자세한 시계열 </strong> <p> 선택된 타임스탬프 샘플 및 간격. 이 수준은 선택한 측정항목이 적절한 세부정보를 노출하는 경우 Apple과 Android 모두에서 사용할 수 있습니다. </p> </div>
 <div class="option"> <strong> 무손실 건강 기록 </strong> <p> 정식 HealthKit 소스 레코드 아카이브. 이 레벨은 Apple 전용입니다. Android는 Health Connect 레코드를 HealthKit 아카이브로 변환하지 않습니다. </p> </div>
 </div>

## "내보내기"가 실제로 수행하는 작업
 <ol>
 <li> 범위 내 각 날짜에 대해 선택한 요약 예측을 캡처합니다. 상세한 시계열에 대해 호환되는 샘플을 추가합니다. 그리고 무손실 건강 기록의 경우 정식 소스 기록과 쿼리 진단을 추가하세요. </li>
 <li> 선택한 형식( Markdown , 기본, JSON 또는 CSV)과 템플릿을 적용합니다. </li>
 <li> 하루에 하나의 파일을 <code>{vault}/{subfolder}/</code> 에 쓰거나, 연결된 Mac 워크플로를 통해 파일을 전송하거나, 버전이 지정된 JSON 봉투를 API 엔드포인트에 게시하세요. </li>
 <li> 개별 추적 </em> <em> 켜져 있는 경우 파일 기반 대상에 대한 정식 아카이브에서 선택한 항목별 Markdown 파일을 파생시킵니다. </li>
 <li> 일일 메모 삽입 </em> <em> 켜져 있는 경우 선택한 요약 필드를 일일 메모에 병합합니다. </li>
 </ol>

<p> JSON 및 CSV는 표준 레코드를 보존할 수 있습니다. Markdown 및 Bases는 읽기 가능한 상태를 유지하며 아카이브를 포함하는 대신 컴팩트 캡처 진단을 노출합니다. 정확한 스키마 및 생략 규칙은 <a href="/ko/docs/reference/"> 전체 내보내기 참조 </a> 을 참조하세요. </p>

## 중지, 취소 및 재시도

중지하거나 취소하면 현재 시도만 종료됩니다. 이미 완료된 파일과 날짜는 완료된 상태로 유지되며, 해결되지 않은 날짜는 다시 시도할 수 있는 상태로 남아 있습니다. 예약된 시도를 취소해도 반복 일정은 비활성화되지 않습니다.

## 프로필과 신뢰할 수 있는 기록

저장된 프로필은 실행 시 설정과 대상을 고정합니다. 프로필을 인식하는 예약 실행과 자동화의 기록 행에는 실행 당시의 프로필이 남고, 기록에는 실제로 사용된 대상에 대한 개인정보 보호 레이블이 남습니다. 수동 내보내기 행에는 프로필 이름이 빠질 수 있습니다. 나중에 이름이나 대상을 바꿔도 기존 기록은 다시 쓰이지 않습니다. 참조한 프로필이 없으면 다른 설정으로 대체하지 않고 작업이 실패합니다. [내보내기 프로필](/ko/docs/export-profiles/)을 참고하세요.

<div class="callout">
 <strong> 잠금 해제 동작. </strong>
 <p style="margin-top:6px;"> 구독이 활성화된 iPhone / iPad 및 Google Play 전화 릴리스에는 내보내기 및 예약을 위한 활성 평가판, 구독, 평생 또는 보존된 영구 액세스가 필요합니다. 현지 자유 수출 허용량이 남아 있지 않습니다. Mac 컴패니언 및 F-Droid 포함 액세스 빌드는 문서화된 예외를 유지합니다. <a href="/ko/docs/paywall/"> Apple 구매 세부정보는 페이월 페이지 </a> 을 참조하세요. </p>
 </div>

## 관련된

<div class="related">
 <a href="/ko/docs/export-profiles/"> <span> 반복 가능한 설정 </span> 프로필을 내보내고 독립적인 설정, 대상, 일정 및 안정적인 자동화 ID를 저장합니다. </a>
 <a href="/ko/docs/scheduling/"> <span> 매일 사용 </span> 예약, 자동화하여 다시 내보내기를 탭하지 마세요. </a>
 <a href="/ko/docs/api-endpoint/"> <span> </span> API 엔드포인트를 통합하고 선택한 JSON을 자체 서비스에 직접 보냅니다. </a>
 <a href="/ko/docs/format/"> <span> 사용자 정의 </span> 형식 사용자 정의, 각 파일의 모양 변경. </a>
 <a href="/ko/docs/shortcuts/"> <span> Power </span> Shortcuts , Siri , 자동화 또는 기타 앱에서 내보내기를 트리거합니다. </a>
 <a href="/ko/docs/reference/"> <span> 참조 </span> 참조, 스키마, 정식 레코드, 진단 및 생성된 예제를 내보냅니다. </a>
 </div>
