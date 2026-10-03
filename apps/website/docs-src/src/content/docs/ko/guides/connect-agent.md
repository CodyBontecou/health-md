---
title: "10분 만에 에이전트 연결"
description: "출시된 Health.md Mac MCP 도우미를 Codex 또는 Claude에 연결하고, iPhone에서 명시적 범위 하나를 가져와 제한된 쿼리를 실행한 다음 완전성을 안전하게 확인하세요."
---

<div class="availability available">
<strong>현재 사용 가능 · Mac용 Health.md</strong>
<p>이 경로는 출시된 Mac 앱에 번들로 제공되는 서명된 <code>healthmd-mcp</code> 도우미를 사용합니다. 휴대용 CLI 미리보기, Direct CLI 액세스, 페어링 QR 코드, 포트 17647은 사용하지 않습니다.</p>
</div>

로컬 MCP 호스트를 연결하고, 건강 데이터 값을 읽지 않고 준비 상태를 확인하며, iPhone에서 작은 범위 하나를 명시적으로 업데이트한 다음, 그 암호화된 Mac 컨텍스트를 조회합니다. 두 앱이 이미 설치되어 있고 같은 로컬 네트워크에 있다면 약 10분이 걸립니다.

## 1. Health.md 설치 후 열기

Mac과 iPhone 모두에서 [App Store에서 Health.md를 다운로드](https://apps.apple.com/us/app/health-md/id6757763969)하세요. 두 앱을 모두 엽니다.

HealthKit은 iPhone에 남습니다. Mac 앱은 서명된 MCP 도우미와 폐기 가능한 암호화 쿼리 컨텍스트를 호스팅하며, HealthKit을 직접 읽지 않습니다.

## 2. iPhone과 Mac 연결

1. Mac에서는 Health.md를 열어 둡니다.
2. iPhone에서 **Health.md → 동기화**를 열고 Mac 연결을 활성화합니다.
3. 두 기기를 같은 접근 가능한 로컬 네트워크에 두고, 새 작업을 시작하는 동안에는 Health.md를 iPhone에서 포그라운드로 유지합니다.
4. Mac 앱이 의도한 iPhone 연결을 표시하는지 확인합니다. 표시되지 않으면 두 앱을 다시 열고 [Mac 동기화 준비 상태](/ko/docs/sync/)를 확인하세요.

이것은 출시된 Mac 연결입니다. `healthmd direct pair`를 실행하지 마세요. 그 명령은 별도의 휴대용 미리보기에 속합니다.

## 3. 서명된 도우미 경로 복사

**Mac용 Health.md → CLI**를 열고 표시된 MCP 도우미 경로를 복사합니다. 일반적인 `/Applications` 설치는 다음을 사용합니다:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

앱이 다른 위치에 설치되어 있다면 표시된 경로를 사용하세요. 도우미는 직접 구성하세요. 셸로 감싸거나 대화형 명령으로 시작하지 마세요.

## 4. Codex 또는 Claude 구성

### Codex

`~/.codex/config.toml`에 다음을 추가하고, 필요하면 도우미 경로를 바꿉니다:

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

파일을 저장한 후 Codex를 다시 시작합니다.

### Claude Desktop 또는 Claude Code

이 로컬 stdio 항목을 Claude Desktop의 MCP 구성 또는 신뢰할 수 있는 Claude Code `.mcp.json`에 추가합니다:

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

Claude Desktop을 다시 시작하거나, Claude Code 작업 공간을 신뢰하고 서버를 승인하세요. 업데이트, 내보내기, 재개, 취소 작업에 대한 승인 프롬프트는 계속 활성화해 둡니다.

## 5. 준비 상태 확인

`healthmd_doctor`를 호출하세요. 건강 데이터 값 없이 준비 상태만 읽습니다.

준비 완료 결과에는 다음 필드가 포함됩니다:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

전체 결과에는 검사 항목과 다음 조치도 포함됩니다. 계속하기 전에 차단하는 검사를 모두 해결하세요. 연결된 도우미가 암호화 컨텍스트가 최신임을 **증명하지는 않습니다**.

다음으로 `healthmd_metrics`를 호출하고 요청하려는 정규 측정 항목 ID와 단위를 확인하세요. 이 안내에서는 `steps`를 예시로만 사용합니다.

## 6. 작은 범위 하나를 명시적으로 업데이트

실제로 원하는 날짜를 확정한 뒤, 양쪽 끝을 포함하는 정확한 범위로 `healthmd_refresh`를 호출합니다. 이 예시는 하루 치 요약 데이터를 요청합니다:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

인수를 검토하고, 획득을 승인하고, 두 앱을 열어 둡니다. 업데이트는 내보내기 파일을 쓰지 않으며 iPhone에 저장된 내보내기 설정도 변경하지 않습니다. 작업이 최종 상태에 도달할 때까지 반환된 `job_id`를 보관하세요.

## 7. 첫 제한된 쿼리 실행

업데이트가 완료되면 같은 날짜, 측정 항목, 소스 선택, 세부 수준으로 `healthmd_metric_chart`를 호출합니다:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true`는 도우미의 집계 페이지 및 바이트 상한 내에서만 불투명 커서를 순회합니다. 수면에는 정규 추출을 대체하지 말고 `healthmd_sleep_sessions`를 호출하세요.

## 8. 답하기 전에 완전성 확인

도구 성공을 완전한 건강 데이터 커버리지의 증거로 여기지 마세요. 다음을 모두 확인하세요:

- 업데이트가 같은 정확한 날짜, 측정 항목, 소스, 세부 수준에서 성공한 최종 상태에 도달했는지;
- 응답 스키마와 버전이 인식 가능한지;
- 요청한 범위와 시간대가 질문과 일치하는지;
- 명시된 각 값이 정규 측정 항목 ID와 단위를 유지하는지;
- 커버리지 상태, 고려된 일수, 값이 있는 일수, 모든 누락 구간이 보고되는지;
- `complete_empty`, `partial`, `failed`, `unsupported`, `skipped`, `cancelled`이 0으로 변환되지 않는지;
- 순회가 완료되었거나 남은 커서나 집계 상한이 공개되는지;
- 증거/소스 설명자와 제한 사항이 답변에 계속 붙어 있는지;
- 사실적 방향이 진단, 치료 조언, 인과 관계, "더 낫다/더 나쁘다"라는 표현으로 바뀌지 않는지.

### 유용한 데이터를 버리지 않고 부분 결과 읽기

타입 지정 쿼리는 요청한 범위의 일부만 완료된 상태에서도 유효한 `healthmd.query_response`를 반환할 수 있습니다. 생성된 [부분 쿼리 응답 픽스처](/docs/reference/generated/automation/agent-query-response-partial.json)는 사용 가능한 걸음 수 항목을 유지하고 실패한 날을 따로 보고합니다:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

위 `items`와 `limitations` 안의 문자열은 설명용 축약형입니다. 정확한 필드와 증거에는 다운로드 가능한 생성 픽스처를 사용하세요. 유지된 항목, 실패한 구간, 커버리지 개수, 제한 사항을 함께 보존합니다.

`status: "partial_success"`를 `healthmd.query_response`에 추가하지 마세요. 그 상태는 획득, 순회, 파일 생성이 불완전할 때 상위 수준의 CLI 및 내보내기 엔벨로프에 속합니다. 시간 초과는 또 다릅니다. 결과를 알 수 없는 영속 작업이며 작업 ID로 확인해야 합니다.

구조화된 실패는 부분 응답 대신 `healthmd.query_error` v1을 사용합니다. 안정적인 코드, 메시지, 재시도 가능성, 타입 지정 세부 정보를 포함한 생성된 프로덕션 형식은 [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json)을 확인하세요.

## 9. 시간 초과에서 안전하게 복구

시간 초과, 닫힌 호스트, 취소된 MCP 대기 작업은 승인된 업데이트를 취소하지 않습니다.

1. 반환된 `job_id`를 보관합니다.
2. 그 ID로 `healthmd_job_status`를 호출합니다.
3. 변경 불가능한 작업을 재개할 수 있다면, 같은 ID와 유한한 대기 시간 초과로 `healthmd_job_resume`을 검토하고 승인합니다.
4. 상태가 승인된 작업이 더 이상 완료될 수 없음을 증명한 뒤에만 새 업데이트를 시작합니다.
5. `healthmd_job_cancel`은 작업을 종료하려는 경우에만 사용하세요. 취소는 iPhone 확인 후에만 최종 상태가 됩니다.

결과를 알 수 없을 때 절대 무작정 재시도하지 마세요. 영속 업데이트 작업은 승인된 범위와 커밋된 경계를 보존합니다.

## 연결되었습니다

doctor가 준비되고, 명시적 업데이트가 최종 상태에 도달하며, 제한된 쿼리의 순회가 완료되고, 커버리지, 증거, 단위, 제한 사항을 검토했을 때 첫 읽기 전용 워크플로가 완료됩니다.

생성 파일 내보내기는 승인이 필요한 별도의 워크플로입니다. 출시된 Mac 도구는 Mac용 Health.md에서 이미 선택된 폴더에 기록하며, 임의의 대상 인수는 받지 않습니다.

<div class="related">
  <a href="/ko/docs/mcp/"><span>도구 카탈로그</span>출시된 모든 Mac 도구, 정확한 스키마, MCP Apps, 페이지 매김, 안전 경계를 검토하세요.</a>
  <a href="/ko/docs/configuration/"><span>다른 클라이언트</span>출시된 Mac 통합과 명확하게 표시된 휴대용 미리보기 중에서 선택하세요.</a>
  <a href="/ko/docs/agent-queries/"><span>다음 질문</span>측정 항목, 수면, 운동, 비교, 데이터 범위, 증거에 대한 타입 지정 워크플로를 실행하세요.</a>
  <a href="/ko/docs/agents/"><span>신뢰 모델</span>암호화 컨텍스트, 요청 범위, 보존, 증거, 보고 규칙을 이해하세요.</a>
</div>
