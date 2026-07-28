# Local Health.md MCP server

## Topology

`healthmd-mcp` is a local stdio Model Context Protocol helper. It is a thin adapter over the running Health.md Mac app's loopback query API; it does not read HealthKit, export folders, security-scoped bookmarks, or arbitrary files.

The helper advertises tools only. It has no MCP resources, prompts, roots, sampling, shell, SQL, URL-fetch, HealthKit-write, or filesystem capability. The only network destination accepted by configuration is an HTTP loopback Health.md endpoint (`127.0.0.1`, `::1`, or `localhost`). There are no credentials or profile grants; the loopback listener is the complete access boundary.

Supported MCP protocol versions are `2024-11-05`, `2025-03-26`, `2025-06-18`, and `2025-11-25`. Messages use newline-delimited JSON-RPC over stdin/stdout.

## Tools

- `healthmd_status`
- `healthmd_doctor`
- `healthmd_capabilities`
- `healthmd_metrics`
- `healthmd_sleep_sessions`
- `healthmd_training_alignment`
- `healthmd_workouts`
- `healthmd_coverage`
- `healthmd_compare_periods`
- `healthmd_training_evidence`
- `healthmd_query`
- `healthmd_evidence_packet`
- `healthmd_refresh`
- `healthmd_job_status`
- `healthmd_job_resume`
- `healthmd_job_cancel`

Every data tool carries its metric, source, date, detail, and operation scope directly. `healthmd.health_data` is the sole public source-data contract; MCP tools remain derived protocol views backed by a disposable internal index. Use the separate `healthmd extract` CLI when original canonical objects are required.

The typed metric, sleep-session, factual workout/sleep-alignment, workout, coverage, period-comparison, and training-evidence tools construct fixed `healthmd.query_request` v1 operations from explicit schemas with unknown top-level properties rejected. Sleep and alignment requests select lossless detail and the required canonical sleep-stage metrics directly. Technical adjacent days may be inspected internally for session boundaries but unrelated dates or metrics are not returned.

Fresh acquisition results expose corpus-wide status separately from `healthmd.requested_scope_completion` v1 and `unrelated_skips`. Query/evidence tools accept `all_pages: true`; the helper follows opaque cursors with cycle checks and bounded aggregate byte/page ceilings, returning `healthmd.mcp_query_pages` v1 with original pages and a receipt. Individual pages remain bounded and continuable.

## Safety semantics

Health.md responses contain factual observations with units, source evidence, coverage, and missingness. The helper does not diagnose, recommend treatment, infer causation, or label changes better/worse. Tool results preserve structured API JSON as MCP text content and mark non-2xx or local transport failures with `isError: true`.

Streamable HTTP MCP is intentionally not exposed. Keep the Mac app's loopback port local; any local process that can connect while Health.md is running can issue the same requests.
