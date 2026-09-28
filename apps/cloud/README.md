# Health.md Cloud (unbacked one-user pilot; not a general production cloud)

An isolated, opt-in export receiver and account dashboard for Health.md's existing **API Endpoint** destination. The original synthetic, upload-disabled tailnet preview is unchanged. A separate unbacked, tailnet-only single-user VM service and owner account are installed; production deployment remains unapproved. It is not Practice, the website, or the wake Worker. A separate read-only retained-export MCP process is live at `https://mcp.healthmd.app/mcp`; a Muse aggregate-only token was issued after explicit owner consent, but the client's actual connection is unverified. An independent `full_export` scope adds bounded navigation of every currently retained JSON export, including source archives/sidecars and older revisions, **only for newly issued full-scope tokens**; a separate full-scope Muse token was issued after explicit broader consent, but vault capture is unverified. It is not a route in the receiver or dashboard. See [remote-read-only-mcp.md](docs/remote-read-only-mcp.md), [mcp-full-export-tools.md](docs/mcp-full-export-tools.md), [public-account-dashboard.md](docs/public-account-dashboard.md), and the [typed query convergence plan](docs/retained-query-parity-plan.md). Read [`AGENTS.md`](AGENTS.md) and [ADR-0007](../../docs/architecture/adr-0007-healthmd-cloud.md) before changing it.

## What works in the synthetic local environment

- Invite-only email-link accounts, cookie sessions, export-token creation and revocation.
- `POST /api/v1/exports` accepts the current iOS `healthmd.api_export` v1/v2 and Android compatibility v1 envelope with an `Authorization: Bearer hmd_ing_…` header. iOS v8 and Android v4 daily documents are retained **as bytes**, without changing either schema. The endpoint does **not** accept Android Raw API Snapshots.
- The dashboard at `/dashboard` displays account/token inventory, paginated retained export/day metadata, and authenticated JSON downloads. In the single-owner VM pilot it also issues password-confirmed, expiring, revocable, full-export MCP credentials after explicit provider consent; the token is shown once. It does not display health readings or perform analysis. A separately authenticated agent may receive retained export data only when the owner shares its read credential.
- R2 objects contain application-encrypted envelopes. D1 stores account/session/receipt metadata and health owner dates. A re-export upserts the newest day pointer while earlier accepted envelopes remain downloadable.

**Disposable owner-operated pilot, not a production service:** The VM has encrypted-object reconciliation and serialized ingest for one account. The owner expressly accepts possible permanent loss and does not require backups, key/password recovery or independent external-review sign-off for the single-user pilot, including a separately authenticated public read-only MCP connector. Do not claim recovery, durability, external security certification or compliance. Keep the public reader separately authenticated and least-privilege, and obtain owner consent before granting a third-party agent access. Do not deploy the checked-in `wrangler.toml`: it has placeholder resource IDs and no configured secrets.

## Local setup (synthetic data only)

Use Node 24 and a separate Cloudflare configuration only for this component:

```bash
cd apps/cloud
npm ci
npm run check
npm run test:smoke
npm run dry-run
npm audit --audit-level=moderate
```

The smoke test creates disposable secrets and private local D1/R2 state, runs the migrations and a local Worker, signs in two synthetic accounts, posts the committed synthetic Apple API v1/v2 fixtures and a synthetic Android v4 envelope, checks replacement ordering and exact encrypted roundtrip, tenant isolation and token revocation, then removes that test state. It refuses to overwrite an existing `.dev.vars` file. No Cloudflare account or production secrets are needed.

For interactive synthetic exploration:

```bash
cp .dev.vars.example .dev.vars
# Replace placeholder base64 values with two independent 32-byte secrets and
# set an invite-only synthetic address. Never commit .dev.vars.
npm run migrate:local
npm run dev
# Open http://localhost:8787/login in a browser.
```

Set `DEV_SHOW_MAGIC_LINK=1` only in the local development environment to display a synthetic link; production refuses this setting. Local dev runs with development origin and invite mode; a real email service is not needed for synthetic testing. In production use a verified HTTPS custom domain and a configured transactional sender. The Worker preview never prompts for a password. The separate VM-native profile uses an offline-provisioned single-user password login and never asks the mobile app to share its HealthKit/Health Connect permissions with the cloud.

