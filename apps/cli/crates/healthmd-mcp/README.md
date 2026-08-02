# healthmd-mcp

Vendor-neutral Model Context Protocol application code for Health.md.

This crate adapts the transport-neutral `healthmd-operations` registry and application service to MCP tools, resources, results, stdio, and HTTP. It does not own operation normalization, mobile pairing, native credentials, HealthKit, Health Connect, or local destination access.

- `HealthMdApplication` is shared by local and hosted transports.
- `HealthMdSession` keeps negotiated client capabilities isolated per MCP session.
- The optional `streamable-http` feature exposes standard MCP Streamable HTTP.
- The optional `oauth-resource-server` feature adds RFC 9728 metadata and bounded JWT/JWKS access-token validation.
- The optional `hosted-data` feature adds a caller-partitioned encrypted compact-day backend and explicit consent/synchronization API primitives.
- MCP Apps UI uses the open `io.modelcontextprotocol/ui` extension and retains JSON/PNG fallbacks.

CLI queries, local stdio, and hosted HTTP use the same `HealthOperations` service and
`HealthDataBackend` contract. The packaged MCP catalog is generated from that shared registry.
Hosted mode exposes only read-only tools; local pairing and filesystem exports remain in
`healthmd-cli`. See the repository's [Remote MCP architecture](https://github.com/CodyBontecou/health-md/blob/main/apps/cli/docs/remote-mcp.md) for the OAuth, storage, consent, retention, deletion, and deployment contract.
