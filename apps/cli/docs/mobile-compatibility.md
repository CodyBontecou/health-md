# Standalone CLI mobile compatibility

This is the authoritative mobile compatibility ledger for the portable Rust CLI. Protocol numbers
show wire capability; they are not a substitute for an app version/build that completed the physical
release matrix.

## `healthmd-cli` 0.1.0-alpha.3 candidate

| Mobile source and feature | Protocol | Exact tag-SHA counterpart / unqualified compatibility floor | Public qualification |
|---|---|---|---|
| iPhone status/raw/extract/generated files/resume/cancel | selector 1, application v1 | Health.md iOS 3.2.1 (build 202608300209) / iOS 3.0.3 | **Pending; no public CLI/mobile pair qualified yet** |
| iPhone portable typed MCP queries | selector 1, application v1 + query v3 | Health.md iOS 3.2.1 (build 202608300209) / iOS 3.0.3 | **Pending; no public CLI/mobile pair qualified yet** |
| Android status/provider-native raw/generated files/resume/cancel | selector 2, application v2 | Health.md Android 1.8.1 (`versionCode 30`) / Android 1.5.4 (`versionCode 25`) | **Pending; no public CLI/mobile pair qualified yet** |
| Android typed MCP queries | N/A | Not implemented | Unsupported |

The exact counterparts above are the mobile versions present at the CLI tag SHA. The lower floors
identify source versions that implement the protocol, but are not qualification claims or proof
that an App Store or Play build with the same marketing version contains the candidate code.
Each qualified cell must keep this exact field order and remain backed by one health-free,
separately retained physical release record whose SHA-256 matches `evidence_sha256`. When a new
mobile build or CLI candidate SHA is qualified, update both the record and the ledger digest
together — never reuse an old digest for new evidence:

```text
**Qualified:** mobile_build=<version/build>; source_commit=<40-lowercase-hex>; device_os=<model and OS>; lan=pass; tailscale=pass; evidence_sha256=<64-lowercase-hex>
```

The evidence digest identifies the separately retained health-free physical release record. Do not
put health values, owner dates, routes, credentials, user paths, or raw payloads in this ledger or
evidence. `verify-release.py` permits pending rows for ordinary source CI and explicitly labeled
SemVer prerelease tags. A prerelease with pending rows is an unqualified preview, not evidence of a
supported CLI/mobile pair. Stable `healthmd-cli/v*` tags remain blocked until all three supported
mobile rows contain the exact qualified shape, and every `source_commit` must equal the tag SHA.
Before approving the protected `cli-release` environment, the reviewer must compare every
`evidence_sha256` with its separately retained health-free physical record. If the first qualified
store build has a later version/build, update this ledger and release notes before tagging.

## Compatibility rules

- Query v3 is additive to iPhone v1 pairing and encrypted transport. Exports remain v1.
- Android v2 uses its own high-entropy pairing selector and never downgrades to v1.
- An old v1-only iPhone remains usable for supported v1 operations; typed query tools report
  unsupported rather than sending an unknown message.
- macOS, Linux, and Windows Rust clients use the deployed `macos_cli` wire role. Desktop OS changes
  native credentials and filesystem behavior, not the mobile application protocol.
- Release evidence must identify exact mobile builds. Marketing version, protocol number, or a green
  fixture test alone is insufficient.
