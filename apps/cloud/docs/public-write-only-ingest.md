# Single-owner public API Endpoint pilot (`api.healthmd.app`)

**Scope:** `https://api.healthmd.app/api/v1/exports` accepts only `healthmd.api_export` compatibility JSON v1/v2 from a deliberately configured Apple or Android API Endpoint target with a separately issued `hmd_ing_…` write-only bearer token. There is no public signup or automatic upload; Android Raw API Snapshot NDJSON is **not** ingested. This is the same unbacked, unlimited-retention single-owner VM pilot, not a durable, generally available, independently approved or compliant health-data service. VM/disk/key loss can permanently destroy uploaded exports. Cloudflare terminates HTTPS and processes the requests; do not claim end-to-end TLS to the VM. A single upload is capped at 25 MiB and account storage has a 1 GiB pilot quota; indivisible large days can return 413.

**Boundaries:** Preserve the existing `*.ts.net:18788` tailnet HTTPS writer and upload-disabled `:18787` synthetic preview, the unrelated `:443` route, `account.healthmd.app` account administration, `mcp.healthmd.app` read-only MCP and the static Vercel website. The new VM listener on `127.0.0.1:18793` uses the existing writer data/key authority but has a positive method/path allowlist: only `POST /api/v1/exports` and `GET /health`. Account, downloads, read tokens, dashboard, MCP, signup and every other route return 404 even with valid tokens or cookies. An independent loopback nginx proxy on `127.0.0.1:18794` has no access/request/error logs, no disk request buffering, a 25 MiB body cap and an exact hostname. A **new**, independently credentialed Tunnel matches `api.healthmd.app` and only the two positive paths; all other ingress returns 404. Do not publish DNS or point this hostname at Vercel, account, MCP, or the tailnet writer.

The server validates exact HTTPS origin and trusted loopback proxy headers; ingestion still requires an active account-bound write token, checks revocation/rate limits and envelope schema, encrypts accepted bytes before storage, and returns no-store responses. A dashboard cookie or `hmd_read_…` MCP token cannot upload. There is no CORS allowance, token URL parameter, GET export or automatic redirect. The private writer owns object reconciliation and account deletion maintenance; the public ingest process does not run them. Uploaded evidence alone is available to cloud MCP readers according to their separately issued read scopes; this endpoint cannot query an iPhone.

## Release procedure

1. Review this deployment, the user's consent and current `apps/cloud/AGENTS.md`; inspect migration state and SQLite integrity. No schema migration is expected for this routing change. Build from committed source, use only the existing root-only writer environment file and set `HEALTHMD_VM_READER_GID` to the installed read group. Do not copy any secrets into source, CI, examples or chat. Verify `npm run check`, `npm run dry-run`, `npm run build:vm`, synthetic smoke and audit.
2. Install `ingest-server.mjs` alongside the writer's existing source after comparing bundle hashes. Install `healthmd-cloud-ingest.service` from the example on loopback `18793` and `healthmd-ingest-proxy.service` with `proxy.conf` on `18794`. Start them **without DNS or autostart**. Verify `nginx -t`, local `POST /api/v1/exports` without a token = 401, `GET /api/account` and `POST /api/auth/password-login` = 404, wrong host = 421, and non-JSON/oversize = 415/413. Use only synthetic fixture data for an authorized end-to-end test; never print its token or payload.
3. Obtain fresh, private Cloudflare Tunnel-creation/DNS authorization from the owner. The existing MCP and account Tunnel credentials are not administration credentials and must not be reused as the new Tunnel's credential. Create a third dedicated Tunnel, route an **explicit** proxied DNS record for `api.healthmd.app` without overwriting any existing record, and run it as a dedicated `healthmd-api-tunnel` user from a root-owned, group-readable per-Tunnel credential and config. Example ingress (substitute the ID **only in root-only live config**, not source):

   ```yaml
   tunnel: REPLACE_WITH_NEW_TUNNEL_ID
   credentials-file: /etc/healthmd-cloud-ingest-tunnel/credentials.json
   ingress:
     - hostname: api.healthmd.app
       path: ^/api/v1/exports$
       service: http://127.0.0.1:18794
       originRequest:
         httpHostHeader: api.healthmd.app
     - hostname: api.healthmd.app
       path: ^/health$
       service: http://127.0.0.1:18794
       originRequest:
         httpHostHeader: api.healthmd.app
     - service: http_status:404
   ```

4. Verify public HTTPS with no credentials first: `GET /health` = 200, `POST /api/v1/exports` without a token = 401, all account/MCP routes = 404, no cookie or wildcard CORS, no-store responses, and wrong-host routing denied. Verify a temporary **first-party synthetic QA ingest token** can upload an obviously synthetic compatibility envelope, read it only through the owner-authorized account or reader, revoke the QA token and verify it returns 401. Do not send real health data during QA; do not print raw tokens, URLs containing tokens, IDs, or exported payloads. Check the tailnet writer, account dashboard, existing read-only MCP scopes and unrelated website still work.
5. Enable the three new services for reboot. Only **after** successful public checks, set `API_PUBLIC_ORIGIN=https://api.healthmd.app` on the installed account service, restart it and confirm `account.healthmd.app/api/runtime` advertises `https://api.healthmd.app/api/v1/exports`. The tailnet writer remains available for existing saved destinations; phones do **not** migrate URLs or tokens automatically. Users must deliberately edit the saved API Endpoint target and retry pending dates explicitly. Preserve write-only token scope and `hmd_read_…` separation.

If the public receiver misbehaves, stop/disable only the new Tunnel first to cut public ingest; leave the tailnet writer, account and MCP untouched. Revert the account service's advertised export origin to the tailnet target until the new endpoint is verified. Never delete encrypted objects or historical keys during an ingress rollback. Remove any temporary broad Cloudflare origin certificate and one-time login URL log after provisioning; retain only the dedicated per-Tunnel credential.
