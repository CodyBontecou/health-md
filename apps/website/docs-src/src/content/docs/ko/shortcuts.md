---
title: "단축어 및 App Intents"
description: "8개의 App Intent로 Siri, 단축어 앱, 집중 모드 필터, 자동화 및 AppIntent 지원 호스트에서 내보내기를 실행하고, 요약을 가져오고, 예약을 켜거나 끌 수 있습니다."
---

## 사용 가능한 Intent
<div class="options">
<div class="option"><strong>어제의 건강 데이터 내보내기</strong><p>매개변수가 없는 단축어입니다. 별도 안내 없이 어제 데이터만 내보내는 빠른 경로이며, 수동 내보내기와 동일한 엔진을 사용합니다. 선택적 <em>프로필</em> 매개변수(<a href="#profiles">내보내기 프로필</a> 참고).</p></div>
<div class="option"><strong>특정 날짜의 건강 데이터 내보내기</strong><p>단일 <em>날짜</em> 매개변수를 사용합니다. 시간은 무시됩니다. 캘린더 기반 자동화에 유용합니다. 선택적 <em>프로필</em> 매개변수.</p></div>
<div class="option"><strong>날짜 범위의 건강 데이터 내보내기</strong><p><em>시작 날짜</em>와 <em>종료 날짜</em> 매개변수를 사용하며 양쪽 날짜가 모두 포함됩니다. 과거 데이터를 채울 때 사용하세요. 선택적 <em>프로필</em> 매개변수.</p></div>
<div class="option"><strong>최근 N일의 건강 데이터 내보내기</strong><p><em>일수</em> 매개변수(1–366)를 사용합니다. 어제까지를 대상으로 합니다. 기본값은 7입니다. &quot;매주 일요일에 최근 7일 내보내기&quot;와 같은 자동화에 적합합니다. 선택적 <em>프로필</em> 매개변수.</p></div>
<div class="option"><strong>특정 날짜의 건강 요약 가져오기</strong><p>보관함에 아무것도 쓰지 않고 걸음 수, 활동 칼로리, 수면, 심박수로 구성된 구조화된 스냅샷을 반환합니다. 단축어에서 값을 다른 앱으로 전달할 때 사용하세요.</p></div>
<div class="option"><strong>마지막 내보내기 상태 가져오기</strong><p>가장 최근에 기록된 내보내기의 타임스탬프, 성공 상태, 일수 및 실패 사유를 반환합니다. 잠긴 기기에서의 요청은 재시도할 때까지 대기 상태로 유지되므로, 대기 중에는 현재 상태로 반환되지 않습니다.</p></div>
<div class="option"><strong>예약된 내보내기 켜기 또는 끄기</strong><p>불리언 매개변수를 사용합니다. 예약을 일시 중지하고(예: 휴가 집중 모드) 나중에 다시 시작할 때 사용하세요.</p></div>
<div class="option"><strong>건강 데이터 내보내기</strong><p>일반 내보내기입니다. 앱 내 내보내기 모달에 마지막으로 설정된 날짜 범위를 사용합니다. 사용 빈도는 낮으며, 일반적으로 날짜 범위를 지정하는 Intent가 더 명확합니다. 선택적 <em>프로필</em> 매개변수.</p></div>
</div>

<a id="profiles"></a>
## 내보내기 프로필
<p>다섯 개의 내보내기 인텐트 모두 선택적 <em>프로필</em> 매개변수를 받습니다. 비워 두면 앱의 현재 내보내기 설정으로 실행되고, 저장된 프로필 이름을 전달하면 앱이 현재 표시하는 것과 관계없이 해당 프로필의 동결된 구성(지표 선택, 형식, 대상)으로 실행됩니다.</p>
<div class="callout">
<strong>매개변수 없는 기존 단축어 사용자에게 알립니다.</strong>
<p style="margin-top:6px;">앱에서 첫 내보내기 프로필을 만들면 <em>프로필</em>이 설정되지 않은 단축어는 앱의 현재 설정 대신 <em>활성</em> 프로필의 저장된 설정으로 내보냅니다. 이전 동작에 의존하는 경우 단축어를 특정 프로필에 고정하거나(또는 프로필을 0개로 유지) 명시적으로 유지하세요. 더 이상 존재하지 않는 프로필 이름은 잘못된 내보내기 대신 명확한 오류로 실패합니다.</p>
</div>
## 찾는 방법
<p>iOS 또는 macOS에서 단축어 앱을 여세요. <em>+</em> 버튼을 탭해 새 단축어를 만든 다음 &quot;Health.md&quot; 또는 위에 나열된 Intent 제목을 검색하세요. 각 Intent는 <em>건강</em> 카테고리에 있습니다.</p>
<p>대부분의 Intent에는 <code>openAppWhenRun = false</code>가 설정되어 있어 앱을 열거나 UI를 표시하지 않고 백그라운드에서 실행됩니다. 자동화, 집중 모드 필터, ‘Siri야’ 호출 및 동작 버튼에서 사용할 수 있습니다.</p>

