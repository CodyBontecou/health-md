---
title: "Health.md MCP 서버 및 App"
description: "로컬 샌드박스 MCP App을 통해 Codex 또는 Claude로 범위가 지정된 Apple Health 분석을 실행하고 네이티브 차트를 렌더링하며 영속 Health.md 내보내기를 시작합니다."
---

Mac용 Health.md에는 서명된 `healthmd-mcp` stdio 도우미가 포함되어 있습니다. Codex, Claude 및 기타 MCP 호스트가 열린 Mac 앱을 통해 사실 기반 Apple Health 데이터를 쿼리하고, 시각화를 렌더링하고, 암호화된 로컬 컨텍스트를 새로 고치며, 승인된 영속 내보내기를 실행할 수 있습니다.

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>현재 사용 가능 · Mac용 Health.md</strong>
<p>번들 서버는 고정된 도구 21개를 제공합니다. 서버 자체는 HealthKit, 내보내기 폴더, 보안 범위 북마크 또는 임의 파일을 읽지 않습니다.</p>
</div>

<div class="availability preview">
<strong>미리보기 · 이식 가능한 직접 MCP</strong>
<p>macOS, Linux 및 Windows용 별도의 19개 도구 <code>healthmd mcp serve</code> 토폴로지가 구현되었지만 아직 공개 패키지로 제공되지 않습니다. 클라우드가 필요 없는 <code>serve-read-only</code> 진입점은 로컬 페어링 후 준비 상태/쿼리 도구 13개만 제공합니다. 이 페이지의 이식 가능한 버전 전용 명령은 미리보기로 표시됩니다.</p>
</div>

## 요구 사항

- 설치되어 열려 있는 Mac용 Health.md
- 업데이트 도구나 내보내기가 새 HealthKit 작업을 시작할 때 연결된 iPhone에서 열려 있는 Health.md
- stdio를 지원하는 로컬 MCP 호스트
- **Mac용 Health.md → CLI**에 표시되는 서명된 도우미 경로

일반 도우미 경로는 `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`입니다. 지원되는 핵심 MCP 프로토콜 버전은 `2024-11-05`, `2025-03-26`, `2025-06-18` 및 `2025-11-25`입니다. `healthmd-mcp`를 일반 대화형 명령으로 실행하지 마세요. MCP 호스트가 stdin과 프로세스 수명 주기를 관리합니다.

## Codex 설정

번들 도우미를 `~/.codex/config.toml`에 추가합니다.

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Codex를 다시 시작하고 `healthmd_doctor`를 호출한 뒤 `healthmd_metrics`로 ID를 확인합니다. 업데이트 도구로 작고 정확한 범위를 명시적으로 가져온 다음 그 범위를 `healthmd_metric_chart`로 조회합니다. 대화형 MCP Apps가 없는 호스트도 정확한 JSON과 표준 PNG 차트를 받습니다.

## Claude 설정

Claude Desktop의 MCP 구성 또는 신뢰할 수 있는 Claude Code `.mcp.json`에서 다음 로컬 stdio 항목을 사용합니다.

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

구성을 편집한 뒤 Claude Desktop을 다시 시작하세요. Claude 프로젝트 구성에는 작업 공간 신뢰와 명시적 서버 승인이 필요합니다.

안정적인 MCP Apps 확장을 알리는 Claude Desktop 버전은 Health.md의 대화형 보기를 인라인으로 렌더링합니다. Claude Code 및 기타 텍스트 중심 클라이언트는 JSON 및 이미지 대체 출력을 유지합니다.

## 이식 가능한 직접 MCP 미리보기

독립 실행형 출시 후 `healthmd setup codex`는 포그라운드 iPhone을 페어링하고 동일 바이너리의 `healthmd mcp serve` 항목을 안전하게 만듭니다. 이 토폴로지는 포트 `17647`의 인증되고 암호화된 수동 IP 또는 Tailscale 전송, 네이티브 자격 증명 저장소 및 요청별 명시적 iPhone 읽기를 사용합니다. Linux에는 잠금 해제된 Secret Service 제공자가 추가로 필요하며 Windows는 Credential Manager를 사용합니다.

