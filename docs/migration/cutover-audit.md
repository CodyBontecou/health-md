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

- Apple: project/package resolution, focused monorepo workflow and release preflight tests, generated export documentation, and 235 local documentation links pass. The complete macOS test run did not finish within its timeout because Xcode repeatedly queried a passcode-locked physical device. Registered release workflow paths remain `release-ios.yml` and `release-macos.yml`; displayed names are Apple-specific. No-publish release-candidate runs [iOS 30142086722](https://github.com/CodyBontecou/health-md/actions/runs/30142086722) and [macOS 30142086734](https://github.com/CodyBontecou/health-md/actions/runs/30142086734) succeeded at commit `61364d1e` with `release_tag=v3.0.2` and `dry_run=true`; archive/export/signing/notarization passed while ASC upload, review submission, release creation, and asset attachment were skipped.
- CLI: formatting, Cargo metadata, exact `healthmd-cli/v0.1.0-alpha.1` cargo-dist planning, and all workspace tests pass.
- Android: unit/direct-protocol tests pass. Release prerequisites pass with ignored local signing material and the external Play service-account file. `:app:bundleRelease` produced a signed AAB, `jarsigner -verify` passed, and `publishReleaseBundle --dry-run` resolved successfully without uploading. Service-account access to `com.healthmd.android` was verified by creating and immediately deleting an empty temporary Play edit; no store metadata or build was uploaded.
- Website: tests, reference checks, documentation checks, reproducible external-plugin generation, and the production build pass.

## GitHub configuration audit

The canonical repository's `main` branch now requires strict, up-to-date `Apple CI`, `Android CI`, `CLI CI`, and `Website CI` checks from the GitHub Actions app. Conversation resolution is required; force pushes and branch deletion are disabled. No review count or admin enforcement was added.

Apple workflow secret names are present in `CodyBontecou/health-md`. Two tag-restricted environments were created: `crates-io` accepts only `healthmd-cli/v*` tags, and `google-play` accepts only `android/v*` tags. The following operator-provided release configuration remains incomplete:

- CLI: `CARGO_REGISTRY_TOKEN` is not configured in `crates-io`, and repository secret `HOMEBREW_TAP_TOKEN` is not configured.
- Android: no Play release workflow has been added. The old Android repository has campaign-attribution build secrets, but GitHub does not expose secret values for transfer. The `google-play` environment still needs `PLAY_CONSOLE_KEY_JSON` plus signing credentials before Android publishing can move to this repository.

Open work that predates the path move:

- Apple pull request [#54](https://github.com/CodyBontecou/health-md/pull/54)
- Apple pull request [#75](https://github.com/CodyBontecou/health-md/pull/75)
- Android CSV decimal-separator issue transferred from `health-md-android#8` to canonical issue [#90](https://github.com/CodyBontecou/health-md/issues/90) with its discussion preserved and `bug` / `component:android` labels applied

Migration notes were added to Apple PRs #54 and #75. Their branches must be rebased and paths relocated after PR #89 lands; neither was closed or rewritten during cutover.

## Vercel audit

The Isotech Vercel project `website` (`prj_g3o7atMD9Q8TOGoDbgFpTrCiK38B`) serves `healthmd.app`. During PR [#89](https://github.com/CodyBontecou/health-md/pull/89), its Git connection was switched from `CodyBontecou/obsidianhealth` to `CodyBontecou/health-md` on `main` and its Root Directory was set to `apps/website` in the same cutover sequence.

Preview deployment `dpl_66nusiXB13StDZXhXHZDbodAEXri` for commit `8c1306b6` passed production-equivalent checks: root/docs/blog/visualization pages and a deep visualization route returned 200; `/docs`, `/blog`, and `/visualizations` returned canonical 308 redirects; sitemap and robots were present; security headers applied to clean directory routes; and docs Astro assets retained immutable caching.

## External integration audit

- `apps/website/external-sources.json` pins `CodyBontecou/health-md-visualizations` at `21b66a3442e30d2fd57146b8e7260e60a9d46035`, which matches the external repository's current remote `main`.
- The external plugin remains outside the monorepo.
- No repository-dispatch sender was found in the canonical, frozen CLI, Android, website, or external plugin repositories. The website receiver remains on `CodyBontecou/health-md`.
- Current component badges, issue links, Cargo metadata, clone instructions, and installation links point to the canonical monorepo or the intentionally external plugin repository.
