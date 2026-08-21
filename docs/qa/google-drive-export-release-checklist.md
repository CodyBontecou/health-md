# Google Drive export release checklist

Owner: documentation, privacy, contract, OAuth, and release reviewers

Capability: `destination.google-drive`

Status: blocked while the capability inventory is `planned`

Use this checklist with the [implementation contract](../architecture/google-drive-export-destination.md) and [cross-platform product description](../features/google-drive-export.md). Record evidence links, project/client identifiers (never secrets), app versions/builds, tester devices, dates, and reviewers in the release issue.

## 1. Google Cloud and OAuth

Use separate production and test Google Cloud projects. For each project:

- [ ] Ownership, billing/quotas, incident contacts, and least-privilege console access are assigned.
- [ ] Google Drive API and Google Picker API are enabled.
- [ ] The OAuth consent screen uses the verified `healthmd.app` domain and accurate product/support/developer contacts.
- [ ] The privacy policy includes the required Google API Services User Data Policy and Limited Use disclosure, and shipped behavior conforms to it.
- [ ] Authorized domains and branding match the shipped app and store listings.
- [ ] The only Drive scope requested is `https://www.googleapis.com/auth/drive.file`; no broad Drive scope appears in console configuration, code, screenshots, or review submissions.
- [ ] Separate public native OAuth clients exist for iOS and Android; no native client secret is generated for or shipped in an app.
- [ ] The iOS client has the exact production bundle ID and registered custom redirect URI. Authorization-code flow uses state, PKCE S256, `access_type=offline`, and deliberate `prompt=consent`; refresh tokens stay only in Keychain.
- [ ] The Android client has the exact package name and every production signing-certificate SHA fingerprint, including Play App Signing. Internal/test signing identities stay in the test project.
- [ ] Android Play services `AuthorizationClient` requests only `drive.file`, opts out of previously granted extra scopes, binds the selected account in encrypted private storage, and verifies authority independently with Drive `about.get`.
- [ ] Picker configuration allows folder selection, filters for folders, and is tested for My Drive and Shared Drives.
- [ ] OAuth app publication/verification is approved for production. Reviewer demo instructions show connect, Picker folder selection, manual upload, disconnect, token revocation, and Android foreground reauthorization.
- [ ] Quota alerts and Google API status/incident runbooks exist without logging account names, Drive IDs, paths, tokens, session URIs, or export content.

### Static verified-domain pages

The following production URLs must be publicly reachable without login, return successful HTTPS responses, use the verified `healthmd.app` domain, and agree with the consent screen and store copy:

- [ ] `https://healthmd.app/` — product identity and support route.
- [ ] `https://healthmd.app/privacy-policy.html` — Google receives user-directed sensitive exports; no Health.md health-data or token server; Google API Services User Data Policy/Limited Use; retention and disconnect behavior.
- [ ] `https://healthmd.app/terms-of-service.html` — governing terms.
- [ ] `https://healthmd.app/docs/guides/google-drive-export/` — feature, scope, write, scheduling, conflict, and troubleshooting disclosure.

Capture the deployed response, canonical URL, visible copy, and link-check result in the verification packet. Do not submit localhost, preview-deployment, redirect-shortener, or unpublished URLs.

## 2. Store privacy and reviewer disclosures

A privacy/legal owner must answer the current store questionnaires from the shipped data flow and retain dated screenshots. Do not select “not collected” or “not shared” merely because Health.md has no server; the app sends health exports and file metadata to Google at the user's direction.

### Apple App Store

- [ ] Re-review App Privacy answers for Health & Fitness, identifiers/account information involved in Google authorization, diagnostics, and any destination analytics under Apple's then-current definitions of collection, service providers, and user-initiated transfer.
- [ ] Confirm purposes and linkage/tracking answers; Health.md does not use Drive export data for advertising or tracking.
- [ ] Privacy policy URL and support URL resolve to the deployed verified-domain pages.
- [ ] App Review notes explain `drive.file`, Picker consent, direct app-to-Google flow, token storage, sensitive files in Google, best-effort schedules, non-atomic multi-file writes, and disconnect not deleting remote files.
- [ ] Provide a review account or approved review path that does not expose a real user's health data. Use synthetic exports for the demonstration.

### Google Play

- [ ] Re-review Data safety for Health info, Files and docs, account identifiers used for authorization, app activity/diagnostics, encryption in transit, deletion, and user-initiated sharing under Google's then-current definitions.
- [ ] Reconcile Data safety, the Health apps declaration, OAuth consent screen, in-app disclosure, privacy policy, and store description word for word where they describe recipients and purposes.
- [ ] Explain that Android uses Play services `AuthorizationClient`, binds one exact account, and may require foreground reauthorization for scheduled work because Health.md runs no confidential token server.
- [ ] Play review instructions cover Picker, My Drive/Shared Drive, revocation, `reauthorization_required`, and synthetic manual/scheduled export evidence.

Legal/store owners decide the final questionnaire classifications; engineering evidence cannot replace that review. Any changed answer is submitted and approved before rollout.

## 3. Documentation and privacy consistency