`healthmd-cli/v<version>` 출시 전에는 공개되지 않은 패키지 또는 설치 프로그램 URL에 의존하지 마세요. 준비된 페어링 및 전송 계약은 [직접 iPhone CLI](/ko/docs/cli-direct/)를 참조하세요.

## 네이티브 MCP App 시각화

Health.md는 안정적인 `io.modelcontextprotocol/ui` 협상에 `text/html;profile=mcp-app`을 사용합니다.

호스트가 해당 MIME 유형을 알리면 서버는 다음을 제공합니다.

- `ui://healthmd/query-visualization-v1`
- 표준 `resources/list` 및 `resources/read` 메서드
- 분석 및 내보내기 수신 확인 도구의 `_meta.ui.resourceUri`
- 정확한 JSON 텍스트와 함께 검증된 `structuredContent`

보기는 네트워크, 원격 스크립트, 원격 글꼴, 저장소 또는 중첩 프레임이 없는 독립형 HTML5 리소스입니다. 선언된 CSP에는 빈 연결/리소스/프레임/기본 도메인 목록이 포함됩니다. 표준 초기화, 도구 결과, 테마, 크기 조정, 취소 및 종료 수명 주기를 따릅니다.

다음을 렌더링할 수 있습니다.

- 단위와 명시적 누락 데이터 간격이 포함된 측정 항목 선 차트
- 호출자가 선택한 집계를 사용한 기간 비교
- 수면 세션 및 단계 기간 요약
- 운동 및 사실 기반 운동/수면 시점
- 데이터 범위, 누락 구간, 증거 및 제한 사항
- 전체 페이지 순회 수신 확인
- 영속 내보내기 진행 상황, 대상 및 작업 수신 확인

호스트가 MCP Apps를 지원하지 않아도 도구는 작동합니다. `healthmd_metric_chart`는 완전한 JSON을 텍스트로 유지하면서 이미지 지원 호스트에 `image/png` 콘텐츠를 추가합니다.

## 사용 가능한 도구

번들 Mac 서버는 준비 상태/쿼리 도구 13개, 생성 파일 작업 도구 4개, 암호화 컨텍스트 업데이트 작업 도구 4개로 구성된 고정 도구 21개를 제공합니다. 19개 도구의 이식 가능한 미리보기는 준비 상태/쿼리 도구 13개와 내보내기 도구 4개를 유지하고, Mac 업데이트 작업을 직접 페어링 도구 2개로 대체하며, 포그라운드 iPhone에서 타입 지정 쿼리를 직접 실행합니다.

### 준비 상태 및 검색

| 도구 | 목적 |
|---|---|
| `healthmd_status` | Mac 앱, 컨텍스트, iPhone 및 내보내기 준비 상태 확인 |
| `healthmd_doctor` | 번들 도우미 및 Mac 루프백 토폴로지 진단 |
| `healthmd_capabilities` | 직접 쿼리, 증거, 내보내기, 스키마 및 페이징 기능 목록 표시 |
| `healthmd_metrics` | 정규 측정 항목 ID, 카테고리, 단위 및 요구 사항 목록 표시 |

### 분석 및 시각화

| 도구 | 목적 |
|---|---|
| `healthmd_metric_chart` | 측정 항목 계열을 쿼리하고 데이터 범위 및 단위가 포함된 네이티브 차트 렌더링 |
| `healthmd_sleep_sessions` | 안정적인 수면 세션 및 생리 데이터 범위 목록과 시각화 제공 |
| `healthmd_training_alignment` | 직전/직후 수면을 기준으로 사실 기반 운동 시점 표시 |
| `healthmd_workouts` | 운동 목록 및 시각화 제공 |
| `healthmd_coverage` | 측정 항목/날짜 데이터 범위 및 누락 상태 확인 |
| `healthmd_compare_periods` | 명시적 집계 의미로 정확한 기간 비교 |
| `healthmd_training_evidence` | 사실 기반 훈련 증거 패킷 생성 |
| `healthmd_query` | 정확한 `healthmd.query_request`를 전송하고 선택적으로 페이지 순회 |
| `healthmd_evidence_packet` | 정확한 증거 요청을 전송하고 선택적으로 페이지 순회 |

