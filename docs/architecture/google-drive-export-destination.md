# Google Drive export destination

Status: implementation contract; public capability remains `planned`

Release documentation: [product and privacy boundaries](../features/google-drive-export.md), [customer guide](../../apps/website/docs-src/src/content/docs/guides/google-drive-export.md), and [OAuth/store/release checklist](../qa/google-drive-export-release-checklist.md).

## Outcome

Health.md exposes **Upload to Google Drive** as a first-class export destination on Apple and Android. A user authorizes one Google account, selects a writable Drive folder with Google's mobile Picker, binds that destination to an export profile, and can run the same rendered export manually or from that profile's schedule.

Health data and OAuth credentials travel directly between the installed app and Google. Health.md-operated services do not receive or retain them. Google receives the exported health files and applies its own retention, account, Workspace, and sharing controls.

This is a destination-layer feature:

- existing Apple v8 and Android frozen-v4/analytical-v5 renderers remain authoritative;
- relative paths, media types, write modes, and bytes remain unchanged;
- the public health export schema does not change;
- the direct iPhone/Android-to-CLI protocols do not carry Google credentials or destination authority;
- Files/SAF provider exports remain separate and are never migrated automatically.

## Platform-neutral capability

The destination has identical semantic behavior on Apple and Android:

- OAuth Drive scope: `https://www.googleapis.com/auth/drive.file` only;
- Google mobile Picker folder selection;
- account authority identified by Drive `user.permissionId`, not display name or email;
- folder authority identified by immutable Drive folder ID;
- My Drive and Shared Drive folders are represented by the same destination kind;
- stable file/folder IDs, never names alone, identify managed remote objects;
- overwrite, append, Markdown update, Daily Note injection, loose files, archives, rollups, dictionaries, sidecars, individual entries, and raw snapshots use existing renderer semantics;
- manual and scheduled work enter one destination runner;
- operation history reports complete, partial, conflict, and reauthorization outcomes honestly;
- disconnect removes local authority and credentials but does not delete remote files.

Native authentication and background mechanics may differ where the operating systems or Google SDK differ.

## External API constraints

Two guarantees are not available under the local-first/no-token-server boundary:

1. Google Play services does not document exposing a durable refresh token to an Android native app. Its offline authorization code is specifically for confidential server exchange. Android scheduled work therefore attempts silent `AuthorizationClient` authorization for the bound account. If Google requires a resolution, the operation enters `reauthorization_required`, posts an actionable notification, and resumes its existing journal after foreground authorization. It never recaptures or redirects to another account.
2. Drive v3 does not document an ETag/`If-Match` compare-and-swap contract for `files.update`. Health.md detects conflicts with exact-ID version/checksum preflight and postflight checks, but cannot promise a race-free replacement against a concurrent non-Health.md editor. No Health.md lock server is introduced.

These limitations must be represented in UI, tests, and release documentation rather than hidden by fallback behavior.

## Google Cloud configuration

Production and test builds use separate Google Cloud projects. Each project enables the Google Drive API and Google Picker API and has separate iOS and Android OAuth clients.

No native client secret is shipped.

Apple configuration supplies a public iOS client ID and registered custom redirect URI. Apple authorization uses `ASWebAuthenticationSession`, authorization code, state, PKCE S256, `access_type=offline`, `prompt=consent`, `trigger_onepick=true`, `allow_folder_selection=true`, and folder MIME filtering. Refresh tokens live only in Keychain.

Android uses Google Play services `AuthorizationClient` and Picker resource parameters, including `PICKER_OAUTH_TRIGGER`, `PICKER_ALLOW_FOLDER_SELECTION`, and `PICKER_MIMETYPES`. It opts out of previously granted scopes so the returned authorization remains Drive-file-only. Bound Android account identity is kept in encrypted private storage and independently verified with Drive `about.get`.

Missing build configuration makes the destination visible but unavailable with `configuration_missing`; it never falls back to Files, SAF, an API endpoint, or another account.

## Data model

### Generated export bundle

Each platform exposes an internal destination-neutral immutable bundle before Drive network effects:

- operation and artifact IDs;
- source dates and profile/source identity;
- frozen settings and renderer/engine pins;
- normalized safe relative path;
- media type and existing write intent;
- immutable fragment bytes or protected file URL;
- byte count and SHA-256;
- complete path-collision validation.

Direct/CLI models may adapt from this bundle but are not its authority. Drive never rerenders, normalizes UTF-8, changes line endings, or changes a public document.

### Destination binding

A versioned non-secret destination record contains:

- local destination ID;
- secure credential/account-reference ID;
- Drive `permissionId` account authority;
- selected folder ID;
- optional Shared Drive ID and resource key;
- privacy-safe account and folder labels;
- last validated folder capabilities and timestamp.

A profile stores only the local destination ID. OAuth tokens, Android account names, upload-session URIs, and rendered health bytes do not appear in profile JSON, Shared Setup, analytics, history, or direct protocols.

### Managed object binding

A managed object record contains:

- destination ID and normalized relative-path hash;
- exact file/folder ID and parent ID;
- expected name and MIME type;
- optional resource key;
- last verified Drive version, byte count, and checksums.

Names and `appProperties` are reconciliation hints, not authority. Duplicate accessible bindings fail closed.

### Operation journal

Before the first Drive mutation, a protected no-backup journal durably records:

- version, operation/profile/source/date identity;
- destination fingerprint and immutable bundle digest;
- every staged final-byte file, count, MIME type, and SHA-256;
- every generated remote folder/file ID;
- exact parent/object bindings and remote baseline metadata;
- resumable upload-session URI and acknowledged byte offset;
- per-artifact phase and final history/accounting acknowledgement.

