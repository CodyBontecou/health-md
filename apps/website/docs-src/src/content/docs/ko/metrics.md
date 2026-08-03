---
title: "건강 항목"
description: "Health.md의 현재 Apple Health 측정 항목 카탈로그에서 선택하세요. 검색하거나 전체 카테고리를 한 번에 전환하거나 개별 측정 항목을 세밀하게 제어할 수 있습니다."
---

<div class="callout">
<strong>Android 안내.</strong>
<p style="margin-top:6px;">이 페이지에서는 Apple Health 측정 항목 선택기와 생성된 HealthKit 데이터 참조를 설명합니다. Android 앱은 106개의 Health Connect 측정 항목을 제공합니다. Health Connect 설정 및 플랫폼별 동작은 <a href="/ko/docs/android/">Android 가이드</a>를 참조하세요.</p>
</div>

## 레이아웃
<div class="options">
<div class="option"><strong>개수 헤더</strong><p>활성화된 측정 항목과 카테고리 수를 실시간으로 표시합니다. 길게 탭하면 정확한 선택 상태가 클립보드에 복사됩니다.</p></div>
<div class="option"><strong>모든 측정 항목 활성화</strong><p>모든 카테고리를 켜거나 끄는 전체 전환 스위치입니다. 시작점으로 유용합니다. 모두 켠 다음 관심 없는 항목을 비활성화하세요.</p></div>
<div class="option"><strong>검색</strong><p>측정 항목 이름과 식별자를 실시간으로 필터링합니다. "heart", "sleep", "vo2"를 검색해 보세요.</p></div>
</div>

## 카테고리
<p>선택기는 일반 요약과 소스 레코드 정의를 수면, 활동, 심장, 호흡, 활력 징후, 신체 측정, 이동성, 사이클링, 영양, 마음 챙김, 생식 건강, 증상, 약물, 특수 레코드 및 운동 등의 카테고리로 그룹화합니다. 각 행에는 켜짐/꺼짐 상태와 해당 카테고리에서 활성화된 정의의 실시간 개수가 표시됩니다. 프로덕션에서 생성된 <a href="/ko/docs/reference/generated/core/metric-catalog/">측정 항목 카탈로그</a>가 현재 목록의 기준입니다.</p>

<p>카테고리를 탭하면 측정 항목을 자세히 볼 수 있습니다. 각 측정 항목에는 자체 전환 스위치와 HealthKit 식별자가 있습니다. 점의 색상은 현재 이 기기의 HealthKit에 해당 측정 항목 데이터가 있는지 나타냅니다.</p>

## 선택 범위
<p>선택한 측정 항목은 <em>모든 기능</em>에 적용됩니다.</p>
<ul>
<li>일일 내보내기 — 활성화된 측정 항목만 파일에 표시됩니다</li>
<li>개별 추적 — 활성화된 측정 항목만 항목별 파일이 생성됩니다</li>
<li>일일 노트 주입 — 활성화된 측정 항목만 프론트매터에 병합됩니다</li>
<li>단축어 — 날짜 범위 내보내기에도 동일한 선택 항목이 사용됩니다</li>
</ul>

<div class="callout">
<strong>팁.</strong>
<p style="margin-top:6px;">처음에는 선택 범위를 좁게 설정하세요. 수면, 활동, 심장을 활성화한 뒤 내보내기를 실행해 파일을 확인하고, 필요한 카테고리를 더 추가하세요. 관심 없는 측정 항목이 담긴 50줄짜리 파일을 훑는 것보다 필요한 항목을 나중에 추가하는 편이 빠릅니다.</p>
</div>

## 관련 문서

<div class="related">
  <a href="/ko/docs/reference/"><span>참조</span>내보내기 참조 — 모든 Apple 측정 항목, 키, 단위, 소스 레코드 정의 및 내보내기 구조.</a>
  <a href="/ko/docs/android/"><span>Android</span>Android 앱 — Health Connect 설정, 측정 항목, 대상 및 자동화.</a>
  <a href="/ko/docs/format/"><span>방법</span>형식 — 선택한 측정 항목이 기록되는 방식을 변경합니다.</a>
  <a href="/ko/docs/individual-tracking/"><span>세분화</span>개별 추적 — 타임스탬프가 지정된 항목마다 파일을 하나씩 추가로 생성합니다.</a>
  <a href="/ko/docs/daily-notes/"><span>Obsidian</span>일일 노트 주입 — 이 측정 항목을 일일 노트에 추가합니다.</a>
</div>
