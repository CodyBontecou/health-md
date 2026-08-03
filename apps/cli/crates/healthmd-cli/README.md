# healthmd-cli

The `healthmd` CLI for direct iOS/Android exports and same-executable `healthmd mcp serve` support
for typed iPhone analysis and visualization on macOS, Linux, and Windows. `healthmd setup codex`
configures and pairs the integration; `healthmd-mcp` remains a compatibility launcher. Local stdio
MCP hosts can render the bounded `healthmd_pairing_start` QR image and poll
`healthmd_pairing_status`; HTTP/OAuth profiles never expose those tools. MCP hosts receive fully
expanded nested input schemas and examples. Humans and troubleshooting agents can
print the same schema locally with `healthmd mcp schema healthmd_sleep_sessions` without opening a
listener or contacting iPhone.

See the [project README](https://github.com/CodyBontecou/health-md/tree/main/apps/cli#readme) for installation,
pairing, command examples, platform support, and security details.

Licensed AGPL-3.0-only.
