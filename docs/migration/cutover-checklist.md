# Monorepo cutover checklist

Validation evidence and operator-owned blockers are recorded in [`cutover-audit.md`](cutover-audit.md).

## Before opening the migration pull request

- [x] Confirm `chore/monorepo-foundation` is pushed without force and tracked by PR [#89](https://github.com/CodyBontecou/health-md/pull/89).
- [x] Confirm the source revisions in `source-revisions.md` still match the frozen repositories.
- [x] Review all commit maps and merge parents.
- [x] Confirm no secret, signing file, machine-specific source path, or generated build directory was imported.
- [x] Run the Apple, Android, CLI, and website checks documented in `docs/architecture/monorepo.md`.

## GitHub configuration

- [x] Review repository and environment secrets required by Apple, crates.io, Homebrew, and future Android release jobs. Missing operator-provided values are listed in `cutover-audit.md`.
- [x] Protect `main` with the stable `Apple CI`, `Android CI`, `CLI CI`, and `Website CI` GitHub Actions checks.
- [x] Confirm the self-hosted Apple runner checks out the monorepo and executes from `apps/apple`.
- [x] Confirm CLI release publication is disabled on PR plans, tags are limited to `healthmd-cli/v*`, and created releases set `make_latest=false`.
- [x] Confirm Apple release jobs skip non-`v*` GitHub Releases.
- [x] Transfer relevant open issues from the Android repository (CSV decimal-separator report is now [#90](https://github.com/CodyBontecou/health-md/issues/90)).
- [ ] Resolve or rebase Apple pull requests that predate the path move.

## Deployments

- [x] Connect the Vercel `website` project to `CodyBontecou/health-md` and set its Root Directory to `apps/website`.
- [x] Verify the Vercel preview, canonical redirects, security/cache headers, docs, blog, sitemap/robots, and visualization index/deep routes.
- [ ] Run Apple release workflows in dry-run mode from an exact `v*` tag/release candidate.
- [x] Run a CLI cargo-dist plan using an exact `healthmd-cli/v*` tag.
- [x] Validate Android Play configuration from `apps/android` before adding a release workflow.

## External integrations

- [x] Keep the Obsidian plugin in its existing repository.
- [x] Verify `apps/website/external-sources.json` points at the intended plugin revision.
- [x] Update badges, documentation, package metadata, and installation instructions to the monorepo URLs.
- [x] Verify external repository-dispatch senders still target `CodyBontecou/health-md` (no senders exist in the audited repositories).

## After merge

- [ ] Fresh-clone `CodyBontecou/health-md` and run component smoke checks from the final filesystem layout.
- [ ] Change the old CLI, Android, and website repositories to read-only notices pointing at their new paths.
- [ ] Preserve old releases, issues, pull requests, stars, and permalinks; do not delete source repositories.
- [ ] Disable duplicate CI/deployment jobs in old repositories.
- [ ] Monitor the first main-branch CI run and first deployment for each component.
- [ ] Extract shared contracts only in a later, separately reviewed change.
