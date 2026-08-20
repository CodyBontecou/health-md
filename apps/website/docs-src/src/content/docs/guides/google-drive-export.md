---
title: "Upload to Google Drive"
description: "How direct Google Drive export works, what Google receives, how schedules and write modes behave, and how to recover safely."
---

<div class="availability preview">
<strong>Planned · not available until mobile integration and review finish</strong>
<p>This page documents the release behavior in advance. Use the destination only when your Health.md build shows <strong>Upload to Google Drive</strong> as available.</p>
</div>

**Upload to Google Drive** sends the files Health.md already renders directly from your phone to a folder you choose in Google Drive. You authorize one Google account, choose one writable My Drive or Shared Drive folder in Google's Picker, and attach that destination to an export profile.

Google receives the exported health files. Those files can contain highly sensitive health, medication, mental-wellbeing, clinical, location, route, timestamp, attachment, and source details. Google's privacy, retention, sharing, Workspace, region, and administrator controls apply after upload.

Health.md does not send the files or Google credentials through a Health.md health-data or token server. The installed app communicates with Google, and protected credentials stay on the device.

## Direct Drive is not Files or SAF

You may already see Google Drive inside Apple Files or Android's Storage Access Framework (SAF). That is a file-provider destination managed by the operating system. **Upload to Google Drive** is separate: it uses Google OAuth, Google's Picker, and the Drive API.

A Files/SAF folder and a direct Drive folder have different permission, history, and recovery records. Health.md never migrates one into the other, silently substitutes one, or falls back to a different destination when configuration is missing.

## Connect an account and folder

1. Choose **Upload to Google Drive** for an export profile.
2. Review the sensitive-data disclosure and continue to Google.
3. Authorize only the `https://www.googleapis.com/auth/drive.file` scope.
4. Select one writable folder in Google's Picker.
5. Confirm the account and folder shown in Health.md.
6. Run a small manual export and inspect it in Drive before enabling a schedule.

The `drive.file` scope is narrower than full Drive access: Health.md can manage files it creates and files you explicitly open or select for the app. It still authorizes highly sensitive files in the selected location.

Health.md binds the destination to Google's stable account permission ID and the folder's immutable Drive ID. Names are only labels. Changing a label does not redirect the binding, and Health.md never silently switches to another signed-in account.

My Drive and Shared Drive use the same destination type when Google reports that the folder can accept children. Shared Drive administrators can change permissions, retention, and access. Health.md checks capabilities rather than assuming that you own the folder.

## Manual and scheduled exports

Manual and scheduled work use the same destination runner and retain the selected profile, account, folder, settings, renderer, and staged bytes.

Schedules are **best effort**. Apple and Android decide when background work can run, so the chosen time is not guaranteed. A locked device, missing network, quota, revoked consent, changed folder permissions, or an operating-system limit can delay or stop a run.

On Android, Google may require you to authorize again in the foreground. Health.md then reports **Reauthorization required**, stops automatic retries, and sends an actionable notification. Open Health.md, authorize the exact bound account, and resume. Health.md keeps the existing operation; it does not recapture the dates, choose another account, or silently start over.

## Formats and write modes

Direct Drive carries the same bytes and paths produced for the profile. It does not change the public health export schema. It supports loose files, archives, daily files, rollups, dictionaries, sidecars, individual entries, raw snapshots, and Daily Notes.

| Mode | Remote behavior |
|---|---|
| New or overwrite | Uploads the complete immutable rendered file. Existing managed files are checked before replacement. |
| Append | Downloads the exact mapped file, appends locally once, then uploads the complete final file—not an append fragment. |
| Markdown Update | Downloads one baseline, applies the existing Markdown merger locally once, and uploads the complete final file. |
| Daily Note injection | Uses the same complete-file baseline and final-byte process while preserving the existing preamble-aware merge. |
| Update for non-Markdown | Keeps the existing overwrite behavior. |

A managed remote file is identified by its stable ID, not its name alone. A moved, renamed, trashed, duplicated, inaccessible, or concurrently changed file stops with a conflict or folder error instead of creating a parallel file silently.

## Conflicts and partial exports

Google Drive does not offer Health.md a documented atomic compare-and-swap for file replacement. Health.md checks file version and checksum immediately before and after an update, but another editor can still race those checks. Cross-device exports cannot be globally locked because Health.md operates no lock server.

Drive also cannot atomically commit several files as one transaction. Health.md preflights the complete bundle, writes in deterministic path order, and records each verified file. If a later file fails, earlier files stay visible and history reports **Partial completion**. Retry the same operation to resume its staged remaining files; do not assume the whole bundle rolled back.

Scheduled work never force-replaces a conflict. In the foreground, inspect the exact destination before choosing an offered recovery such as rebind, conflict copy, or replace.

## Disconnect and delete

Disconnecting Google Drive removes local credentials and authority and prevents future scheduled uploads. It **does not delete remote files**. Delete or retain exported files with Google Drive controls. A Shared Drive's administrators and retention rules may limit deletion.

Revoking Health.md in your Google Account also stops future access but does not remove files already stored in Drive. Reconnect and choose a folder again before resuming exports.

## Shared Setup, CLI, and MCP

Shared Setup copies portable output settings only. It never includes Google account identity, folder IDs or names, credentials, resource keys, remote file mappings, upload sessions, or operation journals. Imported schedules remain off until the recipient chooses a local destination.

CLI, direct-device, and MCP workflows never receive your Google credentials or Drive folder authority and never upload to Drive as a side effect. They can reuse output settings only when you explicitly choose a validated desktop destination.

## Troubleshooting

| Message or symptom | What to do |
|---|---|
| Configuration missing | Install a correctly configured production build. Direct Drive does not fall back to Files, SAF, an API endpoint, or another account. |
| Reauthorization required | Foreground Health.md, authorize the bound account, and resume the existing operation. |
| Account mismatch | Disconnect and reconnect the intended account; never rely on the displayed email/name alone. |
| Folder unavailable / Permission denied | Check folder access and Shared Drive permissions. Explicitly select a new folder if needed. |
| Remote conflict | Inspect the exact file and use the foreground recovery options. Do not rerun append blindly. |
| Partial completion | Review history and Drive, then retry the same operation to resume remaining files. |
| Ambiguous commit / Checksum mismatch | Do not start another merge. Preserve history and retry only through Health.md's reconciliation path. |
| Quota exceeded / Rate limited / Offline | Wait for connectivity or Google's retry interval. Health.md preserves the operation where safe. |
| Files remain after disconnect | Expected. Delete them in Google Drive if you want and have permission. |

Do not send health exports, OAuth tokens, authorization codes, upload-session links, account names, Drive IDs, or full Drive error bodies in support email or public issues.

## Privacy and related guides

Read the [Privacy Policy](/privacy-policy.html) before connecting Google Drive. See [Export](/docs/export/) for output basics, [Scheduling](/docs/scheduling/) for best-effort background behavior, and [Folder & Vault](/docs/folder-vault/) for operating-system file-provider destinations.