### Tailnet-only synthetic preview

This VM runs a private Wrangler development preview on `127.0.0.1:18787` through an **independent** Tailscale Serve HTTPS port: `https://<your-vm>.<your-tailnet>.ts.net:18787/login` (requires membership in the same tailnet). The existing Tailscale port 443 route serves another app and was not changed. The unit is `healthmd-cloud-tailnet-preview.service`. It uses isolated local D1/R2 **emulator** state under `.wrangler/local-staging/state` and ignored `0600`-permission `.dev.vars` keys; neither is a production binding or backup. Only the reserved synthetic invite `pilot@example.test` is enabled. The preview displays a development sign-in link and **rejects every export upload and export-token creation request** with HTTP 403. Never configure a real device or send real health data here. The transient unit is not guaranteed to return after a VM reboot. The separate one-user pilot is tracked in [`docs/personal-tailnet-pilot.md`](docs/personal-tailnet-pilot.md); public MCP uses its own reader identity and ingress.

```bash
systemctl --user status healthmd-cloud-tailnet-preview.service
tailscale serve status
curl -fsS 'https://<your-vm>.<your-tailnet>.ts.net:18787/health'
# Stop only this preview; do not reset the other app's Tailscale Serve route.
sudo tailscale serve --https=18787 off
systemctl --user stop healthmd-cloud-tailnet-preview.service
```

Do not remove `.dev.vars` or `.wrangler/local-staging/state` while the service runs; removing the key makes retained synthetic ciphertext unreadable. `npm run test:smoke` intentionally refuses to overwrite an existing `.dev.vars`, so stop the preview and move its ignored secrets/state aside only if you intentionally reset the local demo. No logs, tokens, or magic-link URLs should be copied into support tickets.

### VM-native personal-MVP profile (separate tailnet service)

`npm run check` exercises owner-only SQLite, private encrypted objects, offline single-account creation, password sign-in, loopback proxy boundary, authenticated downloads, synthetic Apple ingest, orphan reconciliation, serial upload gating, revision history and deletion. `npm run build:vm` bundles the loopback-only Node 24 adapter. The VM service is installed on `127.0.0.1:18788` and exposed only through its **separate tailnet HTTPS port 18788**; the `owner` account has received real iPhone exports. The synthetic preview on 18787 remains upload-disabled, and the unrelated 443 route remains unchanged.

The owner selected **unlimited revision retention**: `REVISION_RETENTION_DAYS=unlimited` skips age-based revision expiry, while account deletion requests erasure of all exports. This is unlimited time, **not unlimited disk space or recoverability**; the 1 GiB account quota and 25 MiB per-request limit remain. No off-host backup has been configured by this project (provider snapshots, if any, have not been verified). Losing the VM, SQLite database, filesystem or encryption keys can permanently lose everything. The owner explicitly chose an **unbacked one-user disposable pilot**: the writer remains tailnet-only and the separately authenticated public MCP reader has its own operating-system identity. `VM_PERSONAL_MVP_NO_BACKUP_ACK=I_ACCEPT_PERMANENT_DATA_LOSS` records the writer's risk acceptance; no HTTP signup, password reset, off-host backup or key recovery exists. A future general-purpose production cloud offering needs a new product decision. Never copy credentials from the synthetic preview, set a fake restore attestation, or present this pilot as recoverable or independently audited.

### Personal-MVP operations (unbacked; owner accepted permanent-loss risk)

A dedicated `healthmd-cloud` system user owns the private (`0700`) writer code snapshot under `/var/lib/healthmd-cloud-mvp`. The data tree is group-readable only by `healthmd-cloud-read`, whose sole reader identity is `healthmd-mcp`; the MCP service has a read-only mount and cannot access writer secrets or write stored exports. The distinct credentials file `/etc/healthmd-cloud-mvp/secrets.env` is root-owned, mode `0640`, readable only by the service group. The Node 24 service binds `127.0.0.1:18788`; Tailscale Serve routes **only HTTPS port 18788** to it. It rejects missing/incorrect proxy headers and cross-site browser mutations. Up to four overlapping uploads wait in a bounded serial queue (preserving the single-user quota); only queue overflow returns HTTP 503 with `Retry-After: 2`. Startup runs deletion cleanup and reconciles orphan encrypted files; missing ciphertext fails startup closed. Systemd holds a single `flock` lock. Do not change the 443 or synthetic 18787 routes.

