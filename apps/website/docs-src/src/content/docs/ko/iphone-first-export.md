---
title: "첫 iPhone 내보내기"
description: "Apple Health 접근을 허용하고, 파일 앱의 대상 폴더를 선택하고, Health.md 출력을 미리 본 다음, 작은 첫 iPhone 내보내기를 실행해 작성된 파일을 확인합니다."
---

측정 항목, 형식 또는 자동화를 변경하기 전에 이 안내에 따라 작고 검증 가능한 내보내기를 생성하세요. Health.md는 iOS에서 승인한 Apple Health 카테고리만 읽고 생성된 파일을 선택한 폴더에 저장합니다.

<div class="availability available">
<strong>현재 이용 가능 · iPhone용 Health.md</strong>
<p>첫 내보내기는 무료 허용량으로 이용할 수 있습니다. 예약 및 기타 유료 기능은 나중에 구성할 수 있습니다.</p>
</div>

## 시작하기 전에

다음이 필요합니다.

- Apple Health 데이터가 있는 iPhone에 설치된 Health.md
- 하나 이상의 Apple Health 카테고리를 읽을 수 있는 권한
- iCloud Drive, 나의 iPhone 또는 Obsidian 보관함과 같이 쓰기 가능한 파일 대상 폴더

가장 빠르게 처음 실행하려면 기본 측정 항목과 Markdown 출력을 유지하세요. 사용 가능한 전체 기록 대신 **어제** 또는 하루짜리 다른 기간으로 시작하세요.

## 1. iPhone 설정 완료하기

처음 실행할 때 **설정 시작**을 탭하고 7단계 온보딩을 완료하세요. 원하는 건강 카테고리의 접근을 허용하고, 샘플 출력을 검토하고, 파일 앱에서 폴더를 선택한 다음 **준비 완료** 단계까지 계속 진행하세요. 잠금 해제 단계가 나타나면 무료 허용량으로 계속할 수 있습니다.

온보딩을 이미 완료했다면 **내보내기** 탭을 열고 Apple Health와 로컬 폴더가 준비되었는지 확인하세요. 폴더 컨트롤을 사용하여 없거나 접근할 수 없는 대상 폴더를 교체하세요.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="온보딩 스크린샷을 전체 크기로 열기">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="7단계 중 1단계에서 설정 시작 버튼이 표시된 Health.md 온보딩 시작 화면. 화면은 영어로 되어 있습니다." />
  </a>
  <figcaption>설정 시작에서는 접근 권한을 요청하기 전에 로컬 아카이브, 예약된 메모 및 폴더 모델을 소개합니다. 이 온보딩 스크린샷은 영어로 되어 있습니다.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="설정 필요 스크린샷을 전체 크기로 열기">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="건강 연결이 해제되어 있고, 폴더 선택을 사용할 수 있으며, iPhone 로컬 폴더와 날짜 범위 버튼이 표시된 Health.md 내보내기 탭. 화면은 영어로 되어 있습니다." />
  </a>
  <figcaption>준비 상태 배지는 누락된 건강 및 폴더 설정을 명확하게 보여 줍니다. 이 시뮬레이터 캡처는 두 요구 사항이 모두 완료되지 않은 상태를 의도적으로 보여 주며 화면은 영어로 되어 있습니다.</figcaption>
</figure>
</div>

## 2. 소규모 내보내기 선택하기

내보내기 탭에서 다음을 수행하세요.

1. 대상으로 **iPhone 로컬 폴더**를 선택합니다.
2. **어제** 또는 하루짜리 사용자 지정 기간을 선택합니다.
3. 첫 실행에서는 기본 측정 항목 선택을 유지합니다.
4. **Markdown**을 선택한 상태로 유지합니다. 기본 경로가 정상적으로 작동한 후 CSV, JSON 또는 Obsidian Bases를 추가할 수 있습니다.

