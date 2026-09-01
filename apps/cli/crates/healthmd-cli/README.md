# healthmd-cli

The `healthmd` CLI for direct iOS/Android exports and same-executable `healthmd mcp serve` support
for typed iPhone analysis and visualization on macOS, Linux, and Windows. `healthmd setup codex`
configures and pairs the integration; `healthmd-mcp` remains a compatibility launcher. Local stdio
MCP hosts can render the bounded `healthmd_pairing_start` QR image and poll
`healthmd_pairing_status`. Least-privilege hosts can instead launch `healthmd mcp serve-read-only`,
which exposes only the 13 readiness/query tools and needs no HTTP, OAuth, tunnel, or cloud service.
HTTP/OAuth profiles never expose local pairing or export-job tools. MCP hosts receive fully
expanded nested input schemas and examples. Humans and troubleshooting agents can
print the same schema locally with `healthmd mcp schema healthmd_sleep_sessions` without opening a
listener or contacting iPhone. Incomplete shell commands are also safe discovery requests:
`healthmd export`, `healthmd extract`, `healthmd query`, and
`healthmd query healthmd_sleep_sessions` return structured requirements or exact schemas without
opening credentials or contacting a device. Interactive terminals render those envelopes as concise
human-readable text; pipes and `--json` retain the stable JSON contracts, while `--human` forces text
through a pager. Malformed and runtime failures use the same privacy-safe, actionable
`healthmd.cli_error/1` model rather than escaped terminal error text.

See the [project README](https://github.com/CodyBontecou/health-md/tree/main/apps/cli#readme) for installation,
pairing, command examples, platform support, and security details.

Licensed AGPL-3.0-only.
