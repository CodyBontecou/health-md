---
title: "개별 항목 추적"
description: "선택적으로 타임스탬프가 있는 항목마다 파일 하나를 작성합니다. 모든 운동, 혈압 측정값, 기분 기록이 각각 파일 이름에 타임스탬프가 포함된 고유한 Markdown 파일로 저장됩니다."
---

## 사용 시기
<p>일일 내보내기는 요약이 포함된 파일을 하루에 하나씩 생성합니다. <em>개별 추적</em>은 <em>이벤트 하나를 따로 참조</em>하려는 경우에 적합합니다. 예를 들어 일지 노트에서 특정 운동을 링크하거나 기분 항목의 백링크를 주간 검토에 추가할 수 있습니다.</p>

<p>이는 일일 내보내기를 대체하는 것이 아니라 그에 추가되는 기능입니다. 둘 다 켜면 두 종류의 파일을 모두 얻을 수 있습니다.</p>

## 2단계 설정
<p>설정 UI는 의도적으로 다음과 같은 2단계 절차로 구성되어 있습니다.</p>
<ol>
<li><strong>마스터 스위치.</strong> 기능을 전체적으로 켭니다.</li>
<li><strong>측정 항목별 선택.</strong> 개별 파일을 생성할 측정 항목을 선택합니다. 대부분의 사용자는 심박수 측정값마다 파일이 생성되는 것(하루 10,000개)은 원하지 않지만, 운동마다 파일 하나가 생성되는 것(하루 약 1개)은 원합니다.</li>
</ol>

## 빠른 작업
<div class="options">
<div class="option"><strong>추천 측정 항목 활성화</strong><p>권장 기본값은 기분, 증상, 운동, 혈압, 혈당입니다. 항목마다 파일 하나를 생성하는 방식에 적합한 측정 항목입니다.</p></div>
<div class="option"><strong>모든 측정 항목 활성화</strong><p>모든 항목을 활성화합니다. 주의하세요. 하루에 수천 개의 파일이 생성될 수 있습니다.</p></div>
<div class="option"><strong>모든 측정 항목 비활성화</strong><p>마스터 스위치는 변경하지 않고 측정 항목별 선택을 모두 해제합니다.</p></div>
</div>

## 폴더 구조
<div class="options">
<div class="option"><strong>항목 폴더</strong><p>개별 파일이 저장되는 보관함 기준 상대 경로입니다. 기본값: <code>entries</code>.</p></div>
<div class="option"><strong>카테고리별 정리</strong><p>켜면 항목이 카테고리 하위 폴더(<code>entries/workouts/</code>, <code>entries/symptoms/</code>)에 중첩됩니다. 끄면 모든 항목이 한 폴더에 나란히 저장됩니다.</p></div>
</div>

## 파일 이름 템플릿
<p>기본값: <code>{date}_{time}_{metric}</code>. 사용 가능한 자리 표시자: <code>{date}</code>, <code>{time}</code>, <code>{metric}</code>, <code>{category}</code>. 출력 예시:</p>

<div class="doc-diagram folder-tree" aria-label="개별 항목 파일 트리 예시">
<span>{vault}/entries/</span>
<span>├─ workouts/2026_07_14_0920_workouts_workouts_71000000-0000-0000-0000-000000000008.md</span>
<span>├─ symptoms/2026_07_14_0916_symptom_headache_symptom_headache_71000000-0000-0000-0000-000000000002.md</span>
<span>└─ vitals/2026_07_14_0918_blood_pressure_blood_pressure_71000000-0000-0000-0000-000000000004.md</span>
</div>

<p>정규 소스 레코드를 기반으로 한 항목에는 구성된 파일 이름 뒤에 선택한 측정 항목과 소문자 HealthKit UUID가 추가됩니다. 이렇게 하면 재실행해도 같은 소스 레코드의 경로가 유지되고, 같은 분에 발생하는 이름 충돌도 방지할 수 있습니다. UUID가 없는 호환용 항목은 기존의 짧은 파일 이름 규칙을 유지합니다.</p>

<div class="callout">
<strong>주의.</strong>
<p style="margin-top:6px;"><em>건강 항목</em>에서 하나 이상의 측정 항목을 활성화한 카테고리만 여기에 표시됩니다. 먼저 해당 화면에서 측정 항목을 활성화한 다음 돌아와 항목별 추적 여부를 선택하세요. 경로를 기반으로 자동화를 구축하기 전에 <a href="/ko/docs/reference/individual-entry-tracking/">소스 레코드 식별자 계약</a>과 생성된 <a href="/ko/docs/reference/generated/individual/filename-path-matrix/">파일 이름 매트릭스</a>를 확인하세요.</p>
</div>

## 관련 문서

<div class="related">
  <a href="/ko/docs/metrics/"><span>사전 요구 사항</span>건강 항목 — 먼저 측정 항목을 활성화하세요.</a>
  <a href="/ko/docs/format/"><span>출력</span>형식 — 항목 파일에도 적용됩니다.</a>
  <a href="/ko/docs/daily-notes/"><span>대안</span>일일 노트 주입 — 측정 항목을 노트에 첨부하는 다른 방법입니다.</a>
  <a href="/ko/docs/reference/individual-entry-tracking/"><span>계약</span>개별 항목 참조 — UUID 식별자, 프론트매터, 특수 항목 및 호환성 대체 동작을 설명합니다.</a>
</div>
