---
title: "내보내다"
description: "내보내기 탭을 사용하여 HealthKit 및 볼트 연결을 확인하세요. 목적지를 선택하고 날짜 범위를 내보냅니다."
---

<p> 내보내기 탭은 세 가지 작은 결정으로 구성됩니다. 즉, 준비 상태 확인, 대상 선택, 미리보기 또는 내보내기 전에 날짜 범위 선택입니다. </p>

## 상태 배지 읽기
 <div class="options">
 <div class="option"> <strong> 상태 배지 </strong> <p> 녹색 점은 HealthKit 이 승인되었음을 의미합니다. 빨간색 점은 액세스 권한이 부여되지 않았음을 의미합니다. iOS 권한 시트를 다시 시도하려면 탭하세요. 시트는 설치당 한 번만 나타납니다. 그런 다음 설정 → 개인 정보 보호 및amp; 보안 → 건강. </p> </div>
 <div class="option"> <strong> 볼트 배지 </strong> <p> 녹색 점 = 볼트 폴더가 선택되었습니다. 금고를 다시 선택하거나 변경하려면 탭하세요. 레이블에는 폴더 이름이 표시됩니다. </p> </div>
 </div>
 <p> 내보내기 <em> 작업은 </em> , 출력 형식 및 선택한 대상이 준비될 때까지 비활성화된 상태로 HealthKit 됩니다. 이렇게 하면 가장 일반적인 실패 모드인 대상 없이 내보내기를 시도하는 것을 방지할 수 있습니다. </p>

## 내보내기 대상 선택
 <p> 내보내기 대상 카드는 데이터가 이동되는 위치를 결정합니다. </p>

<div class="options">
 <div class="option"> <strong> 로컬 iPhone 폴더 </strong> <p> 이 장치에서 선택한 폴더 또는 Obsidian 저장소에 직접 씁니다. </p> </div>
 <div class="option"> <strong> 연결된 Mac </strong> <p> 캡처한 일일 데이터와 정확한 설정 스냅샷을 근처 Mac 앱으로 보냅니다. iPhone 은 HealthKit 읽습니다. Mac은 선택한 형식을 렌더링하고 파일을 씁니다. </p> </div>
 <div class="option"> <strong> API 엔드포인트 </strong> <p> iPhone 에서 사용자가 구성한 HTTP(S) 엔드포인트로 직접 JSON 봉투를 게시합니다. <a href="/ko/docs/api-endpoint/"> API 엔드포인트 </a> 참조하세요. </p> </div>
 </div>

## 날짜 범위 선택
 <p> 날짜 사전 설정에는 일반적인 경로가 포함됩니다: </p>

<div class="options">
 <div class="option"> <strong> 오늘 </strong> <p> 현재 날짜를 내보냅니다. 출력 형식을 테스트하는 데 유용합니다. </p> </div>
 <div class="option"> <strong> 어제 </strong> <p> 하루가 완성되었기 때문에 가장 안전한 일일 내보내기 선택입니다. </p> </div>
 <div class="option"> <strong> 전체 시간 </strong> <p> Health.md 이 찾을 수 있는 가장 빠른 HealthKit 데이터에서 백필합니다. </p> </div>
 <div class="option"> <strong> 사용자 정의 </strong> <p> 특정 범위의 시작 날짜와 종료 날짜를 선택합니다. </p> </div>
 </div>

## 미리보기 또는 내보내기
 <div class="options">
 <div class="option"> <strong> 미리보기 </strong> <p> 쓰기 전에 생성될 파일과 내용을 표시합니다. </p> </div>
 <div class="option"> <strong> 내보내기 </strong> <p> 내보내기를 실행하고 기본 화면에 진행률을 표시하며 결과를 기록에 기록합니다. </p> </div>
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

저장된 프로필은 실행을 위한 설정과 대상을 고정합니다. 프로필 인식 예약 및 자동화 기록 행은 런타임 프로필을 유지하는 반면 기록은 실제로 사용된 대상에 대한 개인 정보 보호 레이블을 유지합니다. 수동 내보내기 탭 행에서는 프로필 이름이 생략될 수 있습니다. 나중에 이름을 바꾸거나 대상을 변경해도 기존 기록은 다시 작성되지 않습니다. 누락된 프로필 참조가 폴백하는 대신 페일클로즈됩니다. [프로필 내보내기](/ko/docs/export-profiles/)를 참조하세요.

## 탭바

<p> 화면 하단에 있는 내보내기, 일정, 동기화, 설정 탭 4개가 전체 앱 표시 영역을 다룹니다. 다른 모든 것은 설정 내부 깊은 곳에 한두 개의 레이어가 있습니다. </p>

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
