---
title: "Mac 동기화"
description: "macOS 컴패니언 앱을 로컬 대상으로 사용하세요. iPhone에서 HealthKit 데이터와 설정을 캡처하면 Mac이 요청된 파일을 렌더링하고 기록합니다."
---

## 개요
<p>Mac 동기화를 사용하면 Mac이 HealthKit 리더가 되지 않고도 내보내기를 생성할 수 있습니다. Apple Health 데이터의 기준 원본은 계속 iPhone입니다. iPhone에서 선택한 일별 데이터와 정확한 설정 스냅샷을 캡처한 다음 해당 작업을 Mac으로 전송합니다. Mac은 공용 내보내기 모듈로 경로를 계획하고, 요청된 형식을 렌더링하며, 생성된 파일을 선택한 대상 폴더에 기록합니다.</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Mac 동기화 내보내기 흐름">
    <span><strong>iPhone</strong>HealthKit 데이터를 캡처하고 적용된 설정의 스냅샷을 생성합니다.</span>
    <span><strong>로컬 네트워크</strong>버전이 지정된 작업을 근처의 Mac 앱으로 전송합니다.</span>
    <span><strong>Mac</strong>선택한 형식을 렌더링하여 선택한 폴더에 기록합니다.</span>
    <span><strong>보관함</strong>Obsidian, iCloud Drive 또는 로컬 폴더로 최종 내보내기 결과가 전달됩니다.</span>
  </div>
</div>

## 활성화 방법
<ol>
<li>macOS 앱을 설치하고 엽니다.</li>
<li>Mac에서 Health.md가 쓰기 권한을 갖도록 대상 폴더를 선택합니다.</li>
<li>iPhone에서 동기화 탭을 열고 Mac 연결을 활성화합니다.</li>
<li>iPhone의 내보내기 탭으로 돌아가 <em>연결된 Mac</em>을 선택하고 내보내기를 구성한 다음 내보내기를 탭합니다.</li>
</ol>

## 전송되는 항목
<ul>
<li>날짜 범위와 적용된 설정을 설명하는 버전이 지정된 내보내기 요청</li>
<li>iPhone에서 HealthKit 데이터를 캡처하는 동안 전달되는 진행 상황 및 기능 정보 메시지</li>
<li>파일 쓰기 작업을 위해 캡처된 일별 데이터와 정확한 설정 스냅샷을 전달하는 제한된 체크섬 검증 프레임</li>
<li>구조화된 완료, 부분 완료, 실패, 거부 또는 사용 불가 결과</li>
</ul>
<p>계정이나 원격 건강 데이터 클라우드는 필요하지 않습니다. 근거리 동기화는 암호화된 Multipeer Connectivity를 사용하며, 수동 IP/Tailscale은 페어링된 암호화 Network.framework 전송을 사용합니다. 두 기기가 서로 연결될 수 있어야 하며, HealthKit 리더는 계속 iPhone입니다.</p>

## 사용 시점
<div class="options">
<div class="option"><strong>데스크톱 전용 보관함</strong><p>Obsidian 보관함이 Mac에만 있다면 iPhone HealthKit에서 Mac 파일로 데이터를 옮기는 깔끔한 방법입니다.</p></div>
<div class="option"><strong>대규모 과거 데이터 채우기</strong><p>iPhone에서 HealthKit 읽기 및 내보내기 구성을 처리하는 동안 최종 파일은 데스크톱 디스크에 보관하세요.</p></div>
<div class="option"><strong>로컬 보관 워크플로</strong><p>macOS에서 백업, 버전 관리 또는 인덱싱되는 폴더에 직접 기록합니다.</p></div>
</div>

<div class="callout">
<strong>로컬 네트워크가 필요합니다.</strong>
<p style="margin-top:6px;">두 기기가 가까이 있어야 하며 로컬 네트워크 사용이 허용되어야 합니다. 셀룰러 네트워크에만 연결된 iPhone은 Mac 대상을 찾을 수 없습니다. 준비 상태에 Mac에서 조치가 필요하다고 표시되면 Mac 앱을 다시 열고 대상 폴더를 다시 선택하세요.</p>
</div>

## Mac 동기화와 Direct CLI 액세스는 별개의 기능입니다

Mac 동기화는 대상 내보내기 및 암호화된 에이전트 컨텍스트를 위해 iPhone과 Health.md Mac 앱을 페어링합니다. Direct CLI 액세스는 별도의 신뢰 도메인을 통해 iPhone과 명령줄 설치를 페어링합니다. 직접 모드에서는 Mac 앱 없이 원시 데이터나 생성된 파일을 내보낼 수 있지만, Mac의 암호화된 쿼리 인덱스나 MCP는 사용할 수 없습니다.

별도의 iPhone 설정을 활성화하기 전에 [iPhone 직접 CLI](/ko/docs/cli-direct/)를 참조하세요.

## 관련 문서

<div class="related">
  <a href="/ko/docs/macos/"><span>데스크톱</span>macOS 앱 — Mac에서 내보내기, 예약, 기록을 관리합니다.</a>
  <a href="/ko/docs/scheduling/"><span>워크플로</span>예약 — 반복되는 내보내기를 자동화합니다.</a>
  <a href="/ko/docs/cli-direct/"><span>별도의 신뢰</span>iPhone 직접 CLI — Mac 앱을 통해 작업을 라우팅하지 않고 CLI를 페어링합니다.</a>
  <a href="/ko/docs/reference/connected-mac-iphone-protocol/"><span>프로토콜</span>연결된 Mac–iPhone 참조 — 기능, 요청, 제한된 전송 및 결과.</a>
</div>