- [ ] Customer UI and docs distinguish direct Google Drive from Apple Files/Android SAF Google Drive providers and never promise migration or fallback.
- [ ] Consent states that Google receives sensitive health exports and Google/Workspace retention, sharing, and administrator controls apply.
- [ ] Docs state that Health.md operates neither a health-data upload server nor a Google token server.
- [ ] Account and folder binding, `drive.file`, Picker consent, My Drive/Shared Drive, disconnect, remote retention, and schedule limitations match the app.
- [ ] Every write mode and artifact is covered. Append/merge is described as a complete-file remote replacement, not an atomic append.
- [ ] Non-atomic multi-file and concurrent-edit limitations, partial completion, conflict recovery, and cross-device races are visible before users rely on scheduling.
- [ ] Shared Setup and CLI/direct/MCP exclusions are explicit.
- [ ] English and all published localized privacy policies contain equivalent Google Drive disclosures and a qualified human has reviewed legal/health terminology.
- [ ] The policy effective date, customer guide availability banner, screenshots, release notes, support macros, and in-app copy match the actual rollout state.

## 4. Integration and failure evidence

Platform owners attach passing evidence for both Apple and Android before the inventory can change from `planned`:

- [ ] Official mobile Picker and only `drive.file` are observed in a production-shaped authorization capture.
- [ ] Exact account and immutable folder binding reject account mismatch and never fall back to Files, SAF, an API endpoint, or another account.
- [ ] Manual and best-effort schedule paths use the same runner; Android resolution resumes the same journal only after foreground authorization.
- [ ] My Drive and Shared Drive capability checks pass, including role/capability loss and resource-key behavior.
- [ ] Loose files, archives, daily files, rollups, dictionaries, sidecars, individual entries, raw snapshots, overwrite, append, Markdown Update, Daily Note injection, and non-Markdown Update match renderer bytes.
- [ ] Crash injection and retries do not duplicate app-owned objects or reapply append/merge fragments.
- [ ] Multi-file partial completion is visible and retry resumes the exact remaining staged frontier.
- [ ] Move, rename, trash, duplicate names, concurrent edit, cross-device write, ambiguous commit, checksum mismatch, expired session, offline, quota, cancellation, 401/403/404/429/5xx, and folder capability loss fail safely.
- [ ] Disconnect removes local authority and future schedule access without deleting remote files.
- [ ] Logs, analytics, profile JSON, Shared Setup, direct protocols, CLI, and MCP contain no token, session URI, account name, Drive ID, path, or health bytes outside their documented local output boundary.
- [ ] Physical iPhone and Pixel tests use production-shaped OAuth clients and synthetic health data.

## 5. Contract and release gates

- [ ] `packages/contracts/validate.py` passes and the product-capability manifest hash matches.
- [ ] `destination.google-drive` remains `planned` until both platform owners attach passing integration receipts and release review approves promotion.
- [ ] Apple v8 and Android v4/v5 schema signatures and byte fixtures are unchanged. A destination implementation alone does not bump `healthmd.health_data`.
- [ ] Apple, Android, shared core, CLI/MCP, website, localization, privacy, link, and external-consumer checks pass at the revisions being released.
- [ ] Google OAuth verification, Apple App Review, Play review/Data safety, privacy/legal review, support readiness, and production quota monitoring are approved.
- [ ] Staged rollout has a stop condition for authorization, conflict, checksum, partial-completion, or quota regressions. Rollback disables new operations without deleting user files or corrupting retained journals.
- [ ] Release notes describe availability truthfully and do not call schedules guaranteed or Drive writes atomic.

## Troubleshooting and support matrix

| User-visible result | Support action |
|---|---|
| Destination says configuration is missing | Confirm the production build's public client configuration. Do not suggest Files/SAF fallback as if it were the same binding. |
| Authorization opens the wrong account | Disconnect, select the intended account, and bind a folder again. Never edit account labels or reuse another account's folder binding. |
| Android says reauthorization is required | Foreground Health.md, complete Google authorization for the bound account, then resume the existing operation. Do not start a second export until history is known. |
| Folder unavailable or permission denied | Check exact folder access and Shared Drive capabilities. Rebind explicitly only after showing the new destination. |
| Remote conflict | Inspect the exact destination and choose the offered foreground recovery. Scheduled work must not force replace. |
| Partial completion | Review committed files in history and retry the same operation to resume its remaining frontier; do not assume the bundle rolled back. |
| Ambiguous commit or checksum mismatch | Do not manually rerun append/merge. Preserve local history and use reconciliation/retry after the remote object is inspected. |
| Quota/rate limit/offline | Wait for connectivity or the indicated retry interval; preserve the journal and staged bytes. |
| Shared Drive upload fails | Ask an administrator to verify `canAddChildren`, retention, and role restrictions. Ownership is not the capability check. |
| User disconnected but files remain | Expected. Disconnect removes local credentials and authority only; delete remote files in Google Drive if desired and permitted. |

Support requests must not ask users to email health exports, OAuth tokens, authorization codes, upload-session URIs, account names, folder/file IDs, or full Drive error bodies.

## Promotion record

The release issue must include:

1. exact Apple, Android, contracts, and website commit SHAs;
2. Cloud project and native client identifiers (not secrets);
3. OAuth verification approval and deployed-page captures;
4. store questionnaire/reviewer approval receipts;
5. automated validation output and physical-device matrix;
6. privacy/legal/localization sign-off;
7. capability-inventory promotion review and updated manifest hash;
8. rollout owner, monitoring window, stop thresholds, and rollback decision.

Until that record is complete, customer documentation must label the feature planned/preview and `destination.google-drive` must remain `planned`.
