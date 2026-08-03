---
title: "API 엔드포인트"
description: "선택한 Apple Health JSON을 iPhone에서 자체 HTTP(S) 엔드포인트로 직접 전송합니다."
---

<p>API 엔드포인트는 Health.md 데이터를 자체 서버, 웹훅, 데이터베이스, 대시보드 또는 자동화로 보내려는 사용자를 위한 내보내기 대상입니다. Apple Health 데이터는 계속 iPhone에서 읽으며, 파일을 쓰는 대신 구성한 엔드포인트로 JSON을 POST합니다.</p>

<div class="callout">
<strong>개인정보 보호 안내.</strong>
<p style="margin-top:6px;">이 대상은 선택한 건강 데이터를 입력한 URL로 의도적으로 전송합니다. 직접 관리하거나 신뢰하는 엔드포인트를 사용하고, HTTPS를 우선하며, 서비스에 실제로 필요한 측정 항목만 선택하세요.</p>
</div>

## 대상 설정

<ol>
<li>iPhone에서 Health.md를 엽니다.</li>
<li><strong>내보내기</strong>로 이동합니다.</li>
<li><strong>내보내기 대상</strong>에서 <strong>API 엔드포인트</strong>를 선택합니다.</li>
<li><code>https://api.example.com/healthmd/ingest</code>와 같은 URL을 입력합니다.</li>
<li>선택 사항: bearer 토큰을 입력합니다. Health.md는 이를 키체인에 저장합니다.</li>
<li><strong>완료</strong>를 탭하고 날짜 범위와 측정 항목을 선택한 다음 <strong>내보내기</strong>를 탭합니다.</li>
</ol>

<p>일반 토큰을 입력하면 Health.md는 이를 <code>Authorization: Bearer &lt;token&gt;</code>로 전송합니다. 값이 이미 <code>Bearer </code> 또는 <code>Basic </code>으로 시작하면 Health.md는 입력한 그대로 전송합니다.</p>

## 페이로드 구조

<p>Health.md는 내보내기 작업마다 하나의 POST를 전송합니다. 본문은 독립적으로 버전이 지정된 <code>healthmd.api_export</code> API 엔벨로프이며, 공개 스키마 v7 <code>healthmd.health_data</code> 일별 레코드를 포함합니다. API 엔벨로프 v1은 일별 레코드를 전달하며, v2는 일별 레코드 스키마를 변경하지 않고 제공자 사이드카도 추가로 전달할 수 있습니다.</p>

<div class="options">
<div class="option"><strong><code>records</code></strong><p>요청 범위에 보관된 완전한 일별 스키마 v7 객체입니다. 쿼리 매니페스트가 증거인 complete-empty 레코드도 포함합니다.</p></div>
<div class="option"><strong><code>failed_date_details</code></strong><p>일별 문서를 보관하기 전에 실패한 날짜입니다.</p></div>
<div class="option"><strong><code>daily_record_schema_version</code></strong><p><code>records</code> 내부의 일별 스키마 버전입니다. API 엔벨로프 버전과 독립적으로 올라갑니다.</p></div>
<div class="option"><strong>제공자 사이드카</strong><p>연결된 제공자가 활성화된 경우 자체 스키마와 식별 규칙을 사용하는 조건부 v2 외부 레코드입니다.</p></div>
</div>

<p>프로덕션에서 생성된 전체 <a href="/docs/reference/generated/automation/api-export-v1.json">API v1 엔벨로프</a>와 <a href="/docs/reference/generated/automation/api-export-v2-provider-sidecar.json">API v2 제공자 사이드카 엔벨로프</a>를 살펴보세요. <a href="/ko/docs/reference/api-and-cli/">API 및 CLI 계약</a>에는 모든 필드, 버전 경계 및 허용 규칙이 설명되어 있습니다.</p>

## 엔드포인트 요구 사항

<div class="options">
<div class="option"><strong>메서드</strong><p><code>POST</code>를 허용합니다.</p></div>
<div class="option"><strong>콘텐츠 유형</strong><p><code>application/json</code>을 허용합니다.</p></div>
<div class="option"><strong>성공</strong><p>페이로드를 안전하게 수락한 뒤 <code>2xx</code> 상태를 반환합니다.</p></div>
<div class="option"><strong>실패</strong><p>거부된 요청에는 <code>4xx</code> 또는 <code>5xx</code>를 반환합니다. 가능한 경우 Health.md가 짧은 응답 미리보기를 표시합니다.</p></div>
</div>

<p>안정적으로 수집하려면 엔드포인트를 날짜별로 멱등하게 만드세요. 사용자는 측정 항목을 변경하거나 서버 오류를 수정한 뒤 동일한 내보내기 범위를 반복할 수 있습니다.</p>

## 팁

<ul>
<li>긴 과거 데이터를 업로드하기 전에 하루 분량으로 테스트하세요.</li>
<li>소스 완전성이 중요하면 무손실 건강 레코드를 활성화된 상태로 유지하세요. 경로, 임상 문서, ECG 또는 첨부 파일이 밀집된 경우 날짜 범위를 줄이세요.</li>
<li>페이로드를 저장하기 전에 서버에서 토큰을 검증하세요.</li>
<li><code>records[].date</code>를 일별 기본 키로 사용하세요.</li>
<li>간결한 오류 본문을 반환하세요. Health.md는 짧은 미리보기만 표시합니다.</li>
</ul>

## 문제 해결

| 문제 | 일반적인 원인 | 해결 방법 |
|---|---|---|
| API 대상이 준비되지 않음 | URL이 비어 있거나 유효하지 않음 | API 엔드포인트 설정을 다시 열고 유효한 HTTP(S) URL을 입력하세요. |
| HTTP 401 또는 403 | 토큰이 없거나 거부됨 | 토큰 또는 서버 인증 규칙을 업데이트하세요. |
| HTTP 404 | URL 경로가 잘못됨 | 서버의 라우트를 확인하세요. |
| HTTP 413 | 페이로드가 너무 큼 | 내보낼 날짜 수를 줄이세요. 수신 측에서 정규 소스 레코드가 필요하지 않을 때만 요약 전용 출력을 사용하세요. |
| 일부 날짜가 누락됨 | 해당 날짜에 활성화된 HealthKit 데이터가 없음 | <code>failed_date_details</code>와 측정 항목 선택을 확인하세요. |

## 관련 문서

<div class="related">
  <a href="/ko/docs/export/"><span>소스</span>내보내기 — 대상을 선택하고 날짜 범위를 지정하여 수동 내보내기를 실행합니다.</a>
  <a href="/ko/docs/reference/api-and-cli/"><span>스키마</span>API 및 CLI 참조 — 정확한 엔벨로프, 버전, 실패 동작 및 생성된 예제입니다.</a>
  <a href="/ko/docs/format/"><span>출력</span>형식 사용자 정의 — JSON, CSV, Markdown, 단위 및 필드입니다.</a>
</div>