### 생성 파일 내보내기

| 도구 | 목적 |
|---|---|
| `healthmd_export_files` | Mac 앱을 통해 선택한 폴더에 영속 내보내기 실행 |
| `healthmd_export_job_status` | 내보내기 진행 상황 및 대상 수신 확인 검토 |
| `healthmd_export_job_resume` | 정확하고 변경 불가능한 영속 내보내기 작업 재개 |
| `healthmd_export_job_cancel` | 내보내기 작업 명시적 취소 |

내보내기, 재개 및 취소 도구는 잠재적으로 파괴적인 쓰기로 표시되며 현재 Claude 호스트에서 명시적 상호 작용이 필요합니다. 구성된 내보내기 모드가 생성 파일을 업데이트하거나 덮어쓸 수 있기 때문입니다. 위 Codex 구성은 추가 보호 수단으로 해당 도구에서 확인을 요청합니다.

### 암호화 컨텍스트 가져오기 작업 · 번들 Mac 전용

| 도구 | 목적 |
|---|---|
| `healthmd_refresh` | 승인된 범위를 iPhone에서 폐기 가능한 암호화 Mac 컨텍스트로 가져오기 |
| `healthmd_job_status` | 건강 값을 읽지 않고 새로 고침 진행 상황 확인 |
| `healthmd_job_resume` | 정확히 허용된 새로 고침 작업 재개 |
| `healthmd_job_cancel` | 허용된 새로 고침 작업 명시적 취소 |

### 완전한 쿼리 구조 찾기

MCP `tools/list`에는 날짜, 측정 항목, 소스, 페이징, 기간 범위, 집계 및 고급 `healthmd.query_request`에 대한 완전한 중첩 JSON Schema가 포함됩니다. 타입 지정 도구에는 구체적인 예제도 포함됩니다. 에이전트는 일반 셸 도움말을 살펴보는 대신 일치하는 타입 지정 도구를 직접 호출해야 합니다. 특히 수면 질문에는 `healthmd_sleep_sessions`를 사용합니다. `healthmd extract`는 다른 정규 소스 데이터 프로젝션을 생성합니다.

이식 가능한 미리보기에서는 네트워크 리스너를 열거나 iPhone에 연결하지 않고도 동일한 스키마를 로컬에서 확인할 수 있습니다. 출시된 Mac 도우미에서는 MCP tools/list를 사용하세요.

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

최소 수면 호출은 다음 구조입니다. 실제 요청에 맞는 포함 날짜를 확인하세요.

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

정규 수면 측정 항목과 무손실 세션 세부 정보는 `healthmd_sleep_sessions`가 자동으로 제공합니다.

## 데이터 분석 및 차트

먼저 `healthmd_doctor`를 호출하고 `healthmd_metrics`로 측정 항목 ID를 확인하세요. 출시된 Mac 토폴로지에서 타입 지정 쿼리 도구는 암호화된 Mac 컨텍스트를 읽으며 iPhone에 암시적으로 연결하지 않습니다. 최신 데이터가 필요하면 날짜, 측정 항목, 소스를 명시해 업데이트 도구를 호출하고 영속 작업이 완료될 때까지 기다린 뒤 같은 범위를 차트로 만드세요.

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

이 객체를 `healthmd_metric_chart`에 전달하세요. 대화형 보기는 단위별 소형 다중 차트를 사용합니다. 누락되거나 부분적인 데이터 지점은 0으로 바뀌지 않고 선을 끊습니다.

출시된 Mac 타입 지정 도구는 암호화된 로컬 컨텍스트를 평가하고 데이터 범위, 누락 상태, 증거 및 제한 사항이 포함된 제한된 페이지를 반환합니다. 연결되어 포그라운드에 있는 iPhone에 접속하고 요청한 컨텍스트 범위를 교체하는 것은 명시적 업데이트뿐입니다. 이식 가능한 미리보기는 각 타입 지정 요청을 페어링되어 포그라운드에 있는 iPhone에서 직접 평가합니다.

## 생성 파일 내보내기 실행

