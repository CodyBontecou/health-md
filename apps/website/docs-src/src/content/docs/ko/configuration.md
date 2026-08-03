---
title: 에이전트 구성
description: Health.md MCP 또는 CLI 인터페이스를 선택하고, Codex나 Claude 또는 다른 로컬 클라이언트를 구성한 다음, HealthKit을 클라우드 서비스로 라우팅하지 않고 페어링된 iPhone에 연결하세요.
---

출시된 Mac 앱에는 서명된 로컬 도우미 두 개가 포함되어 있습니다. 하나는 타입 지정 에이전트 도구용 `healthmd-mcp`이고, 다른 하나는 명시적인 CLI 워크플로용 `healthmd`입니다. iPhone 직접 연결 MCP를 지원하는 별도의 크로스 플랫폼 CLI는 첫 공개 패키지가 실물 기기 출시 QA를 마칠 때까지 미리보기로 문서화됩니다.

<div class="callout">
<strong>HealthKit은 iPhone에 그대로 유지됩니다.</strong>
<p style="margin-top:6px;">구성을 마치면 로컬 클라이언트가 Health.md의 제한된 인터페이스에 접근할 수 있습니다. 컴퓨터나 에이전트에 HealthKit 직접 접근 권한을 부여하지 않으며, 소스 라이브러리를 Health.md 클라우드에 업로드하지도 않습니다.</p>
</div>

## 인터페이스 선택

| 목표 | 시작 위치 | 다음 단계 |
|---|---|---|
| Codex 또는 Claude가 Mac에서 건강 데이터를 조회하고 차트로 표시하도록 허용 | stdio를 통한 번들 `healthmd-mcp` | [MCP 서버 및 도구](/ko/docs/mcp/) |
| Mac 스크립트에서 정규 JSON 또는 생성된 파일 내보내기 | 번들 `healthmd` CLI | [CLI](/ko/docs/cli/) |
| Mac 앱 없이 열려 있는 iPhone에 직접 연결 | 이식 가능한 직접 연결 CLI(**미리보기**) | [iPhone 직접 액세스](/ko/docs/cli-direct/) |
| 정확한 요청 및 응답 엔벨로프를 기준으로 개발 | 루프백 API 또는 공개 계약 | [루프백 API](/ko/docs/agent-api/) |
| 스키마, 레코드, 증거 또는 생성된 픽스처 파싱 | 버전이 지정된 참조 문서 | [데이터 계약](/ko/docs/reference/) |

백엔드와 전송 방식은 명시적으로 선택되며, Health.md는 iPhone 직접 접근에 실패해도 Mac 앱으로 암묵적으로 대체하지 않습니다.

## Mac 앱에서 Codex 사용

<div class="availability available">
<strong>현재 이용 가능 · 서명된 Mac 도우미</strong>
<p>Mac용 Health.md를 설치하고 <strong>CLI</strong> 화면을 연 다음, 앱이 <code>/Applications</code>에 없다면 표시된 번들 MCP 경로를 복사하세요.</p>
</div>

별도로 서명된 `healthmd-mcp` 도우미를 `~/.codex/config.toml`에 추가하세요.

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Codex를 다시 시작하고 `healthmd_doctor`를 호출한 다음, `healthmd_metrics`와 `healthmd_metric_chart` 같은 작은 타입 지정 도구 하나를 호출하세요. 번들 서버는 Mac 준비 상태, 암호화된 컨텍스트 새로 고침 작업, 증거 및 시각화를 포함한 21개 도구를 제공합니다.

## Mac에서 Claude Desktop 또는 Claude Code 사용

번들 도우미를 Claude Desktop의 MCP 구성이나 신뢰할 수 있는 Claude Code `.mcp.json`에 추가하세요.

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

구성을 변경한 후 클라이언트를 다시 시작하세요. 프로젝트 범위 구성에도 작업 공간 신뢰와 명시적인 서버 승인이 필요합니다. 도구에 최신 HealthKit 데이터가 필요할 때는 Mac과 iPhone 앱을 모두 열어 두세요.

## Mac의 모든 stdio MCP 클라이언트

하나의 로컬 프로세스를 구성하세요.

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

호스트가 stdin과 프로세스 수명 주기를 관리합니다. 도우미를 일반적인 대화형 명령으로 실행하거나 JSON-RPC 출력을 변경하는 셸로 감싸지 마세요. MCP `tools/list`를 사용하여 설치된 앱이 제공하는 정확한 스키마를 확인하세요.

## 이식 가능한 직접 연결 설정