The credentials file is never checked in or printed. It contains **three independent 32-byte random secrets** (`IDENTITY_KEY_B64`, `PASSWORD_PEPPER_B64`, and the `v1` entry of `EXPORT_ENCRYPTION_KEYS_JSON`) plus `HEALTHMD_VM_DATA_DIR`, `HEALTHMD_CLOUD_SOURCE_DIR`, `PUBLIC_ORIGIN=https://<vm>.<tailnet>.ts.net:18788`, `VM_PORT=18788`, `REVISION_RETENTION_DAYS=unlimited`, `CURRENT_EXPORT_KEY_ID=v1`, and `VM_PERSONAL_MVP_NO_BACKUP_ACK=I_ACCEPT_PERMANENT_DATA_LOSS`. Never reuse preview keys or put a password in the service environment file. The single `owner` account was created offline with a cryptographically random password piped to the bootstrap process; it was not passed as a command argument or printed in logs. Its account label is `owner@example.test` (no email delivery or password reset). The generated login is in a **separate one-time root-only (0600) delivery file**, not in the application or repository:

```bash
sudo cat /etc/healthmd-cloud-mvp/owner-login.txt
# After you save the password in a password manager, remove the delivery copy:
sudo rm /etc/healthmd-cloud-mvp/owner-login.txt
```

Never send the password in chat. A lost password or encryption key cannot currently be recovered. Keep `/etc/healthmd-cloud-mvp/secrets.env` when restarting or updating code; **deleting or regenerating keys makes retained exports unreadable**. Verify `/api/runtime` reports `unbackedPersonalMvp: true`, sign in at `https://isotech.tail5cf333.ts.net:18788/login`, create a write-only export token, and test only a single Summary day on the iPhone before scheduling more. The API Endpoint is `https://<vm>.<tailnet>.ts.net:18788/api/v1/exports`. A successful upload is durable on this VM's disk only, not backed up elsewhere. Account deletion disables access immediately, then a background job deletes ciphertext and metadata; verify the deletion job completes rather than treating HTTP 202 as finished erasure. This disposable experiment is not a general public Health.md cloud signup or audited service; public privacy claims must accurately distinguish the private export writer from the separately authenticated MCP pilot. Stop **only** this service and route with `sudo tailscale serve --https=18788 off` and `sudo systemctl stop healthmd-cloud-personal-mvp.service`; do not use `tailscale serve reset`. Never delete `/var/lib/healthmd-cloud-mvp/data` or `/etc/healthmd-cloud-mvp/secrets.env` while retaining exports.

### Existing iPhone API target (production after full review only)

1. Sign in to the approved, provisioned cloud domain and create an export token named for the device. Copy it once.
2. In iOS Health.md, choose **Export → Export Target → API Endpoint**. Set the URL displayed by the dashboard (`https://<approved-domain>/api/v1/exports`) and paste the token in the access-token field **without** `Bearer` (iOS adds it). Never put credentials in the URL.
3. Select only required metrics and **Summary** detail at first; send a single test day. The iPhone sends directly to the Worker over HTTPS. Check the dashboard inventory before scheduling exports or selecting Lossless Health Records.
4. Re-exporting a day is safe: new envelopes are archived, and the most recent `exported_at` becomes the current snapshot. A response other than 2xx is not a durable receipt. HTTP 413 means a single day or batch exceeds the prototype 25 MiB cap; changing the date range cannot shrink an indivisible day.

Android's existing **Compatibility Export** API target can use the same URL/token in Bearer mode when tested. Android's separate raw streaming upload is **not** supported. No changes to either mobile app are required for the API Endpoint prototype.

### Production provisioning checklist (blocked)

