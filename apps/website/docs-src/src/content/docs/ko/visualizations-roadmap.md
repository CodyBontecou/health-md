---
title: 시각화 및 로드맵
description: 내보낸 데이터 유형별로 정리한 현재 Health.md Obsidian 시각화 지원 범위와 계획된 차트입니다.
---

Health.md는 Markdown, Obsidian Bases, JSON 및 CSV용으로 스키마 버전이 지정된 로컬 데이터 세트를 내보냅니다. 아래 로드맵은 이 데이터 영역을 연동 Obsidian 시각화 플러그인과 연결해 현재 제공되는 기능, 내보낸 데이터로 추가할 수 있는 기능, 범용 스키마 인식 차트가 필요한 카테고리를 보여 줍니다.

<div class="callout">
<strong>데이터 소스.</strong>
<p style="margin-top:6px;">이 페이지는 Health.md의 내보내기 스키마와 데이터 사전을 기준으로 활동, 수면, 심장, 활력 징후, 신체, 영양, 마음 챙김, 투여약, 운동, 생식 건강, 증상, 청각 및 생활 방식/환경 측정 항목을 정리합니다.</p>
</div>

## 시각화별 단위 재정의

플러그인 전체 설정과 다른 표시 단위를 하나의 차트에서 사용하려면 개별 `units` 설정을 `health-viz` 블록에 추가하세요.

```health-viz
type: workout-trends
metric: distance
units: imperial
```

`auto`는 내보내기에서 선언한 단위 체계를 따르고, `metric`은 킬로미터·킬로그램·미터·섭씨로 표시하며, `imperial`은 마일·파운드·피트·화씨로 표시합니다. 재정의는 해당 시각화에만 적용되며 전역 Units 설정보다 우선합니다. 표시 값만 바뀌고 내보낸 Health.md 파일은 변경되지 않습니다. 걸음 수, BPM, 백분율, 칼로리처럼 변환할 수 없는 지표는 그대로 유지됩니다.

## 현재 시각화 지원 범위

<div class="reference-stats">
<div><strong>43</strong><span>현재 제공되는 플러그인 렌더러</span></div>
<div><strong>18</strong><span>내보내기 데이터 카테고리</span></div>
<div><strong>220+</strong><span>정규 내보내기 키</span></div>
<div><strong>1</strong><span>아직 필요한 범용 측정 항목 계층</span></div>
</div>

## 내보내기 도구별 플랫폼 지원

시각화 지원 여부는 소스 데이터가 Apple HealthKit과 Android Health Connect에 모두 존재하는지, 아니면 Apple HealthKit 내보내기 계약에만 존재하는지에 따라 달라집니다.

### iOS 및 Android

다음 시각화는 공통 HealthKit / Health Connect 내보내기 필드에 매핑됩니다.

| 카테고리 | 시각화 유형 |
| --- | --- |
| 개요 | `intro-stats`, `summary-card`, `trend-tile` |
| 활동 | `activity-rings`, `vitals-rings`, `bar-chart`, `activity-heatmap`, `step-spiral`, `weekday-average` |
| 심장 | `heart-terrain`, `heart-range`, `hrv-trend` |
| 호흡 및 활력 징후 | `oxygen-river`, `oxygen-range`, `breathing-wave` |
| 수면 | `sleep-schedule`, `sleep-quality-bars`, `sleep-architecture`, `sleep-polar` |
| 이동성 | `walking-symmetry`* |
| 운동 | `workout-log`, `workout-heart-rate`, `workout-zones`, `workout-trends`, `workout-intervals`, `workout-map` |

참고:

- Android에서 `walking-symmetry`는 부분적으로 지원됩니다. Android에는 보행 속도가 있지만 Apple 전용 비대칭성 또는 이중 지지 세부 정보는 없습니다.
- Android에서 `activity-rings`의 일어서기는 부분적으로 지원됩니다. `standHours`가 없으면 플러그인이 걸음 수에서 파생한 일어서기 대체값을 사용합니다.
- 운동 경로 및 샘플 차트에는 세분화된 운동 데이터와 경로 권한/동의가 필요합니다.