먼저 Mac용 Health.md에서 쓰기 가능한 대상 폴더를 선택하고 유지하세요. 호스트가 전체 인수를 표시하고 사용자가 승인한 뒤 `healthmd_export_files`를 호출합니다.

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

전체 기록에는 `date_selection: "all_available"`을 사용하고 `date_range`는 생략하세요. 선택적 `metric_ids`, `categories` 또는 `all_metrics`는 저장된 설정을 변경하지 않고 iPhone 가져오기를 좁힙니다. `detail_level`은 이러한 선택 중 하나가 있을 때만 적용됩니다. `all_metrics`는 명시적 측정 항목/카테고리 목록과 함께 사용할 수 없습니다.

대신 저장된 내보내기 프로필을 실행하려면 `settings_policy`를 `"profile"`로 설정하고 프로필의 안정적인 UUID가 담긴 `profile_reference`를 전달하세요(선택적 표시 `name`은 오류 기록용으로만 저장됩니다):

```json
{
  "date_selection": "explicit_range",
  "date_range": { "start": "2026-07-01", "end": "2026-07-07" },
  "settings_policy": "profile",
  "profile_reference": { "profileID": "11111111-2222-4333-8444-555555555555" }
}
```

프로필이 설정 범위를 소유합니다: `profile_reference`는 `metric_ids`, `categories`, `all_metrics` 또는 저장된 설정 정책과 결합할 수 없으며, 알 수 없는 UUID는 현재 설정으로 대체되지 않고 형식화된 오류로 실패합니다.

다음을 확인하세요.

- `status` 및 영속 `state`
- `job_id`
- 처리된/전체 날짜 및 진행 상황
- 기록된 파일 또는 일일 노트
- 검증된 데스크톱 대상
- 커밋된 파티션 및 바이트
- 일시 중지/실패 이유 및 만료

시간 초과 또는 닫힌 MCP 대기자는 영속 작업을 취소하지 않습니다. 결과를 알 수 없을 때 재개하기 전에 `healthmd_export_job_status`를 확인하세요. 명시적 취소만 작업을 종료합니다.

원시 및 정규 소스 전송에는 수 GB의 경로, 임상 텍스트, 첨부 파일 및 소스 레코드가 포함될 수 있습니다. Health.md는 의도적으로 이러한 본문을 MCP 대화에 넣지 않습니다. 소스 형태 출력에는 검증된 스트리밍 CLI를 사용하세요.

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

MCP 분석은 파생된 사실 보기로 유지됩니다. 생성 파일 내보내기는 프로덕션 내보내기 도구를 통해 계속 공개 `healthmd.health_data` 계약을 사용합니다.

## 페이징 및 완전성

지원되는 쿼리/증거 도구는 `all_pages: true`를 제공합니다. 도우미는 순환 감지와 전체 바이트/페이지 한도를 적용해 불투명 커서를 따라가고, 버전이 지정된 각 응답을 `healthmd.mcp_query_pages` v1 아래에 보존합니다. 자동 순회 한도에 도달하면 성공 상태의 부분 결과 래퍼가 `receipt.traversal_complete`를 `false`로 설정하고 정보 손실 없이 계속 진행할 수 있는 정확한 `receipt.next_cursor`를 반환합니다. iPhone은 포그라운드에서 아무 작업이 없는 동안 10분간 페이지화된 압축 스냅샷을 유지하고 최종 순회 또는 백그라운드 전환 시 지웁니다. 요청 하나에는 다음과 같은 인코딩된 압축 컨텍스트 보호 한도가 적용됩니다: 366,000일, 64 MiB. `query_scope_too_large`는 논리적 기록을 사용할 수 없다는 뜻이 아니라 호출 간에 날짜 또는 측정 항목 ID를 분할하라는 뜻입니다. 페이지는 누락 구간 및 소스 설명자 목록을 명시적 개수/잘림 필드와 제한 사항으로 제한합니다.

전송 성공은 완전성을 뜻하지 않습니다. 항상 다음을 확인하세요.

- 요청 범위 및 데이터 모음 상태
- 데이터 범위 및 누락 구간
- 제한 사항 및 증거
- `next_cursor` 또는 순회 수신 확인
- 관련 없는 건너뜀
- 소스 스키마 및 버전

