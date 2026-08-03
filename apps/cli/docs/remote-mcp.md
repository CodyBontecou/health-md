# Remote MCP architecture

## Status and product boundary

Health.md does not operate or provide a synchronized health-data corpus. It does not upload, retain,
or back up users' health data for later MCP queries.

The default CLI exposes local MCP over newline-delimited JSON-RPC on stdio. Source builds may also
enable a read-only Streamable HTTP transport for development or a deliberately configured
single-owner direct relay:

| Mode | Transport | Data source | Retained health data |
|---|---|---|---|
| Local | JSON-RPC over stdio | Paired foreground iPhone over the encrypted direct protocol | None |
| Remote relay | MCP Streamable HTTP at `/mcp` | The same paired foreground iPhone | None |

Both modes use the same `healthmd-operations` registry and direct iPhone backend. The HTTP mode does
not replace that backend with server storage. Every health query still requires the paired iPhone to
be open, authorized, reachable, and able to answer the bounded request.

ChatGPT, Claude, Codex, IDEs, and other clients are distribution targets rather than architectural
dependencies. Vendor-specific manifests must not change query semantics, authorization, or data
handling.

## Streamable HTTP surface

The source-build-only HTTP command is:

```bash
cargo run --release --features streamable-http -- mcp serve-http \
  --bind 127.0.0.1:8787 \
  --allowed-host localhost:8787
```

The listener is loopback-only. Without OAuth it also rejects every non-loopback Host or Origin, so a
public reverse proxy cannot turn development mode into an unauthenticated remote endpoint. It
supports MCP Streamable HTTP revisions `2025-06-18` and `2025-11-25`, bounded JSON requests and
responses, cancellation, opaque sessions, and the negotiated MCP Apps extension. It exposes the 13 read-only readiness, discovery, typed query, chart, sleep,
workout, comparison, coverage, and evidence tools. Pairing QR/session tools and generated-file
export, resume, and cancel tools remain local-stdio-only and cannot be discovered or invoked over
HTTP/OAuth.

The relay has no health-data database, compact-day store, synchronization API, account-data API,
retention scheduler, health-data backup, or remote export path. It processes only the bounded live
request and response needed for the current MCP call. Pairing trust remains in the native credential
store on the machine running the CLI.

## Optional OAuth resource server

The `oauth-resource-server` feature adds RFC 9728 protected-resource metadata and bounded JWT/JWKS
verification around the same direct relay. It does not add an account system or health-data storage.
OAuth mode is intentionally single-owner: `HEALTHMD_MCP_OAUTH_OWNER_SUBJECT` must match the exact
verified token subject.

```bash
HEALTHMD_MCP_OAUTH_OWNER_SUBJECT='exact-owner-subject' \
cargo run --release --features oauth-resource-server -- mcp serve-http \
  --bind 127.0.0.1:8787 \
  --allowed-host mcp.example.com \
  --allowed-origin https://trusted-client.example \
  --oauth-resource https://mcp.example.com/mcp \
  --oauth-issuer https://auth.example.com/ \
  --oauth-jwks-uri https://auth.example.com/.well-known/jwks.json
```

The protected resource publishes metadata at:

```text
/.well-known/oauth-protected-resource
/.well-known/oauth-protected-resource/mcp
```

Tokens must have the exact issuer and resource audience, a supported asymmetric signature, valid
time claims, the configured owner subject, and the `healthmd:read` scope. Every HTTP request is
reverified. MCP sessions are bound to the verified issuer, subject, audience, and tenant claim, so a
session cannot be reused by another authorization grant. Verified bearer headers are removed before
dispatch.

JWT verification accepts RS256, ES256, and EdDSA only. JWKS retrieval requires HTTPS except for
loopback development, rejects redirects, times out, and caps responses at 1 MiB. Unknown-key refresh
is throttled.

## Deployment requirements

The Rust process does not terminate public TLS. A remote experiment requires a co-resident HTTPS
reverse proxy that forwards only to the loopback listener and preserves an explicitly allowed Host.
Browser Origin access is denied by default; each trusted browser origin must be allowlisted exactly.
Partial OAuth configuration fails closed.

A relay operator must ensure that proxy, OAuth, crash, and observability systems do not record MCP
arguments, health responses, bearer tokens, device identities, local paths, or direct-protocol
payloads. Health-free telemetry may include service version, route class, status, duration bucket,
byte/count buckets, and a random request identifier.

Because queries are live, remote availability must never be described as durable or asynchronous.
If the iPhone is locked, backgrounded, disconnected, unpaired, or unavailable, the query fails or
times out instead of falling back to stored data.

## Security boundaries

| Threat | Control |
|---|---|
| Public plaintext listener | Loopback-only bind and co-resident TLS reverse proxy |
| Token replay against another API | Exact issuer and resource audience validation |
| Another account using the relay | Exact configured owner subject and session-principal binding |
| Browser DNS rebinding or untrusted origins | Explicit Host allowlist and deny-by-default Origin policy |
| Credential forwarding | Authorization header removed before MCP dispatch |
| Unbounded work | Bounded headers, tokens, JWKS, MCP bodies, pages, traversal, concurrency, cancellation, and timeouts |
| Accidental server retention | No synchronization routes, corpus store, health-data files, or backup surface |

The local stdio mode remains the supported default and requires no OAuth service, reverse proxy, or
remote endpoint.