짧은 기간을 사용하면 권한, 비어 있는 카테고리 및 대상 폴더 문제를 더 쉽게 이해할 수 있습니다. 또한 오래 실행되는 첫 요청을 실패한 내보내기로 오인하는 일을 방지할 수 있습니다.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/ko/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="측정 항목 선택 스크린샷을 전체 크기로 열기">
    <img src="/docs/assets/docs/ko/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="219개 중 217개의 측정 항목과 표준 항목이 활성화되고, 검색 필드와 펼칠 수 있는 수면, 활동 및 심장 카테고리가 표시된 건강 항목 화면." />
  </a>
  <figcaption>측정 항목 총수는 설치된 앱 버전과 권한에 따라 달라집니다. 이 현지화된 화면에는 219개 중 217개의 측정 항목과 표준 항목이 활성화되어 있지만, 첫 내보내기를 위해 이 수만큼 활성화할 필요는 없습니다.</figcaption>
</figure>

## 3. 작성하기 전에 미리보기

**미리보기**를 탭하세요. 미리보기에는 Apple Health 접근 권한이 필요하지만 쓰기 가능한 로컬 폴더는 필요하지 않으므로, 읽기 권한 문제와 파일 문제를 구분하는 데 유용합니다.

미리보기에 다음 항목이 표시되는지 확인하세요.

- 요청한 날짜
- 예상한 측정 항목 이름과 단위
- 임의의 0으로 채우지 않고 명시한 누락 또는 사용 불가 상태
- 선택한 형식과 파일 이름 구조

날짜, 측정 항목 또는 형식을 조정해야 한다면 내보내기 탭으로 돌아가세요.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/ko/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="내보내기 미리보기 스크린샷을 전체 크기로 열기">
    <img src="/docs/assets/docs/ko/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="하루짜리 Markdown 내보내기 예상치, 집계 기간, 대상 폴더 및 생성된 파일 이름을 보여 주는 Health.md 내보내기 미리보기." />
  </a>
  <figcaption>미리보기는 출력 검토와 파일 작성을 분리합니다. 이 재현 가능한 문서용 캡처는 샘플 건강 데이터를 사용하며 선택된 보관함이 없음을 명확히 보여 줍니다.</figcaption>
</figure>

## 4. 내보내고 확인하기

**데이터 내보내기**를 탭하세요. 설정이 완료되지 않았다면 Health.md는 파일을 부분적으로 쓰기 시작하지 않고 누락된 건강 또는 폴더 요구 사항을 알려 줍니다.

완료 후 다음을 수행하세요.

1. 앱 내 결과에서 파일별 작성, 건너뜀 및 실패 상태를 검토합니다.
2. 파일 앱을 열고 선택한 폴더로 이동합니다.
3. 생성된 파일 하나를 열고 날짜, 단위 및 프론트매터를 확인합니다.
4. 문제 해결 시 결과 세부 정보를 보관하세요. 버튼이 유휴 상태로 돌아온 것만으로 성공했다고 판단하지 마세요.

<div class="callout">
<strong>선택한 날짜에 데이터가 없나요?</strong>
<p style="margin-top:6px;">활동 또는 수면 데이터가 있다고 알고 있는 날짜를 선택한 다음 건강 접근 권한과 측정 항목 선택을 검토하세요. 접근이 허용된 기간에 데이터가 없는 것과 전송 또는 쓰기 실패는 서로 다릅니다.</p>
</div>

## 다음 단계

<div class="related">
  <a href="/ko/docs/metrics/"><span>데이터 선택</span>Apple Health 측정 항목을 검색하고 카테고리 또는 특별 권한을 조정합니다.</a>
  <a href="/ko/docs/format/"><span>출력 구성</span>형식, 날짜, 단위, 프론트매터, 템플릿 및 파일 이름을 구성합니다.</a>
  <a href="/ko/docs/scheduling/"><span>자동화</span>수동 실행 한 번을 확인한 후 반복 내보내기를 예약합니다.</a>
  <a href="/ko/docs/folder-vault/"><span>대상 폴더 문제 해결</span>파일 제공자, 폴더 접근 및 복구 방법을 알아봅니다.</a>
</div>
