# Standalone CLI mobile compatibility

This is the authoritative mobile compatibility ledger for the portable Rust CLI. Protocol numbers
show wire capability; they are not a substitute for an app version/build that completed the physical
release matrix.

## `healthmd-cli` 0.1.0-alpha.1 candidate

| Mobile source and feature | Protocol | Conservative source floor | Public qualification |
|---|---|---|---|
| iPhone status/raw/extract/generated files/resume/cancel | selector 1, application v1 | Health.md iOS 3.0.3 built from the exact CLI candidate SHA | **Pending; no public CLI/mobile pair qualified yet** |
| iPhone portable typed MCP queries | selector 1, application v1 + query v3 | Health.md iOS 3.0.3 built from the exact CLI candidate SHA | **Pending; no public CLI/mobile pair qualified yet** |
| Android status/provider-native raw/generated files/resume/cancel | selector 2, application v2 | Health.md Android 1.5.4 (`versionCode 25`) built from the exact CLI candidate SHA | **Pending; no public CLI/mobile pair qualified yet** |
| Android typed MCP queries | N/A | Not implemented | Unsupported |

The floors above describe the current monorepo source that implements the contracts. They are not a
claim that an App Store or Play build with the same marketing version contains the candidate code.
Before publishing the CLI, replace each required pending cell in this authoritative ledger with one
health-free machine-checked record using this exact field order:

```text
**Qualified:** mobile_build=<version/build>; source_commit=<40-lowercase-hex>; device_os=<model and OS>; lan=pass; tailscale=pass; evidence_sha256=<64-lowercase-hex>
```

The evidence digest identifies the separately retained health-free physical release record. Do not
put health values, owner dates, routes, credentials, user paths, or raw payloads in this ledger or
evidence. `verify-release.py` permits pending rows for ordinary source CI but rejects every
`healthmd-cli/v*` tag until all three supported mobile rows contain the exact qualified shape. If the
first qualified store build has a later version/build, update this ledger and release notes before
tagging.

## Compatibility rules

- Query v3 is additive to iPhone v1 pairing and encrypted transport. Exports remain v1.
- Android v2 uses its own high-entropy pairing selector and never downgrades to v1.
- An old v1-only iPhone remains usable for supported v1 operations; typed query tools report
  unsupported rather than sending an unknown message.
- macOS, Linux, and Windows Rust clients use the deployed `macos_cli` wire role. Desktop OS changes
  native credentials and filesystem behavior, not the mobile application protocol.
- Release evidence must identify exact mobile builds. Marketing version, protocol number, or a green
  fixture test alone is insufficient.
