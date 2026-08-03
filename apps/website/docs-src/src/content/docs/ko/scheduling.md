---
title: "예약된 내보내기"
description: "매일 또는 매주, 선택한 시간에 내보내기를 자동으로 실행합니다. iOS 백그라운드 작업을 사용하며, 기기가 잠겨 있을 때는 예약된 로컬 알림을 대체 수단으로 사용합니다."
---

## 예약 탭
<p>예약 탭은 설정 패널이 아니라 상태 화면입니다. 다음 내용을 한눈에 확인할 수 있습니다.</p>
<ul>
<li>예약이 켜져 있는지 또는 꺼져 있는지</li>
<li>다음 예약 실행 시간(있는 경우)</li>
<li>마지막 실행 결과</li>
</ul>
<p><em>예약 설정</em> 또는 <em>예약 관리</em> 버튼 하나로 세부 정보 보기를 열 수 있습니다.</p>

## 예약 설정
<div class="options">
<div class="option"><strong>예약된 내보내기 활성화</strong><p>상단의 마스터 토글입니다. 끄면 백그라운드 실행과 알림이 모두 중지됩니다.</p></div>
<div class="option"><strong>빈도</strong><p>매일, 매주 또는 매월 실행할 수 있습니다. 매일 내보내기는 전날을, 매주 내보내기는 이전 7일을, 매월 내보내기는 이전 30일을 포함합니다.</p></div>
<div class="option"><strong>시간</strong><p>시와 분을 설정합니다. iOS는 이를 보장된 실행 시각이 아니라 목표 시간으로 취급합니다. 아래의 제한 사항을 확인하세요.</p></div>
</div>

## 내보내기 기록
<p>예약 화면 하단의 목록에는 예약된 모든 실행과 그 결과가 기록됩니다. 행을 탭하면 세부 정보를 볼 수 있습니다. 실패한 실행에는 해당 날짜 범위만 다시 실행하는 <em>재시도</em> 버튼이 표시됩니다.</p>

## iOS 예약의 실제 작동 방식
<div class="doc-diagram">
  <div class="flow-steps" aria-label="예약된 내보내기의 대체 실행 흐름">
    <span><strong>1. 목표 시간</strong>Health.md가 선택한 시간 전후에 앱을 깨우도록 iOS에 요청합니다.</span>
    <span><strong>2. 백그라운드 시도</strong>기기를 사용할 수 있으면 iOS가 백그라운드 새로 고침 작업을 실행합니다.</span>
    <span><strong>3. 잠금 시 대체 수단</strong>HealthKit을 사용할 수 없으면 Health.md가 알림을 보냅니다.</span>
    <span><strong>4. 탭하여 완료</strong>알림을 열면 앱이 HealthKit을 읽고 내보내기를 실행할 수 있습니다.</span>
  </div>
</div>

<div class="callout">
<strong>알아 두어야 할 iOS 제한 사항</strong>
<p style="margin-top:6px;">기기가 잠겨 있는 동안에는 HealthKit 데이터를 읽을 수 없습니다. 예약된 내보내기는 <code>BGAppRefreshTask</code>를 통해 실행되며, iOS는 사용 패턴에 따라 적절한 시점을 골라 작업을 예약합니다. 따라서 설정한 시간은 목표일 뿐 실행을 보장하지 않습니다. 대체 수단으로, 예약 시간에 기기가 잠겨 있으면 앱이 로컬 알림을 보냅니다. 알림을 탭하면 내보내기가 실행됩니다.</p>
</div>
<ul>
<li>예약 시간은 대략적인 시간입니다. iOS가 작업을 더 일찍 또는 늦게 실행할 수 있으며, 기기의 전원이 꺼져 있거나 연결이 끊어진 경우 건너뛸 수도 있습니다.</li>
<li>휴대전화를 매일 비슷한 시간에 정기적으로 전원에 연결하고 잠금 해제하면 예약된 내보내기가 가장 원활하게 작동합니다.</li>
<li>기기가 잠겨 있어 내보내기가 실패했다면 iPhone의 잠금을 해제하고 알림을 탭하세요. 그러면 앱이 HealthKit에 접근하여 내보내기를 실행합니다.</li>
</ul>

## 프로그래밍 방식으로 제어
<p>단축어의 <em>예약된 내보내기 켜기 또는 끄기</em> 인텐트를 사용하여 예약을 켜거나 끌 수 있습니다. 예시는 <a href="/ko/docs/shortcuts/">단축어</a>를 참조하세요.</p>

## 관련 문서

<div class="related">
  <a href="/ko/docs/export/"><span>수동</span>내보내기 — 일회성 날짜 범위에 사용합니다.</a>
  <a href="/ko/docs/shortcuts/"><span>자동화</span>단축어 — 자동화에서 예약을 전환합니다.</a>
  <a href="/ko/docs/sync/"><span>기기 간 연동</span>Mac 동기화 — Mac에서도 예약합니다.</a>
</div>
