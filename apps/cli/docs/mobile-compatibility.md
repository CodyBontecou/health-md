# Standalone CLI mobile compatibility

This is the authoritative mobile compatibility ledger for the portable Rust CLI. Protocol numbers
show wire capability; they are not a substitute for an app version/build that completed the physical
release matrix.

## `healthmd-cli` 0.1.0-alpha.7

| Mobile source and feature | Protocol | Exact tag-SHA counterpart / unqualified compatibility floor | Public qualification |
|---|---|---|---|
| iPhone status/raw/extract/generated files/resume/cancel | pairing selector 3 current (1 legacy), application v1 | Health.md iOS 3.4.0 (build 202609032318) / iOS 3.0.3 | **Pending; no public CLI/mobile pair qualified yet** |
| iPhone portable typed MCP queries | pairing selector 3 current (1 legacy), application v1 + query v3 | Health.md iOS 3.4.0 (build 202609032318) / iOS 3.0.3 | **Pending; no public CLI/mobile pair qualified yet** |
| Android status/provider-native raw/generated files/resume/cancel | pairing selector 3 current (2 legacy), application v2 | Health.md Android 1.9.0 (`versionCode 38`) / Android 1.5.4 (`versionCode 25`) | **Pending; no public CLI/mobile pair qualified yet** |
| Android typed MCP queries | N/A | Not implemented | Unsupported |

The owner has physically confirmed that alpha.7 pairs and connects to both iPhone and Android. That
connectivity smoke is recorded here without promoting it into a complete release qualification:
the retained record still needs exact device/OS identity, LAN and Tailscale results, the full
operation matrix, and its evidence digest before any row may use the machine-checked `Qualified`
shape below.

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

## Current source history limitations

The current Apple native adapter cannot assess per-type history-authorization boundaries with the
pinned SDK (Xcode 26.6 / SDK 26.5). It reports `api_unavailable`; this is not proof of denial or no data.
An absent assessment or `unknown` likewise cannot establish full-history access. Use explicit date ranges
with completeness unverified, and preserve HealthKit's denied-versus-empty ambiguity. See
[HealthKit permission and history semantics](../../apple/docs/features/healthkit-permissions.md).

An OS upgrade alone cannot enable an API missing from this build. Related legacy API hints such as
`minimum_source_os: 27` and `full_history_claim_requires_os_27_boundary_check` remain compatibility
fields, not upgrade instructions or support claims. The contract can represent `limited_history` and
`full_history` from a capable source or synthetic tests; that grammar does not make the current native
adapter capable. Qualification must name the exact app/build/SDK and the assessment it actually produced.

`healthmd_doctor` forwards peer-supplied history metadata when available; a ready transport or an OS
version is not a verified history grant. Unqualified `all_available` completeness requests are rejected
by the current Apple capture paths. Configuration-only bridge planning may retain logical
`all_available` without resolving history bounds or reading data; its callable source services are not
yet advertised native routes or approved execution.

Android Health Connect uses its own historical-read permission and first-grant-date window. That grant
is not an Apple per-type boundary assessment, and provider-specific limits remain independent. Do not
replace unavailable history or privacy-hidden records with empty/zero values to claim parity.

These are current development-source limits, not new claims about alpha.7's immutable binaries.
Physical release qualification remains pending; source tests do not qualify an installed counterpart.

## Compatibility rules

- RFC-0005 P1 is a host-side wait-only wake window shared by iOS and Android. It changes no pairing,
  application-protocol, query, or transfer bytes. P2 adds opt-in APNs enrollment for iPhone; current
  `main` compiles the health-free worker nudge into every desktop CLI build and alpha.7 archives
  carry that default. Published alpha.6 archives remain P1-only because P2 was source-feature-gated;
  alpha.7 and later send the best-effort nudge by default. Android FCM remains the
  explicit P3 target, so opening Health.md manually unblocks Android in the meantime.
- Shared pairing selector 3 is independent from iPhone query v3. It adds one 20-digit iOS/Android QR/code without changing application v1/v2 or encrypted transport.
- Legacy Apple selector 1 and Android selector 2 remain byte-compatible. Android may retry high-entropy selector 2 for an older CLI and never downgrades its application protocol to v1.
- An old v1-only iPhone remains usable for supported v1 operations; typed query tools report
  unsupported rather than sending an unknown message.
- macOS, Linux, and Windows Rust clients use the deployed `macos_cli` wire role. Desktop OS changes
  native credentials and filesystem behavior, not the mobile application protocol.
- Release evidence must identify exact mobile builds. Marketing version, protocol number, or a green
  fixture test alone is insufficient.
