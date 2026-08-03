# healthmd-mcp

Vendor-neutral Model Context Protocol application code for Health.md.

This crate adapts the transport-neutral `healthmd-operations` registry and application service to MCP
tools, resources, results, stdio, and HTTP. It does not own operation normalization, mobile pairing,
native credentials, HealthKit, Health Connect, local destination access, or health-data storage.

- `HealthMdApplication` is shared by complete local, local read-only, and remote read-only surfaces.
- `HealthMdSession` keeps negotiated client capabilities isolated per MCP session.
- The optional `streamable-http` feature exposes standard MCP Streamable HTTP.
- The optional `oauth-resource-server` feature adds RFC 9728 metadata and bounded JWT/JWKS
  access-token validation.
- MCP Apps UI uses the open `io.modelcontextprotocol/ui` extension for query visualizations and a local-only inline pairing QR card, while retaining JSON/PNG fallbacks.

CLI queries, local stdio, and direct-backed HTTP use the same `HealthOperations` service and
`HealthDataBackend` contract. The packaged MCP catalog is generated from that shared registry. The
read-only profiles expose only the 13 readiness/query tools and still query the paired foreground
iPhone; they have no synchronized corpus or server-side health-data fallback. The local read-only
stdio profile needs no HTTP, OAuth, tunnel, or cloud service. Pairing execution and filesystem
exports remain in `healthmd-cli`; only its complete local stdio adapter may expose those guarded MCP
operations, while local read-only, HTTP, and OAuth profiles cannot discover or invoke them. See the
repository's [Remote MCP architecture](https://github.com/CodyBontecou/health-md/blob/main/apps/cli/docs/remote-mcp.md).