Credentials are excluded. Journals and spools use atomic replacement, file and parent-directory synchronization, bounded retention, backup exclusion, and platform file protection. Missing/corrupt state fails closed; it never continues the same remote operation by recapturing different bytes.

## Drive API behavior

All applicable calls set `supportsAllDrives=true` and attach `X-Goog-Drive-Resource-Keys` when keys are known.

A selected folder is accepted only when exact-ID metadata confirms folder MIME type and `capabilities.canAddChildren`. Shared Drive permissions are capability-driven, not ownership-driven.

New objects use IDs from `files.generateIds`. Generated IDs are persisted before create, allowing an ambiguous response to be reconciled with `files.get` without creating a duplicate.

Content uploads use resumable sessions. Session URIs are treated as bearer-equivalent secrets. Chunk offsets are recovered with the documented empty `PUT` status probe. An expired session restarts against the same staged bytes and reserved object identity.

Completion requires exact-ID metadata and remote SHA-256/size verification where Drive exposes them. `appProperties` include only privacy-safe Health.md ownership/version/path-hash markers and intended content hash.

## Write and conflict semantics

For overwrite of a new object, upload the immutable rendered bytes.

For replacement of an existing object, record its exact ID, parent, version, size, and checksum; recheck immediately before upload; stop on change; upload the complete staged file; then verify version and checksum.

For append or Markdown update:

1. Download the exact mapped baseline once.
2. Persist baseline object identity, parent, version, and checksum.
3. Apply the existing authoritative append or Markdown merger locally once.
4. Persist the complete final bytes and digest before mutation.
5. Recheck baseline metadata immediately before upload.
6. Upload the complete final file, never a fragment.
7. Reconcile ambiguous responses against the intended checksum.
8. Verify postflight metadata/checksum.

Daily Note injection follows the same baseline/final-byte protocol while preserving the existing preamble-aware merger. Non-Markdown Update retains the existing overwrite behavior.

A changed, renamed, moved, trashed, duplicated, or inaccessible **managed** object enters `remote_conflict` or `folder_unavailable`; Health.md does not silently follow it outside the configured hierarchy. Existing files created through Files/SAF, another app, or another OAuth project are not adopted automatically. An accessible unowned same-name object fails closed. Under `drive.file`, Google can hide an unauthorized child and Drive permits duplicate names, so an invisible same-name object cannot be detected; product copy recommends a new or empty app-managed destination and must not promise name uniqueness. Scheduled work never force-replaces a conflict. A foreground recovery surface may explicitly rebind, create a conflict copy, or replace after showing the exact destination.

Drive cannot atomically mutate multiple files. Health.md preflights the complete bundle, commits in deterministic path order, checkpoints each verified artifact, and reports visible partial completion. Retry resumes the exact remaining frontier.

## Scheduling and recovery

Pending work freezes the destination ID/fingerprint with its profile/settings/renderer identity. Editing or activating another profile cannot redirect it.

Apple uses existing best-effort background-task admission plus silent refresh-token renewal. Android workers request network connectivity and silently authorize the exact bound account. If a user resolution is needed, workers stop automatic retries, retain the exact journal, mark `reauthorization_required`, and notify the user.

Manual and scheduled operations targeting one destination are serialized locally. Cross-device writes use the same preflight/postflight conflict detection but cannot be globally locked without a server.

## Persistence compatibility

Drive-capable builds use versioned destination/profile envelopes with tolerant per-record decoding. Unknown destination kinds remain opaque, visible, and unrunnable. One unknown or corrupt record cannot erase unrelated profiles or trigger legacy fallback.

Existing profile and destination payloads migrate additively. Drive bindings exist only in the new envelope. Existing legacy schedules are disabled when their active destination can no longer be represented safely. Already-shipped older binaries cannot become Drive-aware, so downgrade behavior is tested and documented but cannot guarantee that an old build exposes Drive profiles.

Shared Setup includes portable output settings only. It omits Google account identity, folder IDs/names, credentials, resource keys, managed-object mappings, and journal state; imported schedules remain disabled until a local destination is selected.

CLI/MCP exports may use a Drive profile's frozen output settings only when the caller explicitly chooses the desktop destination. They never upload to Drive as a side effect or receive Google authority.

## Error taxonomy

Both platforms use the same privacy-safe semantic IDs:

- `configuration_missing`
- `reauthorization_required`
- `account_mismatch`
- `folder_unavailable`
- `permission_denied`
- `remote_conflict`
- `ambiguous_commit`
- `quota_exceeded`
- `rate_limited`
- `checksum_mismatch`
- `partial_completion`

HTTP response bodies, tokens, account names, file/folder IDs, paths, and exported contents are excluded from user analytics and ordinary logs.

## Acceptance gates

Documentation completion does not make the destination available. `destination.google-drive` remains `planned` until both platform integrations, production-shaped physical-device testing, external OAuth/store reviews, and the [release checklist](../qa/google-drive-export-release-checklist.md) pass.

The integration is complete only when:

- Apple and Android use the official mobile Picker and `drive.file` only;
- every existing export artifact and write mode has byte-equivalence coverage;
- manual, profile, both schedule paths, history, retry, disconnect, Shared Setup, automation, raw export, and direct CLI boundaries are explicit;
- crash injection before/after every journal/upload/history checkpoint creates no duplicate app-owned objects and never re-applies append/merge fragments;
- account mismatch, revocation, folder capability loss, Shared Drive behavior, duplicate names, move/rename/trash, offline, quota, 401/403/404/429/5xx, cancellation, session expiry, and checksum mismatch are covered;
- contract, Apple, Android, core, CLI/MCP, website, localization, analytics, privacy, and manifest gates pass;
- physical iPhone and Pixel testing uses production-shaped OAuth clients;
- Google OAuth publishing, App Store privacy, Play Data safety, and review instructions are complete.
