# Release QA

Automated checks are necessary but do not replace a physical iPhone run against the exact Health.md
build advertised by a release.

## Automated gate

```bash
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check --workspace --all-features --locked
dist generate --check
dist plan
```

CI must pass on macOS, Ubuntu, and Windows. Verify the release archive's checksum and run its
`healthmd --version`, `healthmd --help`, and isolated `healthmd direct devices` smoke tests.

## Physical iPhone gate

Use a disposable destination and test account/data policy appropriate for sensitive health data.
Never attach raw output to an issue or CI log.

1. Pair on LAN with a generated code; reject a wrong code and an untrusted peer.
2. Reconnect without a code, list/select multiple devices, unpair both sides, and explicitly test
   `reset-trust --confirm` only with disposable trust.
3. Repeat status and a raw export through a Tailscale IPv4 address.
4. Exercise protected-data unavailable, app backgrounding, local-network denial, timeout, and
   reconnect behavior.
5. Export one day, seven days, complete-empty data, warning-only data, and an honest partial result.
6. Run summary and lossless extraction with category, metric, object, and JSON Pointer selectors;
   confirm partial extraction emits no retained values without `--allow-partial`.
7. Interrupt during a multi-partition raw job, inspect `status --job`, resume, compare the final
   digest/result, and test explicit cancellation plus cancellation-pending delivery.
8. On macOS and Linux, test overwrite, append, both Markdown merge modes, nested directories,
   duplicate/case/Unicode-alias paths, symlink ancestors/files, destination mutation, low disk, and
   interruption between destination commit and final confirmation.
9. On Windows, verify status/raw/extract/resume/cancel and the deterministic protocol-v1 rejection
   of generated-file destinations.
10. Confirm stdout contains only the documented JSON/result stream, stderr contains no health
    payload, and private state/output permissions are appropriate on each platform.

Record the iPhone app version/build, CLI version, source commit, OS versions, architecture, network
path, commands, job IDs, statuses, and artifact digests. Record counts and diagnostics only—never
health values.
