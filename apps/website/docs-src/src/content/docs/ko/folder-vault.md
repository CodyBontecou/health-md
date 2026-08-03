---
title: "폴더 및 보관함"
description: "Markdown 파일을 저장할 위치와 내보낸 파일이 기록될 하위 폴더의 이름을 지정하세요. 보관함은 iOS에서 선택한 폴더를 뜻하며, Obsidian, 파일 앱, iCloud Drive 또는 타사 파일 제공자를 모두 사용할 수 있습니다."
---

## 여기서 "보관함"의 의미
<p>앱에서는 실제 Obsidian 사용 여부와 관계없이 선택한 폴더를 통칭하여 <em>보관함</em>이라고 합니다. Obsidian을 사용한다면 Obsidian 보관함 루트를 지정하세요. 그렇지 않다면 iCloud Drive의 <code>Documents/Health</code>, 나의 iPhone 내 폴더 등 원하는 폴더를 선택하세요.</p>

## 선택기의 작동 방식
<p>보관함 행을 탭하면 iOS의 표준 문서 선택기(<code>UIDocumentPickerViewController</code>)가 열립니다. 폴더를 선택하면 iOS가 <em>보안 범위 URL</em>을 반환합니다. 이 지속성 핸들 덕분에 앱을 다시 실행해도 권한을 재요청하지 않고 해당 폴더에 접근할 수 있습니다. 앱은 이를 <code>UserDefaults</code>에 북마크로 저장합니다.</p>

## 하위 폴더 이름
<p>보관함을 선택하면 내보낸 파일을 저장할 하위 폴더의 이름을 지정하라는 메시지가 표시됩니다. 기본값은 <code>Health</code>입니다. 선택한 이름은 내보내는 모든 파일 경로의 접두사가 됩니다.</p>

<div class="doc-diagram folder-tree" aria-label="Health.md 내보내기 폴더 트리 예시">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← Health.md에서 지정한 이름</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>나중에 <em>설정 → Obsidian 보관함</em>에서 하위 폴더를 변경할 수 있습니다. 기존 파일은 이동되지 않습니다.</p>

## 앱 간 동작
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Obsidian 보관함 루트를 선택하세요. 내보낸 파일이 보관함 트리에 폴더로 표시되도록 하위 폴더를 예를 들어 <code>Health</code>로 설정하세요.</p></div>
<div class="option"><strong>iCloud Drive</strong><p>iCloud Drive 아래의 폴더를 선택하세요. 파일은 모든 Apple 기기에 자동으로 동기화됩니다.</p></div>
<div class="option"><strong>나의 iPhone</strong><p>파일 → 나의 iPhone에서 생성한 폴더를 선택하세요. 로컬에만 저장되며 동기화되지 않습니다.</p></div>
<div class="option"><strong>타사 제공자</strong><p>Dropbox, Google Drive, Working Copy처럼 파일 앱에 제공자로 표시되는 서비스는 모두 같은 방식으로 작동합니다.</p></div>
</div>

<div class="callout">
<strong>iOS의 특이 사항.</strong>
<p style="margin-top:6px;">iOS가 보안 범위 북마크를 취소하면(드문 경우이며 일반적으로 원래 폴더가 삭제되거나 이동되었을 때만 발생) 내보내기가 실패하기 시작합니다. 이 경우 <em>설정</em>에서 보관함을 다시 선택하세요.</p>
</div>

## 관련 문서

<div class="related">
  <a href="/ko/docs/onboarding/"><span>이전</span>온보딩 — 보관함을 처음 선택하는 단계입니다.</a>
  <a href="/ko/docs/export/"><span>다음</span>새 보관함으로 내보내기를 실행하세요.</a>
  <a href="/ko/docs/format/"><span>사용자 정의</span>형식 사용자 정의 — 하위 폴더 안에 파일이 기록되는 방식을 설정합니다.</a>
</div>
