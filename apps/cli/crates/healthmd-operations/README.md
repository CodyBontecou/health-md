# healthmd-operations

`healthmd-operations` is Health.md's transport-neutral application contract.

It owns the fixed operation registry, typed operation normalization, backend interface, bounded
query traversal, canonical receipts, and health-free failures shared by the command-line and MCP
adapters. It does not parse shell arguments, implement JSON-RPC, open sockets, access credentials,
or read HealthKit.

The CLI and MCP adapters must translate into these operations rather than implementing parallel
business behavior.
