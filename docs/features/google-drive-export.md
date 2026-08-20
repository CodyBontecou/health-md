# Direct Google Drive export

Status: release documentation for a planned capability

The implementation authority is [Google Drive export destination](../architecture/google-drive-export-destination.md). This document identifies the customer, integration, privacy, and release surfaces that must remain aligned. It does not change an Apple, Android, or public health-data schema.

## Product outcome and boundaries

**Upload to Google Drive** is a first-class mobile destination. A user authorizes one Google account with the `https://www.googleapis.com/auth/drive.file` scope, selects one writable My Drive or Shared Drive folder in Google's Picker, and binds an export profile to that account and immutable folder ID. Manual and best-effort scheduled exports send the existing renderer's bytes directly from the installed app to Google.

This destination is not the Google Drive provider shown inside Apple Files or Android's Storage Access Framework (SAF). Files/SAF grants operating-system access to a provider-backed folder. Direct Google Drive uses Google OAuth, Picker consent, and the Drive API. The two kinds of destination keep separate bindings and history and are never migrated or substituted automatically.

Google receives sensitive exported health files and the request metadata needed to store them. Google's privacy, retention, Workspace, sharing, region, and administrator controls apply to its copy. Health.md operates no health-data upload proxy and no Google token server. OAuth credentials and resumable-session state remain in protected app storage and travel only between the app, platform authorization services, and Google.

The destination does not alter Apple v8, Android frozen-v4, or Android analytical-v5 output. Formats, paths, media types, source dates, write modes, and rendered bytes remain authoritative. The public `healthmd.health_data` schema remains unchanged.

## Binding and consent

A binding consists of one local destination ID, the authorized account's Drive `user.permissionId`, and the Picker-selected folder's immutable Drive ID. Displayed account and folder names are labels, not authority. The app validates that the exact folder can accept children before use and does not silently switch accounts or follow a moved object outside the selected hierarchy.

`drive.file` allows Health.md to access files it creates and files the user explicitly opens or selects for the app. It is narrower than full Drive access, but it still lets Health.md place highly sensitive exports in the selected folder. Consent copy must say this before authorization. No native client secret is embedded.

Health.md manages only files and folders created by, or explicitly authorized to, the same Google OAuth application. It does not adopt same-named exports previously written through Apple Files, Android SAF, another app, or another OAuth project. Users should select a new or otherwise empty destination folder. An accessible unowned same-name object stops the operation. Because `drive.file` can hide an unauthorized child, Drive can still contain an invisible same-name object that Health.md cannot detect; Google Drive permits duplicate names. This provider limitation must be disclosed rather than described as atomic sync.

My Drive and Shared Drive folders are supported under the same destination kind when Drive reports the required capabilities. Shared Drive administrators may restrict uploads, move or delete objects, change access, or enforce retention. Health.md follows capabilities rather than assuming ownership.

## Running exports

Manual exports and schedules enter the same destination runner and preserve the profile, account, folder, settings, renderer, and staged bytes selected when the operation began.

Schedules are best effort, not exact-time guarantees. Apple background admission and protected-data availability can delay or skip work. Android attempts silent authorization for the exact bound account. If Google requires user resolution, Android stops automatic retries, reports `reauthorization_required`, and asks the user to foreground the app. Foreground authorization resumes the existing journal; it does not recapture, change accounts, or redirect to another folder.

## Files, write modes, and conflicts

The destination carries every existing renderer artifact: loose files, archives, daily files, rollups, dictionaries, sidecars, individual entries, raw snapshots, and Daily Notes. Existing overwrite, append, Markdown Update, Daily Note injection, and non-Markdown Update behavior remains in force.

- A new overwrite uploads the immutable rendered bytes.
- Replacing an existing file preflights its exact ID, parent, version, size, and checksum, then verifies the result.
- Append, Markdown Update, and Daily Note injection apply only to an exact Health.md-managed file binding. They download that baseline, merge locally once, stage the complete final file, and upload that complete file. They never upload or replay only a fragment. An ordinary pre-existing Daily Note is not adopted automatically.
- Non-Markdown Update keeps its existing overwrite behavior.

Drive does not provide a documented ETag/`If-Match` compare-and-swap guarantee for `files.update`. Health.md checks versions and checksums before and after a write, but a concurrent editor can still race those checks. A changed, moved, renamed, trashed, duplicated, inaccessible, or ambiguous managed object stops with a conflict or availability result rather than silently creating a parallel file.

Drive cannot atomically commit a multi-file export. Health.md preflights the bundle, writes in deterministic path order, checkpoints each verified file, and reports partial completion honestly. A retry resumes the staged remaining frontier. A user must inspect partial and conflict history before deciding whether to retry, create a conflict copy, rebind, or replace.

## Disconnect, portability, and automation

Disconnect removes local Google authority, credentials, account/folder binding, and the ability to schedule future Drive writes. It does **not** delete files already in Google Drive. Users delete or retain those files with Google Drive controls, subject to Shared Drive policy.

Shared Setup carries portable output settings only. It excludes account identity, folder IDs and names, OAuth credentials, resource keys, remote object mappings, schedules' destination authority, journals, and upload sessions. An imported schedule remains disabled until the recipient selects a local destination.

CLI, direct-device, and MCP flows never receive Google credentials or folder authority and never upload to Drive as a side effect. They may use a profile's output settings only when the caller explicitly chooses and validates a desktop destination.

## Documentation map

- Customer guide: [Upload to Google Drive](../../apps/website/docs-src/src/content/docs/guides/google-drive-export.md)
- Privacy policy: [English source](../../apps/website/privacy-policy.html), with every published legal locale updated in parallel
- OAuth, store disclosure, troubleshooting, and release gates: [Google Drive release checklist](../qa/google-drive-export-release-checklist.md)
- Machine-readable availability: [`destination.google-drive`](../../packages/contracts/product-capabilities.json)

The capability remains `planned` until both platform integrations and every release gate pass. Documentation readiness alone must not promote it to `shared` or `available`.
