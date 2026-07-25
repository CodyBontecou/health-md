# Monorepo cutover checklist

## Before opening the migration pull request

- [ ] Confirm `chore/monorepo-foundation` is pushed without force.
- [ ] Confirm the source revisions in `source-revisions.md` still match the frozen repositories.
- [ ] Review all commit maps and merge parents.
- [ ] Confirm no secret, signing file, local path, or generated build directory was imported.
- [ ] Run the Apple, Android, CLI, and website checks documented in `docs/architecture/monorepo.md`.

## GitHub configuration

- [ ] Review repository and environment secrets required by Apple, crates.io, Homebrew, and future Android release jobs.
- [ ] Update required status checks for renamed `Apple CI` jobs and new component workflows.
- [ ] Confirm self-hosted Apple runners accept `apps/apple` as their working directory.
- [ ] Confirm CLI releases trigger only from `healthmd-cli/v*` tags and do not become the repository-wide latest release.
- [ ] Confirm Apple release jobs skip non-`v*` GitHub Releases.
- [ ] Transfer relevant open issues from the Android repository.
- [ ] Resolve or rebase Apple pull requests that predate the path move.

## Deployments

- [ ] Set the Vercel project Root Directory to `apps/website`.
- [ ] Verify a Vercel preview, redirects, headers, docs, blog, and visualization routes.
- [ ] Run Apple release workflows in dry-run mode from an exact `v*` tag/release candidate.
- [ ] Run a CLI cargo-dist plan using an exact `healthmd-cli/v*` tag.
- [ ] Validate Android Play configuration from `apps/android` before adding a release workflow.

## External integrations

- [ ] Keep the Obsidian plugin in its existing repository.
- [ ] Verify `apps/website/external-sources.json` points at the intended plugin revision.
- [ ] Update badges, documentation, package metadata, and installation instructions to the monorepo URLs.
- [ ] Verify external repository-dispatch senders still target `CodyBontecou/health-md`.

## After merge

- [ ] Fresh-clone `CodyBontecou/health-md` and run component smoke checks from the final filesystem layout.
- [ ] Change the old CLI, Android, and website repositories to read-only notices pointing at their new paths.
- [ ] Preserve old releases, issues, pull requests, stars, and permalinks; do not delete source repositories.
- [ ] Disable duplicate CI/deployment jobs in old repositories.
- [ ] Monitor the first main-branch CI run and first deployment for each component.
- [ ] Extract shared contracts only in a later, separately reviewed change.
