# healthmd-mcp

Vendor-neutral Model Context Protocol application code for Health.md.

This crate adapts the transport-neutral `healthmd-operations` registry and application service to MCP
tools, resources, results, stdio, and HTTP. It does not own operation normalization, mobile pairing,
native credentials, HealthKit, Health Connect, local destination access, or health-data storage.

- `HealthMdApplication` is shared by local and read-only remote transports.
- `HealthMdSession` keeps negotiated client capabilities isolated per MCP session.
- The optional `streamable-http` feature exposes standard MCP Streamable HTTP.
- The optional `oauth-resource-server` feature adds RFC 9728 metadata and bounded JWT/JWKS
  access-token validation.
- MCP Apps UI uses the open `io.modelcontextprotocol/ui` extension and retains JSON/PNG fallbacks.

CLI queries, local stdio, and direct-backed HTTP use the same `HealthOperations` service and
`HealthDataBackend` contract. The packaged MCP catalog is generated from that shared registry. The
remote profile exposes only read-only tools and still queries the paired foreground iPhone; it has no
synchronized corpus or server-side health-data fallback. Pairing execution and filesystem exports
remain in `healthmd-cli`; its local stdio adapter may expose their guarded MCP operations, while HTTP
and OAuth profiles cannot discover them. See the repository's [Remote MCP architecture](https://github.com/CodyBontecou/health-md/blob/main/apps/cli/docs/remote-mcp.md).
