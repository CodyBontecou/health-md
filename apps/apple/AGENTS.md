# Health.md Agent Instructions

## Export schema contract

Health.md export files are a public, long-lived contract for Obsidian, JSON, CSV, and downstream automation.

When editing any exporter, metric mapping, unit mapping, data dictionary, frontmatter key, CSV row/header, or JSON shape:

1. Read `docs/features/export-schema.md`.
2. Decide whether the public export schema changed.
3. If it changed, bump `HealthMdExportSchema.version` in `HealthMd/Shared/Export/HealthMetricsDictionary.swift`.
4. Run `make update-export-schema-signature` to create/update the versioned fixture.
5. Review the fixture diff under `HealthMdTests/Fixtures/Export/export_schema_signature_v<version>.json`.
6. Run exporter contract tests before finishing.

Do **not** update the schema signature fixture just to silence CI. The test intentionally refuses to overwrite a changed fingerprint for the same `schema_version`; bump the schema version for intentional schema changes.

## App Store release synchronization

Git is the release ledger; App Store Connect (ASC) is a deployment target. A release is not synchronized unless the Xcode version/build, source commit, Git tag, GitHub Release, ASC version/build, changelog, in-app release notes, and App Store release notes agree.

### Canonical release contract

For every iOS or macOS App Store release:

1. Release only from a clean worktree whose intended source is committed and pushed to `origin/main`. Never archive or upload a dirty working tree.
2. Confirm the requested version matches `MARKETING_VERSION` and choose a remote-safe build number using `asc builds next-build-number`. Commit the final `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` before building.
3. Update and review all relevant customer-facing records, including `CHANGELOG.md`, `HealthMd/iOS/ReleaseNotes.swift`, and `fastlane/metadata/en-US/release_notes.txt`.
4. Before uploading or submitting to ASC, create a **draft** GitHub Release named `v<version>` targeting the exact commit being built. Its release body is the canonical customer-facing release note. Creating the draft first preserves source provenance without triggering the published-release workflows.
5. Run `asc validate --app "$ASC_APP_ID" --version "<version>" --platform <IOS|MAC_OS>` and resolve blocking diagnostics.
6. Upload/submit through the repository's canonical release command or workflow. When a manual ASC path is necessary, use waiting/discovery-aware commands such as `asc builds upload --wait` or `asc publish appstore --wait --submit --confirm`; never treat an upload operation ID as an ASC build ID.
7. Leave the GitHub Release as a draft while the submission is under review. The ASC approval webhook and `.github/workflows/announce.yml` should publish/promote the matching release and perform downstream announcements.

Do not maintain competing release paths. Once a repository wrapper is available (for example, a future `make release-ios VERSION=x.y.z`), use it instead of running raw ASC publication commands.

### Drift detection and reconciliation

- An ASC fallback in `.github/workflows/announce.yml` may keep announcements running, but it does **not** reconcile a missing Git tag or GitHub Release.
- Release automation should fail loudly or open a tracking issue when an ASC version has no matching `v<version>` Git tag and GitHub Release.
- A release-sync audit should compare ASC versions/builds with Git tags, GitHub Releases, and the version/build stored at each tagged commit.
- Never repair history by tagging arbitrary current `main`. First identify the exact commit used to build the uploaded binary. If the binary came from an uncommitted worktree and exact provenance cannot be recovered, record that gap explicitly and ask the user before creating a best-effort historical release.
- If drift is discovered while a new ASC version is still in preparation, pause submission and make that version the first fully synchronized release before continuing.
