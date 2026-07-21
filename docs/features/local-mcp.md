# Local Health.md MCP server

## Topology

`healthmd-mcp` is a local stdio Model Context Protocol helper. It is a thin adapter over the running Health.md Mac app's loopback agent API; it does not read HealthKit, export folders, security-scoped bookmarks, or arbitrary files.

The helper advertises tools only. It has no MCP resources, prompts, roots, sampling, shell, SQL, URL-fetch, HealthKit-write, or filesystem capability. The only network destination accepted by configuration is an HTTP loopback Health.md endpoint (`127.0.0.1`, `::1`, or `localhost`).

Supported MCP protocol versions are `2024-11-05`, `2025-03-26`, `2025-06-18`, and `2025-11-25`. Messages use newline-delimited JSON-RPC over stdin/stdout.

## Authentication

Set the one-time credential issued for a registered client in the MCP process environment:

```bash
HEALTHMD_AGENT_TOKEN='<credential>' healthmd-mcp
```

The helper sends it only as `Authorization: Bearer …` to the fixed loopback API. It never writes the token, includes it in MCP responses, or logs it. Health.md binds the authenticated registration, exact profile revision/digest, grant, activity record, and durable job owner server-side.

`healthmd_status` is the only tool that can run without a credential. Other tools return `agent_authentication_required` before making an HTTP request.

## Tools

- `healthmd_status`
- `healthmd_capabilities`
- `healthmd_profiles`
- `healthmd_query`
- `healthmd_evidence_packet`
- `healthmd_refresh`
- `healthmd_activity`
- `healthmd_job_status`
- `healthmd_job_resume`
- `healthmd_job_cancel`

Query and activity results are paged. Clients must follow `next_cursor` until absent; page and transport bounds never make an authorized tail inaccessible. A single oversized indivisible item is returned alone with an explicit limitation rather than dropped.

Fresh acquisition remains an iPhone operation and uses durable all-history corpus transfer when requested. Cached queries remain local to the encrypted Mac context store.

## Safety semantics

Health.md responses contain factual observations with units, source evidence, coverage, and missingness. The helper does not diagnose, recommend treatment, infer causation, or label changes better/worse. Tool results preserve structured API JSON as MCP text content and mark non-2xx or local transport failures with `isError: true`.

Streamable HTTP MCP is intentionally not exposed. Stdio avoids claiming that loopback alone authenticates generic MCP clients while Health.md's registered-client and grant checks remain authoritative.
