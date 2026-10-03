---
title: "내 설정 공유"
description: "건강 데이터, 자격 증명, 구매, 기기 신뢰가 없는 개발 전용 v2 프로필 이동 흐름을 설명합니다."
---

<div class="availability preview"><strong>개발 미리보기 · 릴리스 미인증</strong><p>v2 계약은 실기기 상호 운용성과 접근성 검증이 끝날 때까지 pre-canonical 및 planned 상태입니다. 프로덕션에서 의존하지 마세요.</p></div>

Share My Setup은 하나 이상의 프로필을 묶습니다. 측정 항목, 형식, 이름, 구성, 대상 의도를 옮깁니다. 건강 데이터, 토큰, 실제 폴더 권한, 페어링, 구매, 기록, 작업은 포함하지 않습니다.

1. 원본에서 **설정 → Share My Setup**을 열고 v2 파일을 내보냅니다.
2. 대상에서 열고 각 프로필을 검토합니다.
3. **추가** 또는 **교체**를 선택합니다.
4. 폴더, 자격 증명이 있는 API, Mac을 로컬에서 다시 연결합니다.
5. 적용하고 작은 내보내기로 시험합니다.

트랜잭션은 원자적이며 한 번의 **실행 취소**를 제공합니다. 대상이 연결될 때까지 프로필은 차단되고 일정은 꺼진 상태로 가져옵니다. 현재 개발 소스는 `healthmd.shared_setup` v2만 쓰며 v1은 거부합니다.

<div class="related"><a href="/ko/docs/export-profiles/"><span>프로필</span>고정된 설정.</a><a href="/ko/docs/guides/platform-features/"><span>상태</span>플랫폼 QA.</a></div>