<div class="availability preview">
<strong>미리보기 · 아직 공개 패키지로 제공되지 않음</strong>
<p>크로스 플랫폼 Rust CLI, <code>healthmd setup codex</code>, 동일 바이너리의 <code>healthmd mcp serve</code>, Linux/Windows 직접 페어링은 구현되었지만 첫 번째 품질 검증 공개 출시를 기다리고 있습니다.</p>
</div>

공개 후에는 `healthmd setup codex`가 Codex를 멱등적으로 구성하고 iPhone 직접 페어링을 시작합니다. 그전까지는 공개되지 않은 Homebrew, crates.io, 설치 프로그램 또는 GitHub 릴리스 URL에 의존하지 마세요. [iPhone 직접 연결 CLI](/ko/docs/cli-direct/) 페이지에서 준비 중인 전송 및 프로토콜 동작을 설명합니다.

## 명시적인 CLI 워크플로

정규 추출 또는 파일 중심 자동화에는 MCP 호스트에 큰 소스 본문을 전달하도록 요청하는 대신 `healthmd`를 직접 호출하세요.

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

번들 Mac 도우미와 독립 실행형 크로스 플랫폼 CLI는 이용 가능 여부와 문법이 서로 다릅니다. 명령을 무인 자동화에 복사하기 전에 [Health.md CLI](/ko/docs/cli/)를 검토하세요.

## 이식 가능한 페어링 및 준비 상태

<div class="availability preview">
<strong>미리보기 · 이식 가능한 직접 연결 워크플로</strong>
<p>이 단계에서는 향후 제공될 크로스 플랫폼 패키지를 설명합니다. 출시된 번들 Mac MCP 경로는 대신 Mac 앱의 기존 iPhone 연결을 사용합니다.</p>
</div>

직접 MCP 및 CLI 워크플로를 사용하려면 iPhone의 Health.md와 신뢰할 수 있는 일회성 페어링을 완료해야 합니다. 페어링은 인증된 암호화 채널과 macOS, Linux 또는 Windows의 네이티브 자격 증명 저장소를 사용합니다.

1. iPhone의 Health.md에서 **Direct CLI 액세스**를 활성화하세요.
2. `healthmd setup codex` 또는 `healthmd direct pair`에서 페어링을 시작하세요.
3. iPhone에서 제한된 페어링 요청을 승인하세요.
4. 쿼리 또는 내보내기를 시작하는 동안 Health.md를 포그라운드에 유지하세요.
5. 더 큰 작업을 시작하기 전에 MCP에서 `healthmd_doctor`를 호출하거나 이식 가능한 CLI에서 `healthmd status`를 실행하세요.

수동 IP, Tailscale, 포트, 신뢰할 수 있는 기기, 포그라운드 실행 및 복구에 관한 자세한 내용은 [iPhone 직접 액세스](/ko/docs/cli-direct/)를 참조하세요.

## 구성 경계

로컬 에이전트 구성은 다음 권한을 부여하지 **않습니다**.

- 임의의 HealthKit 읽기 또는 쓰기
- 임의의 파일 시스템 접근
- MCP를 통한 임의의 URL, 셸 명령, 프롬프트, 루트 또는 샘플링
- 누락 상태, 데이터 범위, 단위, 증거 또는 제한 사항을 숨길 권한
- 해당 승인을 받지 않고 생성된 파일 작업을 재개하거나 취소하거나 덮어쓸 권한

완전한 결과를 얻으려면 프로세스 성공 여부만 확인하지 말고 요청 범위, 데이터 범위, 순회, 제한 사항 및 소스 스키마를 검토하세요.

## 다음 단계

<div class="related">
  <a href="/ko/docs/mcp/"><span>도구 인터페이스</span>현재 이용 가능한 21개의 Mac 도구, 이식 가능한 17개 도구 미리보기, MCP Apps, 스키마, 페이징, 내보내기 및 샌드박스 경계를 검토하세요.</a>
  <a href="/ko/docs/agent-queries/"><span>첫 번째 질문</span>타입 지정 측정 항목, 수면, 운동, 비교, 데이터 범위 및 증거 워크플로를 실행하세요.</a>
  <a href="/ko/docs/cli-extract/"><span>정규 데이터</span>큰 본문을 채팅에 넣지 않고 선택한 스키마 v7 문서와 소스 레코드를 추출하세요.</a>
  <a href="/ko/docs/reference/"><span>계약</span>버전이 지정된 데이터 구조, 필드 목록, 생성된 픽스처 및 통합 방법을 살펴보세요.</a>
</div>
