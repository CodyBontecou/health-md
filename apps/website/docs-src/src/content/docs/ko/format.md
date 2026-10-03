---
title: "형식 사용자 정의"
description: "수집되는 항목은 변경하지 않고 출력 형식을 제어하세요. 파일 형식과 날짜, 시간, 단위 표기 규칙을 선택하고, YAML 프론트매터를 사용자 정의하며, Markdown 템플릿을 선택할 수 있습니다."
---

## 출력 형식
<div class="options">
<div class="option"><strong>Markdown (.md)</strong><p>기본값입니다. 하루에 파일 하나를 생성합니다. 선택 사항인 YAML 프론트매터와 카테고리별 제목 섹션으로 구성됩니다.</p></div>
<div class="option"><strong>Obsidian Bases</strong><p>Obsidian의 <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> 플러그인에 최적화된 구조화된 프론트매터를 사용하는 Markdown입니다. 숫자 속성은 숫자로, 날짜는 날짜로 유지됩니다.</p></div>
<div class="option"><strong>JSON</strong><p>하루에 JSON 파일 하나를 생성합니다. 무손실 건강 기록이 활성화된 경우 Apple 스키마 v8 일일 요약에 기준 <code>healthmd.healthkit_records</code> v1 아카이브를 포함할 수 있습니다.</p></div>
<div class="option"><strong>CSV</strong><p><code>Date,Category,Metric,Value,Unit,Timestamp</code> 헤더를 사용하는 CSV 파일을 하루에 하나 생성합니다. 호환성 요약 행은 필드 5개로 구성되며 타임스탬프 열을 생략합니다. 타임스탬프가 있는 행과 정규 레코드 행은 필드 6개를 모두 포함합니다.</p></div>
</div>

<div class="callout">
<strong>정확한 계약이 필요하신가요?</strong>
<p style="margin-top:6px;">프로덕션 데이터를 바탕으로 한 <a href="/ko/docs/reference/export-formats/">형식 참조</a>, <a href="/ko/docs/reference/generated/core/csv-row-contracts/">CSV 행 계약</a>, 다운로드 가능한 전체 픽스처를 참조하세요.</p>
</div>

## 날짜 및 시간
<p>날짜 형식(예: <code>YYYY-MM-DD</code>, <code>MMM d, yyyy</code>)과 시간 형식(12시간제, 24시간제)을 선택할 수 있습니다. 설정을 변경하면 화면 하단의 미리보기 블록이 실시간으로 업데이트됩니다.</p>

## 단위 체계
<p><em>미터법</em>과 <em>야드파운드법</em> 사이를 전환합니다. 거리(m/km 또는 ft/mi), 체중(kg 또는 lb), 온도(°C 또는 °F) 등에 영향을 줍니다. HealthKit은 항상 정규 단위로 저장하며, 변환은 내보내기 시점에 이루어집니다.</p>

## 프론트매터 필드
<p><em>프론트매터 필드</em>를 탭하면 전용 편집기가 열립니다.</p>
<ul>
<li>개별 기본 제공 필드(date, weekday, totalSteps 등)를 켜거나 끕니다</li>
<li>필드 이름을 변경합니다. Obsidian 설정에서 다른 키를 요구할 때 유용합니다</li>
<li>정적 값을 사용하는 사용자 정의 필드를 추가합니다(예: <code>type: health</code>)</li>
<li>내보내기 시점에 값이 결정되는 자리 표시자 필드를 추가합니다(예: <code>weather: {weather}</code>)</li>
</ul>

## Markdown 템플릿
<p><em>Markdown 템플릿</em>을 탭하면 여러 기본 제공 스타일(간결형, 섹션형, 상세형)과 완전한 사용자 정의 모드를 갖춘 템플릿 편집기가 열립니다. 미리보기 블록에는 오늘 데이터에 적용된 결과가 표시됩니다.</p>

## 미리보기
<p>형식 화면 하단의 실시간 미리보기 블록은 현재 설정으로 오늘 데이터를 렌더링합니다. 토글을 변경하고 미리보기를 확인한 다음 반복하는 것이 가장 빠르게 조정하는 방법입니다.</p>

## 데이터 세부 수준과 프로필

요약은 간결한 일일 프로젝션을 만듭니다. 상세 시계열은 측정 항목이 지원할 때 Apple과 Android에서 선택한 샘플과 구간을 추가합니다. 무손실 건강 기록은 정규 HealthKit 아카이브를 추가하는 Apple 전용 기능이며 Android 호환 계층이 아닙니다.

세부 수준은 [내보내기 프로필](/ko/docs/export-profiles/)과 함께 고정됩니다. 활성 프로필에서 바꾸면 해당 프로필만 변경됩니다.

## 관련 문서

<div class="related">
  <a href="/ko/docs/export-profiles/"><span>프로필</span>워크플로별 세부 정보 수준과 형식을 저장합니다.</a>
  <a href="/ko/docs/metrics/"><span>항목</span>건강 항목 — 먼저 데이터를 선택하세요.</a>
  <a href="/ko/docs/individual-tracking/"><span>세분화</span>개별 추적 — 완전히 다른 출력 방식입니다(항목별 파일).</a>
  <a href="/ko/docs/daily-notes/"><span>Obsidian</span>일일 노트 주입 — 동일한 프론트매터 필드를 사용합니다.</a>
  <a href="/ko/docs/reference/export-formats/"><span>계약</span>내보내기 형식 — JSON, CSV, Markdown, Bases의 정확한 동작을 확인하세요.</a>
</div>
