# Monorepo cutover audit

Last updated: 2026-07-24

This document records cutover evidence and outstanding operator-owned configuration. It contains names and statuses only—never secret values or signing material.

## Source and history integrity

- Frozen remote `main` revisions still match `source-revisions.md`:
  - Apple: `a968183011e29b07224739920e8b5305928cb49f`
  - CLI: `0905f1278644d2b17d1827d5af0f3fa34e7401a8`
  - Android: `95e7716809296ff29331a0f1d706dc7948c0d1e3`
  - Website: `7eb4a5038d1131b7fa110865448bdb6f3c467ecb`
- Commit maps are complete, unique, and reachable from their recorded rewritten heads: CLI 2 commits, Android 99 commits, website 94 commits.
- Import commits have the intended rewritten head as their second parent: `648b2bc1`, `f1c5e894`, and `c148771d`.
- `git fsck --no-dangling`, workflow YAML parsing, and `actionlint` pass.
- No generated build directory, environment file, signing file, service-account key, or file larger than 10 MiB is tracked at the imported tip.
- Machine-specific source and credential paths found in imported documentation and Fastlane configuration were replaced with monorepo-relative or environment-based paths.

## Component validation

- Apple: project/package resolution, focused monorepo workflow and release preflight tests, generated export documentation, and 235 local documentation links pass. The complete macOS test run did not finish within its timeout because Xcode repeatedly queried a passcode-locked physical device.
- CLI: formatting, Cargo metadata, exact `healthmd-cli/v0.1.0-alpha.1` cargo-dist planning, and all workspace tests pass.
- Android: unit/direct-protocol tests pass. Release prerequisites pass with ignored local signing material and the external Play service-account file. `:app:bundleRelease` produced a signed AAB, `jarsigner -verify` passed, and `publishReleaseBundle --dry-run` resolved successfully without uploading. Service-account access to `com.healthmd.android` was verified by creating and immediately deleting an empty temporary Play edit; no store metadata or build was uploaded.
- Website: tests, reference checks, documentation checks, reproducible external-plugin generation, and the production build pass.

## GitHub configuration audit

The canonical repository currently has no branch protection rule, repository ruleset, or GitHub environment.

Apple workflow secret names are present in `CodyBontecou/health-md`. The following release configuration remains incomplete:

- CLI: `CARGO_REGISTRY_TOKEN` and `HOMEBREW_TAP_TOKEN` are not configured. The `crates-io` environment referenced by the workflow does not exist yet.
- Android: no Play release workflow has been added. The old Android repository has campaign-attribution build secrets, but GitHub does not expose secret values for transfer. A future `google-play` environment needs `PLAY_CONSOLE_KEY_JSON` plus signing credentials before Android publishing can move to this repository.

Open work that predates the path move:

- Apple pull request [#54](https://github.com/CodyBontecou/health-md/pull/54)
- Apple pull request [#75](https://github.com/CodyBontecou/health-md/pull/75)
- Android issue [health-md-android#8](https://github.com/CodyBontecou/health-md-android/issues/8)

Required checks should be configured only after the migration PR has produced the final check contexts. This avoids protecting `main` with guessed or stale names.

## Vercel audit

The Isotech Vercel project `website` (`prj_g3o7atMD9Q8TOGoDbgFpTrCiK38B`) serves `healthmd.app`. During PR [#89](https://github.com/CodyBontecou/health-md/pull/89), its Git connection was switched from `CodyBontecou/obsidianhealth` to `CodyBontecou/health-md` on `main` and its Root Directory was set to `apps/website` in the same cutover sequence. A production-equivalent preview remains required before merge.

## External integration audit

- `apps/website/external-sources.json` pins `CodyBontecou/health-md-visualizations` at `21b66a3442e30d2fd57146b8e7260e60a9d46035`, which matches the external repository's current remote `main`.
- The external plugin remains outside the monorepo.
- No repository-dispatch sender was found in the canonical, frozen CLI, Android, website, or external plugin repositories. The website receiver remains on `CodyBontecou/health-md`.
- Current component badges, issue links, Cargo metadata, clone instructions, and installation links point to the canonical monorepo or the intentionally external plugin repository.
