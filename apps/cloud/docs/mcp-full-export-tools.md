# Full retained-export MCP tools (VM-only pilot)

`https://mcp.healthmd.app/mcp` is a **read-only** Streamable HTTP MCP endpoint. Use `POST /mcp`, `Content-Type: application/json`, `Accept: application/json, text/event-stream` and a secret per-agent `Authorization: Bearer hmd_read_…` header. It is **not** a dashboard URL, upload endpoint, live HealthKit/Health Connect bridge, file server, or public unauthenticated dataset. The client must securely store the Bearer credential; never put it in a URL, a prompt, or a log. Read results delivered to a hosted agent may enter that provider's conversations and retention/training systems.

## Authority and coverage

New tokens default to the original `aggregates` scope (six curated Apple-v8 daily-aggregate tools). The migration defaults **all previously issued tokens**, including the original Muse token, to `aggregates`. Only an explicitly issued `full_export` token sees the five additional tools below. Scope is fixed when issued; rotating or revoking a token does not mutate another token. Write-only iPhone ingest credentials, dashboard passwords and sessions cannot authorize MCP.

`full_export` grants access to **all original, currently retained, account-owned** `healthmd.api_export` v1/v2 JSON envelopes, including separately retained supplements and older revisions not selected as the current daily snapshot, iOS daily v8, Android compatibility daily v4/v5 where uploaded, full optional HealthKit source archives and typed provider sections, v2 provider-native sidecars, source identifiers, precise routes, sensitive free text, base64 binary stored in JSON, and failed-date details. No metric/category/date redaction or step-up prompt applies to a full token. There is no time-retention cutoff on discovery. The original encrypted ciphertext is decrypted only in the separate read-only reader process after owner-scoped metadata lookup, object authentication and digest verification.

**Not available:** data never uploaded, previously deleted, unsupported or ungranted mobile API data, detached file artifacts not in the JSON envelope, and Android *Raw API Snapshot* NDJSON artifacts (the current VM receiver does not ingest them). The existing exports are snapshots, not a live current-state or deletion-tombstone stream. Apple and Android profiles retain distinct schema versions/semantics; do not relabel them as a common metric. Archive availability depends on export-time settings and `raw_capture_status`. Missing/partial data must never be fabricated or converted to zero.

## Discover and navigate

Full-scope `tools/list` exposes the original six tools plus:

| Tool | Input | Result |
|---|---|---|
| `health_export_guide` | none | Server-owned usage, coverage, fidelity and privacy notes; call first. |
| `health_list_exports` | `cursor?: string` (start `""`), `limit?: 1..20` (default 10) | Newest-received envelopes, source, schema versions, counts, date bounds, byte size, `exportId`, `retentionRole` (`current`, `supplemental`, or `unreferenced`) and `nextCursor`. Continue until null to reach all retained history, including separately retained supplements, older replaced revisions and provider sidecars. Changes during browsing are not a snapshot; restart if concurrent uploads/deletions matter. |
| `health_find_export_for_date` | `date: "YYYY-MM-DD"` | Current **primary** daily snapshot's `exportId` and `/records/<index>` pointer. Supplements are not merged into this result or the aggregate tools; discover them, sidecar-only envelopes and historical exports using `health_list_exports`. |
| `health_read_export_node` | `exportId`, `pointer?: string` (root is `""`), `offset?: integer` (default 0), `limit?: 1..20` (default 10) | Traverse any existing JSON Pointer (RFC 6901 escapes: `/` → `~1`, `~` → `~0`). Arrays/objects yield typed child pointers and `nextOffset`; page until null. Strings return up to 8192 UTF-8 **bytes**, base64-encoded, and `nextOffsetBytes`; concatenate decoded byte chunks before decoding UTF-8 (a chunk can split a code point). Scalars return their value, except integers outside JavaScript safe-integer range: use exact bytes below. Long keys/large entries may exceed the 16 KiB result cap; use smaller pages or exact bytes. |
| `health_read_export_bytes` | `exportId`, `offsetBytes?: integer` (default 0) | Up to 8192 base64-encoded **original JSON bytes** at the given byte offset. Decode and concatenate in `nextOffsetBytes` order until null. This preserves original number digits, Unicode/escapes, fields and embedded base64 binary even if a JSON parser or pointer navigation cannot represent them exactly. This is not an arbitrary-path or plaintext file API. |

Recommended agent sequence: call `health_export_guide`; for a known day call `health_find_export_for_date` and navigate the returned pointer with `health_read_export_node`; for the complete historical corpus page `health_list_exports`, then explore each returned `exportId`. Use `health_read_export_bytes` when complete byte-for-byte fidelity or a very large value is required. Daily aggregate tools remain convenient for the original eleven verified Apple-v8 numeric metrics, but are **not** an exhaustive substitute for the full-export tools.

A synthetic MCP call (no real identifiers or credentials):

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"health_read_export_node","arguments":{"exportId":"00000000-0000-4000-8000-000000000001","pointer":"/records/0/healthkit_record_archive/records","offset":0,"limit":10}}}
```

The response is a normal MCP `tools/call` result with `structuredContent` and matching text content; `isError: true` contains a safe error code. Requests are limited to 64 KiB, results to 16 KiB, ciphertext reads to 64 MiB/call, at most two simultaneous requests and 60 requests/minute/token. A single retained envelope is at most 25 MiB plaintext; reconstructing a large export requires many calls, not one enormous model context. Authorized calls use `Cache-Control: no-store`; audit logs record only a pseudonymous token fingerprint, tool name, status and duration (not health values, arguments, dates, URLs, token or file paths). Proxy and Tunnel access logs remain off.

## Consent and operation

A full-scope token can disclose precise location, clinical and mental-health details, medication history, provider-native data, stable source identity, and binary payloads to the agent's provider. For Muse **default experience**, the owner explicitly authorized this broader exposure despite Muse's described Meta review/training eligibility and unspecified retention. A different agent (including Grokbot) still requires separate product-specific bearer-header/retention qualification and explicit owner authorization. Keep the original Muse aggregate token limited; a separate 30-day full-scope Muse token was issued and its 11-tool public catalog verified. The owner must capture it via Muse's Secure Vault (not chat), validate client `tools/list`, then revoke the old aggregate token and remove both root-only delivery copies. Muse's actual connection is still unverified.

The VM-only offline writer CLI supports `mcp-admin.mjs create --user=owner --label=Muse-full --days=30 --scope=full_export`; omit `--scope` for an aggregate-only token. Token values are shown once; never paste them into chat, CLI arguments, source or logs. For details on reader UID, key boundaries, Cloudflare ingress, interruption and revocation see [remote-read-only-mcp.md](remote-read-only-mcp.md). This unbacked single-user pilot offers no recovery guarantee or independent security-audit claim.
