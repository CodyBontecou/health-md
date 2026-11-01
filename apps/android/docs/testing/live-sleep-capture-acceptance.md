# Read-only physical sleep capture acceptance

This opt-in probe reads owner-prepared synthetic sleep records through the real Health Connect client and `HealthConnectManager`, then prepares explicit Android-v6 exports with the packaged Rust core. It never inserts, updates or deletes Health Connect records. It does not enable Morning ends in production settings or qualify production admission, complete recovery, source archives, other providers or accessibility.

Supply synthetic wake dates and the captured IANA calendar timezone. The test reads the adjacent overnight interval and checks preceding notes for misplaced/duplicate ownership; it exports only records owned by the supplied dates. At least one overnight session must exist. Empty data, missing permission, incomplete day coverage and source-clock differences fail rather than count as acceptance.

```sh
HEALTHMD_LIVE_SLEEP_DATES="2026-10-19" \
HEALTHMD_LIVE_SLEEP_ZONE="America/New_York" \
HEALTHMD_OBSIDIAN_PLUGIN_REPO="/absolute/path/to/pinned/health-md-visualizations" \
  apps/android/scripts/run-live-sleep-acceptance.sh
```

The date above is an example, not a known device fixture. Use the owner's actual synthetic dates. The designated Pixel 7 must be connected, unlocked and ready for Health Connect reads. The reader checkout must be clean at the website's exact `external-sources.json` pin, with its dependencies installed. Run from a shell with the Android SDK configured.

The runner refuses existing `.e2e` packages, builds and installs isolated app/test APKs without replacement, and grants only sleep read permission plus historical read permission when the supplied interval needs it. Installation-path checks protect a concurrently replaced package during cleanup. Production packages and their settings are untouched. The instrumentation test is skipped in ordinary CI unless explicitly enabled; successful compilation or a skip is not provider acceptance.

The independent SDK read establishes source identities, exact intervals, supplied/absent offsets, titles, notes and origins. Native capture must return every requested/negative-control day, place each target session only on its wake date and retain the complete additive duration without millisecond truncation. Both metadata variants produce four distinct formats. The pinned public readers verify every owner/format/metadata combination, mandatory attribution authority and complete interval multiplicity against the SDK baseline. All four formats, including Markdown, must retain each native parent ID and its source fields. Complete parent and stage objects must also match the native JSON companion. Machine summaries and metadata-bearing Markdown retain the precise additive total; metadata-off Markdown may round its visible summary while preserving complete source records. The probe does not independently qualify every stage-summary chart or large source archive.

Evidence is private local output under ignored `.pi/live-sleep-acceptance/<run>/`, with mode-restricted directories, requested dates/timezone, source/APK hashes, SDK baseline, native artifacts, instrumentation output and consumer verification. `HEALTHMD_LIVE_SLEEP_OUTPUT` may select a new private local output directory. No health payload is uploaded. The runner removes only its own unchanged isolated APK installations; retain required evidence outside any worktree before retiring it.

Full feature acceptance remains governed by the successor profile contract and the production gate ledger. This probe has not passed until real execution produces both native and pinned-consumer receipts; synthetic verifier controls and APK builds are separate evidence.
