---
title: "일일 노트 주입"
description: "선택한 건강 항목을 기존 일일 노트(Obsidian 또는 다른 Markdown 앱에서 작성하는 노트)의 YAML 프론트매터와 선택적으로 본문에 병합합니다."
---

## 기능
<p>일일 노트(예: <code>Daily/2026-04-28.md</code>)를 사용한다면 이 기능을 켜세요. 내보낼 때마다 앱이 선택한 측정 항목을 해당 노트의 YAML 프론트매터에 <em>병합</em>하며, 노트의 나머지 내용은 변경하지 않습니다.</p>

<div class="doc-diagram merge-preview" aria-label="Health.md 병합 전후의 일일 노트 프론트매터">
<div class="merge-card">
<strong>이전</strong>
<pre><code>---
title: Tuesday note
mood: focused
---

Wrote launch notes...</code></pre>
</div>
<div class="merge-card">
<strong>내보내기 후</strong>
<pre><code>---
title: Tuesday note
mood: focused
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

Wrote launch notes...</code></pre>
</div>
</div>

<p>선택적으로 앱이 Markdown 섹션(수면, 활동, 심장 등)을 노트 본문에 삽입하도록 설정할 수도 있습니다. 이러한 섹션은 <em>앱에서 관리</em>되며, 내보낼 때마다 깔끔하게 교체됩니다. 직접 작성한 제목은 변경되지 않습니다.</p>

## 위치
<div class="options">
<div class="option"><strong>폴더</strong><p>일일 노트 폴더의 보관함 기준 상대 경로입니다. 기본값은 <code>Daily</code>입니다. 보관함 루트를 대상으로 하려면 비워 두세요. 예: <code>Daily</code>, <code>Journal/Daily</code>.</p></div>
<div class="option"><strong>파일 이름</strong><p>확장자를 제외한 노트 파일 이름 패턴입니다. 기본값 <code>{date}</code>는 <code>2026-04-28</code>로 변환됩니다.</p></div>
</div>

## 파일 이름 자리 표시자
<p>자유롭게 조합할 수 있습니다.</p>
<ul>
<li><code>{date}</code> — 전체 ISO 날짜(<code>2026-04-28</code>)</li>
<li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li>
<li><code>{weekday}</code> — 짧은 이름(<code>Tue</code>)</li>
<li><code>{monthName}</code> — 전체 이름(<code>April</code>)</li>
<li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li>
</ul>
<p>예: <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. 필드 아래의 미리보기 줄에 변환된 경로가 실시간으로 표시됩니다.</p>

## 옵션
<div class="options">
<div class="option"><strong>노트가 없으면 생성</strong><p>해당 날짜의 일일 노트가 없으면 새 노트를 만듭니다. Obsidian Templater 또는 유사한 플러그인으로 일일 노트를 직접 생성하는 경우에는 끄세요.</p></div>
<div class="option"><strong>지표 섹션 삽입</strong><p>노트 본문에 수면, 활동, 심장 등의 제목도 작성합니다. 앱에서 관리되며, 내보낼 때마다 깔끔하게 교체됩니다. 기본적으로 꺼져 있습니다.</p></div>
</div>

## 삽입되는 측정 항목
<p><em>건강 항목</em>에서 선택한 항목이 삽입됩니다. 별도의 선택기는 없습니다. 건강 항목에서 선택을 변경하면 일일 노트 주입에도 반영됩니다.</p>

## 프론트매터 미리보기
<p>일일 노트 주입 화면 하단에는 병합될 프론트매터의 실시간 미리보기가 있습니다. 측정 항목 선택이나 형식 사용자 정의의 프론트매터 필드를 변경하면 이 미리보기도 업데이트됩니다.</p>

<div class="callout">
<strong>병합 방식.</strong>
<p style="margin-top:6px;">기존 일일 노트에 이미 프론트매터가 있으면 앱은 사용자의 키를 보존하고 앱이 소유한 키만 추가하거나 업데이트합니다. 앱에서 관리하는 본문 섹션은 HTML 주석으로 감싸므로 다시 실행해도 내용이 중복되지 않습니다.</p>
</div>

## 관련 문서

<div class="related">
  <a href="/ko/docs/metrics/"><span>사전 준비</span>건강 항목 — 주입할 항목을 선택하세요.</a>
  <a href="/ko/docs/format/"><span>형식</span>프론트매터 필드 편집기 — 키 이름을 바꾸고 사용자 정의 필드를 추가하세요.</a>
  <a href="/ko/docs/individual-tracking/"><span>세부 추적</span>개별 추적 — 이벤트별 추적을 위한 대안입니다.</a>
</div>