MCP App은 이러한 필드를 숨기지 않고 표시합니다. 자동 순회가 안전 한도에 도달하면 범위를 좁히거나 수동으로 계속하세요.

## 보안 및 개인정보 보호 경계

도우미에는 프롬프트, 루트, 샘플링, 셸, SQL, 임의 파일 읽기, 임의 URL 가져오기, HealthKit 쓰기, 루프백 HTTP 서비스 또는 원격 MCP 엔드포인트가 없습니다. 유일한 MCP 리소스는 번들 App 문서입니다. 생성 파일 쓰기는 승인이 필요한 고정 작업 하나입니다. 출시된 Mac 도우미는 Mac용 Health.md에서 선택한 폴더를 사용합니다. 이식 가능한 미리보기는 전송 전에 검증하고 영속적으로 결합하는 명시적 기존 대상을 요구합니다.

직접 신뢰는 키체인, Secret Service 또는 Windows Credential Manager에 저장됩니다. 페어링은 기존 인증 암호화 프로토콜을 사용합니다. iPhone은 포그라운드에 있어야 하며 컴퓨터의 LAN 또는 Tailscale 주소에 명시적으로 연결되어야 합니다. 쿼리 페이지는 협상된 바이트/항목 한도로 제한되며 자동 전체 페이지 집계에는 추가 바이트/페이지 한도가 있습니다. 제한 없는 원시 본문은 검증된 스트리밍 CLI 경로에 유지됩니다.

Health.md는 단위, 출처, 데이터 범위 및 누락 상태와 함께 사실 관측을 보고합니다. 진단하거나, 치료를 권고하거나, 인과관계를 추론하거나, 방향을 더 좋거나 나쁘다고 표현하지 않습니다.

## 문제 해결

| 증상 | 조치 |
|---|---|
| 호스트가 도우미를 시작할 수 없음 | 절대 경로의 설치된 `healthmd` 또는 `.exe`에 인수 `mcp serve`를 사용하세요. |
| 터미널에서 실행하면 도우미가 기다림 | 정상입니다. MCP 호스트가 stdin으로 JSON-RPC를 보내야 합니다. |
| `healthmd_not_paired` | `healthmd direct pair`를 실행하고 iPhone에서 페어링을 완료하세요. |
| `healthmd_unavailable` | iPhone에서 Health.md를 잠금 해제하고 포그라운드에 두며 Direct CLI 액세스를 활성화하고 컴퓨터에 연결하세요. |
| `query_scope_too_large` | 호출 간에 날짜 또는 측정 항목 ID를 분할하세요. 논리적 데이터 모음은 여러 요청에서 계속 사용할 수 있습니다. |
| 대화형 차트가 없음 | 호스트를 업데이트하세요. 서버는 계속 정확한 JSON과 PNG 측정 항목 차트 대체 출력을 반환합니다. |
| 내보내기 대상을 사용할 수 없음 | Mac: Health.md에서 저장된 폴더를 다시 선택하세요. 이식 가능한 미리보기: 기존 절대 경로이며 심볼릭 링크가 아닌 데스크톱 디렉터리를 만들어 전달하세요. |
| 내보내기 대기 시간 초과 | 재개하기 전에 ID로 영속 내보내기 작업을 확인하세요. |
| 결과에 `next_cursor`가 있음 | `all_pages: true`를 설정하거나 커서를 수동으로 계속하세요. |

## 관련 문서

<div class="related">
  <a href="/ko/docs/agents/"><span>아키텍처</span>로컬 에이전트, 암호화 컨텍스트, 요청 범위 및 증거.</a>
  <a href="/ko/docs/agent-queries/"><span>분석</span>측정 항목, 수면, 운동, 비교 및 데이터 범위를 위한 타입 지정 쿼리 활용법.</a>
  <a href="/ko/docs/cli-extract/"><span>소스 데이터</span>대용량 소스 형태 결과를 위한 검증된 정규 추출.</a>
  <a href="/ko/docs/reference/evidence-packets/"><span>계약</span>타입이 지정된 값, 누락 상태, 증거 및 패킷 식별 정보.</a>
</div>