Do **not** follow this until all ADR-0007 gates are complete and the owner explicitly approves a production rollout:

- Create separate, private D1 and R2 resources for preview and production; update the component's Wrangler config with real IDs, disable public R2 access, and bind a verified HTTPS custom domain. Do not reuse any other Worker's identity or storage.
- Provision `IDENTITY_KEY_B64` (32 random bytes), `EXPORT_ENCRYPTION_KEYS_JSON` (mapping key IDs to independent 32-byte random keys), `RESEND_API_KEY`, and `AUTH_INVITE_EMAILS` as Wrangler secrets. Only after the independent production gates and explicit approval, set `CLOUD_RUNTIME_APPROVED` to `healthmd-cloud-v1-reviewed` as a fail-closed deployment marker (not a security credential). Keep historical export keys until all objects using them are migrated or verifiably deleted. Configure a verified email sender. Never put secret values in `wrangler.toml`, CLI flags, CI logs, or Git.
- Inspect remote migration state before applying migrations in order. Test with synthetic encrypted accounts without treating the unbacked pilot as recoverable. Review runtime logs and edge metrics for body/credential leakage. Do not deploy the placeholder Worker configuration; keep the pilot's source and migration changes reviewable and separately scoped.
- Review provider terms, data protection and retention/erasure obligations, privacy policy and App Store disclosures before user access. No automatic deploy job is checked in.

## API surface

| Route | Authority | Purpose |
| --- | --- | --- |
| `POST /api/auth/request-link`, `POST /api/auth/consume-link` | Invite + single-use link | Worker-preview browser sign-in; no account enumeration responses |
| `POST /api/auth/password-login` | VM single-user password profile only | Rate-limited browser sign-in; no HTTP registration or recovery |
| `POST /api/account/delete` | VM password session + password reauthentication | Disable account and queue encrypted object/account erasure; inspect completion before treating deletion as complete |
| `POST /api/auth/logout`, `GET /api/account` | HttpOnly browser session | Session and owner profile |
| `POST/GET /api/ingest-tokens`, `DELETE /api/ingest-tokens/:id` | Browser session | Write-only token management |
| `POST /api/v1/exports` | Write-only Bearer token | Bounded original-envelope ingest; durable receipt after encrypted storage + D1 commit |
| `GET /api/exports`, `GET /api/exports/:id/download` | Browser session | Owner-scoped inventory and original-envelope download |

All routes are same-origin or token-authenticated, return no-store responses, and do not expose R2 object URLs. The Worker and personal VM receiver expose no MCP route or OAuth authorization server. A **separate** read-only MCP service is publicly routed at `https://mcp.healthmd.app/mcp` and requires its own `hmd_read_` bearer token. The owner dashboard can create/revoke new full-export credentials after password re-entry; the isolated single-owner account dashboard is now live at `https://account.healthmd.app/dashboard` behind its own dedicated Tunnel and separate proxy (password sign-in; no public signup). The `healthmd.app/dashboard` entry redirect is staged on a website branch and is not yet live. Previously issued aggregate-only credentials remain aggregate-only; newly issued, explicitly authorized `full_export` credentials can read paginated original retained JSON envelopes, including sensitive raw data. Separate aggregate-only and full-export Muse credentials exist after explicit owner consent; Muse's actual client connection is not verified, and no Grokbot token has been issued. Do not give an ingest token or dashboard session to an agent; issue read credentials offline only after reviewing that specific provider's retention and obtaining owner consent. See [remote-read-only-mcp.md](docs/remote-read-only-mcp.md).

A separate, write-only `api.healthmd.app` ingest listener and proxy are currently installed on VM loopback ports 18793/18794 with autostart disabled. **The public upload URL is not live:** the dedicated Tunnel and DNS have not been provisioned; public requests still hit an unrelated wildcard route and return 404. The private tailnet `:18788` writer remains operational. Account runtime continues to advertise that tailnet URL until the independent public ingest boundary passes its gates. The public listener allows only `POST /api/v1/exports` and `GET /health`; this does not change Apple/Android export schemas, saved mobile destinations or write-token privileges. See [public-write-only-ingest.md](docs/public-write-only-ingest.md).