<div class="callout">
<strong>잠긴 상태에서 실행해도 HealthKit의 잠금은 해제되지 않습니다.</strong>
<p style="margin-top:6px;">Apple은 iPhone이 잠겨 있는 동안 HealthKit 데이터를 보호하며, <a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">잠긴 후 약 10분이 지나면 앱의 접근을 차단합니다</a>. <em>잠겨 있을 때 실행 허용</em>을 사용하면 단축어가 동작을 시작할 수 있지만 HealthKit 데이터 보호를 우회하지는 않습니다. 단축어의 Health.md 앱 콘텐츠 권한도 이를 우회하지 않습니다.</p>
<p>HealthKit을 사용할 수 없으면 Health.md는 요청된 날짜를 대기 상태로 보존하고 <em>건강 데이터 내보내기에 주의 필요</em> 알림을 보냅니다. iPhone의 잠금을 해제한 다음 알림을 탭하거나 Health.md를 열어 다시 시도하세요. 휴대전화가 잠긴 상태로 유지되는 동안에는 완전 무인 내보내기를 보장할 수 없습니다.</p>
</div>

<a id="recipe-nightly-export-with-confirmation"></a>
## 사용법: 완료 확인이 포함된 일일 내보내기
<ol>
<li><strong>개인용 자동화</strong> → <em>특정 시간</em> → 오전 8:00처럼 잠금 해제된 iPhone을 평소 사용하는 시간을 선택합니다.</li>
<li><em>어제의 건강 데이터 내보내기</em> Intent를 추가합니다.</li>
<li><em>마지막 내보내기 상태 가져오기</em> Intent를 추가합니다.</li>
<li>결과를 포함하는 <em>알림 표시</em>를 추가합니다.</li>
</ol>
<p><strong>대기 상태 참고:</strong> <em>마지막 내보내기 상태 가져오기</em>는 가장 최근에 기록된 내보내기 기록 항목을 읽습니다. 이번 실행에서 잠긴 HealthKit 데이터가 감지되면 대기 중인 요청을 재시도할 때까지 이전 내보내기가 계속 표시될 수 있습니다. 대기 중인 작업은 Health.md의 복구 알림으로 가장 확실하게 확인할 수 있습니다.</p>

## 사용법: 과거 데이터 한 번에 채우기
<ol>
<li>단축어를 만듭니다.</li>
<li><em>날짜 범위의 건강 데이터 내보내기</em>에서 시작 = 2024-01-01, 종료 = 2024-12-31로 설정합니다.</li>
<li>단축어에서 실행합니다. 1년 전체를 순회하며 하루에 파일 하나를 씁니다. 연간 전체 데이터를 처리하는 데 몇 분이 걸릴 수 있습니다.</li>
</ol>

## 사용법: 휴가 중 예약 일시 중지
<ol>
<li><strong>집중 모드 필터</strong>: <em>휴가</em> 집중 모드가 켜지면 활성화 = false로 설정한 <em>예약된 내보내기 켜기 또는 끄기</em>를 실행합니다.</li>
<li>집중 모드가 꺼지면 활성화 = true로 설정해 다시 실행합니다.</li>
</ol>

<div class="callout">
<strong>권한 부여가 필요합니다.</strong>
<p style="margin-top:6px;">Intent는 앱 내 HealthKit 권한과 보관함 선택을 그대로 사용합니다. 이 기기에서 앱을 한 번 이상 열어 설정하지 않았다면 명확한 오류와 함께 실패합니다.</p>
</div>

## 관련 문서

<div class="related">
  <a href="/ko/docs/scheduling/"><span>연결 기능</span>예약 — 전환 Intent에 해당하는 앱 내 기능입니다.</a>
  <a href="/ko/docs/export/"><span>연결 기능</span>내보내기 — 날짜 범위 Intent에 해당하는 앱 내 기능입니다.</a>
</div>