### iOS 전용

HealthKit 마음 상태 / 기분 시각화:

- `mood-trend` / `state-of-mind`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

투여약 목록 / 복용 이벤트 시각화:

- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

Android Health Connect는 이에 상응하는 HealthKit 마음 상태 기록이나 HealthKit 방식의 투여약 목록 / 복용 이벤트 기록을 제공하지 않습니다.

### Android 전용

현재 Obsidian 플러그인 시각화 레지스트리에는 없습니다. Android는 PHR/FHIR 리소스, 계획된 운동, 활동 강도와 같은 Android 고유 데이터를 내보내지만, 아직 이러한 필드를 대상으로 하는 시각화 유형은 없습니다.

<span id="visualization-screenshot-gallery"></span>

## 시각화 카탈로그

각 항목은 [Health.md 시각화 갤러리](/visualizations/)의 해당 공개 버전으로 연결됩니다. 링크에 `theme-colors` 변형을 사용해 모든 렌더러를 이 페이지에 삽입하지 않고도 로드 속도와 안정성을 유지합니다.

### 요약 및 개요

- [소개 통계](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [요약 카드](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [추세 타일](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### 활동

- [활동 링](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [막대 차트](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [활동 히트맵](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [걸음 수 나선형 차트](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [요일별 평균](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### 심장

- [심박 지형도](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [심박 범위](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [HRV 추세](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### 호흡, 산소 및 활력 징후

- [산소 흐름 차트](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [산소 범위](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [호흡 파형](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [활력 징후 링](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### 수면

- [수면 일정](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [수면 품질 막대](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [수면 구조](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [수면 극좌표 차트](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### 마음 챙김 및 기분

- [기분 추세](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [기분 달력 히트맵](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [기분 × 수면 산점도](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [하루 기분 타임라인](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [연관 요소별 기분](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [기분 레이블 클라우드](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [기분 변동성](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [일일 기분과 순간 기분 비교](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [일주기 기분 시계](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [회복 + 마음가짐 타일](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [기분 연관성 행렬](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### 투여약

- [투여약 개요](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [투여약 목록](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [복약 순응도 요약](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [투여약 복용 상태](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [복약 순응도 추세](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [최근 투여약 복용 이벤트](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### 이동성, 보행 및 달리기 자세

- [보행 대칭성](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### 운동

- [운동 기록](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [운동 심박수](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [운동 구간](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [운동 추세](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [운동 인터벌](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [운동 지도](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## 기반 기능 로드맵

가장 큰 제품 공백은 차트 하나가 빠진 것이 아닙니다. 측정 항목마다 사용자 정의 파서와 렌더러를 작성하지 않고도 내보낸 모든 Health.md 필드를 차트로 표시하는 범용 스키마 인식 측정 항목 계층이 필요합니다.

### 구현됨

- 일일 내보내기, 레거시 파일, 롤업 및 데이터 사전 파일에 대한 스키마 호환성 감지.
- JSON, CSV, Markdown 및 Obsidian Bases 불러오기.
- 주간/월간/연간 요약이 일일 차트를 오염시키지 않도록 하는 롤업 인식.
- 차트 지점에서 해당 데이터를 제공한 Health.md 파일로 이동하는 소스 파일 탐색.

### 계획됨

- **범용 스키마 인식 측정 항목 접근자** — `_healthmd_data_dictionary.json`에서 레이블, 단위, 카테고리, 집계 규칙 및 별칭을 읽습니다.
- **범용 측정 항목 추세** — 내보낸 모든 숫자 키를 위한 선/영역 차트입니다.
- **범용 측정 항목 막대** — 목표선 및 임곗값 선을 포함하는 일반화된 일간/주간/월간 막대입니다.
- **범용 달력 히트맵** — 모든 일일 숫자 측정 항목을 달력 격자로 표시합니다.
- **시각화 지원 범위 보고서** — 보관함에 존재하는 필드와 전용 렌더러가 지원하는 필드를 보여 줍니다.

---

## 요약 및 개요

### 구현됨

- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) — 합계, 평균, 수면 및 활력 징후를 포함한 데이터 세트 요약입니다.
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) — 스파크라인과 이전 기간 비교를 포함하는 Apple 스타일 KPI 카드입니다.
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) — 현재 기간과 이전 기간을 비교하는 추세 카드입니다.

### 계획됨

- 선택한 Health.md 폴더에 존재하는 필드를 기반으로 자동 생성되는 대시보드.
- 데이터 카테고리별 스키마 지원 범위 대시보드.
- 수면과 기분, HRV와 운동, 증상과 의약품 또는 음주와 수면 같은 상관관계 요약 카드.

---

## 활동

Health.md는 걸음 수, 활동 에너지, 기초 에너지, 운동 시간, 일어서기 시간, 오른 계단 수, 걷기/달리기 거리, 사이클링, 수영, 휠체어 활동, 활강 스키 거리, 움직이기 시간, 신체 활동 강도 및 VO₂ max를 내보냅니다.

### 구현됨

- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)

### 계획됨

- 걸음 수, 칼로리, 운동, 일어서기 시간 및 신체 활동 강도를 위한 활동 부하 대시보드.
- VO₂ max 추세.
- 움직이기 / 운동하기 / 일어서기 일관성 차트.
- 걷기/달리기, 사이클링, 수영, 휠체어 및 설상 스포츠 전반의 거리 구성 차트.
- 수영 거리 + 스트로크 차트.
- 휠체어 거리 + 밀기 횟수 차트.

---

## 수면

Health.md는 총수면, 취침 시각, 기상 시각, 깊은 수면/REM/코어/깨어 있음/침대에 있던 시간과 세분화된 수면 단계 구간을 내보냅니다.

### 구현됨

- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)

### 계획됨

- 수면 부채 및 일관성 점수.
- 수면 단계 비율 추세.
- 취침/기상 규칙성 히트맵.
- 수면 + HRV + 안정 시 심박수 회복 대시보드.

---

## 심장

Health.md는 안정 시 심박수, 보행 심박수, 평균/최저/최고 심박수, HRV, 심박수 샘플, HRV 샘플, 심박수 회복 및 심방세동 부담을 내보냅니다.

### 구현됨

- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)

### 계획됨

- 안정 시 심박수 추세.
- 보행 심박수 추세.
- 심박수 회복 추세.
- 심방세동 부담 차트.
- HRV + 안정 시 심박수 회복 타일.
- 시간대별 일주기 심박수 프로필.

---

## 호흡 및 산소

Health.md는 평균/최저/최고 혈중 산소, 혈중 산소 샘플, 평균/최저/최고 호흡수 및 호흡수 샘플을 내보냅니다.

### 구현됨

- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)

### 계획됨

- 전용 호흡 범위 차트.
- 산소포화도 저하 이벤트 차트.
- 수면 단계, 산소 및 호흡수를 결합한 야간 호흡 대시보드.

---

## 활력 징후

Health.md는 체온, 혈압, 혈당, 기초 체온, 손목 온도, 피부 전기 활동, 노력성 폐활량, FEV1, 최대 호기 유량 및 흡입기 사용량을 내보냅니다.

### 구현됨

- 요약 카드와 범용 일일 차트를 통해 부분적으로 지원됩니다.

### 계획됨

- 임곗값 구간을 포함한 수축기/이완기 혈압 범위 차트.
- 혈당 범위 차트.
- 체온, 기초 체온 및 손목 온도 추세.
- 손목 온도 회복 / 질병 타일.
- FVC, FEV1, 최대 유량 및 흡입기 사용량을 위한 호흡 기능 대시보드.
- 피부 전기 활동 / 스트레스 추세.

---

## 신체 측정값

Health.md는 체중, 신장, BMI, 체지방률, 제지방량 및 허리둘레를 내보냅니다.

### 구현됨

- 아직 전용 신체 구성 렌더러가 없습니다.

### 계획됨

- 신체 구성 대시보드.
- 이동 평균과 목표선을 포함한 체중 추세.
- 카테고리 구간을 포함한 BMI 추세.
- 체지방과 제지방량 비교 차트.
- 허리둘레 추세.

---

## 이동성, 보행 및 달리기 자세

Health.md는 보행 속도, 걸음 길이, 이중 지지, 보행 비대칭성, 계단 오르기/내려가기 속도, 6분 걷기, 보행 안정성, 달리기 속도, 달리기 보폭, 지면 접촉 시간, 수직 진폭 및 러닝 파워를 내보냅니다.

### 구현됨

- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)

### 계획됨

- 보행 대시보드.
- 보행 안정성 게이지.
- 6분 걷기 추세.
- 계단 오르기/내려가기 속도 차트.
- 속도, 보폭, 지면 접촉, 수직 진폭 및 파워를 위한 달리기 자세 대시보드.

---

## 운동

Health.md는 운동 횟수, 시간, 칼로리, 거리, 운동 유형, 심박수 통계, 달리기/사이클링 자세 측정 항목, 파워, 고도, 랩, 구간 기록, 경로 지점, 심박수 구간 및 운동 시계열 샘플을 내보냅니다.

### 구현됨

- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)

### 계획됨

- 운동 달력 히트맵.
- 지속 시간과 강도를 기반으로 한 훈련 부하 차트.
- 유형별 주간 운동 분포.
- 운동 유형별 페이스 및 속도 추세.
- 고도 상승/하강 추세.
- 경로 비교 소형 다중 차트.
- 파워 곡선 / 최고 기록.
- 달리기 자세 및 사이클링 성능 대시보드.

---

## 마음 챙김 및 기분

Health.md는 마음 챙김 시간, 마음 챙김 세션, 마음 상태 항목, 평균 정서가, 일일 기분, 순간 감정, 레이블 및 연관 요소를 내보냅니다.

### 구현됨

- [`mood-trend`](/visualizations/mindfulness-mood/mood-trend/theme-colors/)
- [`mood-calendar-heatmap`](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/)
- [`mood-sleep-scatter`](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/)
- [`mood-day-timeline`](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/)
- [`mood-association-breakdown`](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/)
- [`mood-label-cloud`](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/)
- [`mood-volatility`](/visualizations/mindfulness-mood/mood-volatility/theme-colors/)
- [`mood-kind-split`](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/)
- [`mood-circadian-clock`](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/)
- [`mood-recovery-tile`](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/)
- [`mood-association-matrix`](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/)

### 계획됨

- 마음 챙김 시간 추세.
- 마음 챙김 세션 연속 기록/달력.
- 기분과 투여약 복약 순응도 비교.
- 기분과 영양, 음주 및 카페인 비교.
- 기분 레이블 타임라인.

---

## 투여약

Health.md는 투여약 목록, 활성/보관 항목 수, 복용 이벤트 수, 복용/건너뜀 횟수, 투여약 세부 정보, RxNorm/코딩 메타데이터, 복용량, 일정 유형, 예정/시작/종료 날짜, 상태 및 메타데이터를 내보냅니다.

### 구현됨

- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)

### 계획됨

- 투여약 일정 타임라인.
- 복약 순응도 달력 히트맵.
- 예정 시각과 실제 복용 시각을 비교하는 복용 지연 차트.
- 복용량 추세.
- 투여약과 증상/기분의 상관관계 보기.
- RxNorm / 코딩 세부 정보 패널.

---

## 영양

Health.md는 섭취 칼로리, 단백질, 탄수화물, 지방, 포화 지방, 단일불포화 지방, 다중불포화 지방, 식이섬유, 당, 나트륨, 콜레스테롤, 수분 및 카페인을 내보냅니다.

### 구현됨

- 아직 전용 영양 렌더러가 없습니다.

### 계획됨

- 영양 대시보드.
- 다량영양소 구성 차트.
- 섭취 칼로리와 활동 칼로리 비교 차트.
- 수분 섭취 추세.
- 일일 카페인 섭취량 / 섭취 시각 차트.
- 당 및 나트륨 임곗값 차트.
- 식이섬유 및 단백질 목표 진행률.

---

## 비타민 및 미네랄

Health.md는 비타민 A, B6, B12, C, D, E, K, 티아민, 리보플라빈, 니아신, 엽산, 비오틴, 판토텐산, 칼슘, 철분, 칼륨, 마그네슘, 인, 아연, 셀레늄, 구리, 망간, 크로뮴, 몰리브덴, 염화물 및 요오드를 내보냅니다.

### 구현됨

- 아직 전용 미량영양소 렌더러가 없습니다.

### 계획됨

- 미량영양소 히트맵.
- 일일 권장량 진행률 격자.
- 비타민 추세 대시보드.
- 미네랄 추세 대시보드.
- 결핍/과잉 플래그 패널.
- 영양 완전성 점수.

---

## 청각

Health.md는 헤드폰 오디오 레벨과 환경 소음 레벨을 내보냅니다.

### 구현됨

- 요약 수준에서만 부분적으로 지원됩니다.

### 계획됨

- 청각 노출 추세.
- 소음이 큰 날 달력.
- 안전 노출 임곗값 구간.
- 주간 노출 요약.

---

## 생식 건강 및 생리 주기 추적

Health.md는 생리량, 성생활, 배란 검사 결과, 자궁경부 점액 상태 및 생리 사이 출혈을 내보냅니다.

### 구현됨

- 아직 전용 생식 건강 렌더러가 없습니다.

### 계획됨

- 생리 주기 달력.
- 생리량 히트맵.
- 가임 신호 타임라인.
- 생식 건강, 증상, 기분 및 수면을 결합한 생리 주기 증상 오버레이.
- 점상 출혈 / 생리 사이 출혈 타임라인.

---

## 증상

Health.md는 두통, 피로, 메스꺼움, 어지럼증, 기분 변화, 수면 변화, 식욕 변화, 안면 홍조, 오한, 발열, 요통, 복부 팽만, 변비, 설사, 속쓰림, 기침, 인후통, 콧물, 호흡 곤란, 흉통, 건너뛴 심장 박동, 빠른 심장 박동, 여드름, 피부 건조, 탈모, 기억력 감퇴, 식은땀, 구토, 복부 경련, 유방 통증, 골반 통증, 전신 통증, 실신, 후각 상실, 미각 상실, 천명, 부비동 울혈, 요실금 및 질 건조증의 일일 증상 횟수를 내보냅니다.

### 구현됨

- 아직 전용 증상 렌더러가 없습니다.

### 계획됨

- 증상 달력 히트맵.
- 증상 빈도 순위표.
- 증상 동시 발생 행렬.
- 증상 악화 타임라인.
- 증상 상관관계 탐색기.
- 신체 계통별로 그룹화된 증상 대시보드.

---

## 기타 건강, 생활 방식 및 환경

Health.md는 자외선 노출, 일광 노출 시간, 낙상, 혈중 알코올, 알코올음료, 인슐린 투여, 양치질, 손 씻기, 수온 및 수중 깊이를 내보냅니다.

### 구현됨

- 아직 전용 생활 방식/환경 렌더러가 없습니다.

### 계획됨

- 일광 / 자외선 달력.
- 낙상 타임라인.
- 음주와 수면 / HRV 비교 차트.
- 인슐린 투여 추세.
- 양치질 및 손 씻기 연속 기록.
- 수온 / 수중 깊이 차트.

---

## 우선순위

1. 범용 스키마 인식 측정 항목 인프라.
2. 범용 추세, 막대 및 달력 히트맵 렌더러.
3. 활력 징후 제품군: 혈압, 혈당, 체온, 호흡 기능.
4. 신체 구성 대시보드.
5. 영양 대시보드.
6. 증상 히트맵, 순위표 및 상관관계 보기.
7. 생리 주기 / 생식 건강 달력.
8. 미량영양소 히트맵 및 RDA 격자.
9. 확장된 이동성 및 달리기 자세 대시보드.
10. 청각 및 생활 방식/환경 차트.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">마지막 업데이트: 2026-06-25</p>
