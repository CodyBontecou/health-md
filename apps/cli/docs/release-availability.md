# CLI release availability audit

Audited on **2026-10-02** against GitHub REST release metadata, the public checksum manifest,
and `CodyBontecou/homebrew-tap/Formula/healthmd.rb`. No installer or binary was executed.

| State | Evidence | What users may infer |
|---|---|---|
| Published preview: `healthmd-cli/v0.1.0-alpha.6` | Non-draft prerelease, published 2026-09-04; 23 uploaded assets; tap version alpha.6 | Downloads exist, but the CLI/mobile pair is explicitly unqualified |
| Pending draft: `healthmd-cli/v0.1.0-alpha.7` | Maintainer-visible metadata: `draft=true`, `published_at=null`, zero assets, target `d62741ff917970fac0513691faeaf02fa809d593` | Not installable; a tag or source candidate is not publication |
| Qualified stable | None; the [mobile qualification ledger](mobile-compatibility.md) is still pending | Do not claim stable readiness from download availability or a connectivity smoke |

Alpha.6 has five portable desktop archives (macOS arm64/x86_64, Linux arm64/x86_64, Windows
x86_64), two macOS DMGs, each archive/DMG's `.sha256`, both installers, `healthmd.rb`,
`release-identities.json`, `sha256.sum`, and `sha256.sum.sigstore.json`. Every required payload
and sidecar is named in the checksum manifest. The tap's four archive URLs and hashes match
that manifest. The published alpha.6 tag's MCP catalog contains 19 tools; development contains
21, adding two unreleased full-corpus raw-artifact tools. Alpha.6 binaries remain wait-only;
alpha.7 source enables the enrolled-iPhone APNs nudge. Android is still wait-only.

## Regression and live evidence

Website CI runs the deterministic behavior tests in
`apps/cli/scripts/test_audit_release_availability.py`, then the live read-only audit in
`apps/cli/scripts/audit-release-availability.py`. Both are part of the final Website CI gate.
The audited advertised version is recorded in `release-availability.json`; the checker also
requires the README shell/PowerShell install examples and consumer skill source checkout to
match. Website tests check the new v8 skill and checksum-backed manifests while preserving
immutable v1–v7 bytes (v7 retains its historical incorrect claims; consumers must follow the
manifest's latest version for corrected guidance).

The behavioral tests reject drafts even with assets, wrong tags, absent publication timestamps,
missing/empty/incomplete/misdirected assets, duplicate assets or checksum entries, missing
checksum coverage, stale tap versions/URLs/hashes, and newly public releases still documented
as pending. The mocked audit verifies that only metadata, checksums, and formula content are
read—not installers or binaries. Live requests have timeouts and response-size limits.

API reference: [Get a release by tag name](https://docs.github.com/en/rest/releases/releases#get-a-release-by-tag-name).
Drafts may be invisible to public or read-only tokens: 404 means **not publicly available**, not
proof of the draft's existence or its asset count. The dated maintainer audit above provides that
separate evidence. API/network failures fail the check rather than silently invent availability.

This audit checks **availability**, not cryptographic authenticity, actual archive contents,
runtime behavior, device compatibility, or OS qualification. Users must still perform the
README's signature/checksum and publisher checks before execution. Physical qualification
remains a separate retained-evidence gate; no new device QA is asserted by this correction.

## Updating advertised versions

Before changing install examples, require a non-draft published release, nonempty uploaded
required assets and signed checksum inventory. Update the JSON snapshot, README, website
(including translations/blogs), and consumer skill together, preserving historical skill versions.
Re-run the Actions availability and website checks on the exact source SHA. Do not publish a
draft, bypass release qualification, use `/releases/latest`, or reset local credentials/jobs to
make an availability check pass. This documentation correction changes no public schema,
protocol, binary version, capability classification, or local data.
