# Health.md Cloud Agent Instructions

## Health-data boundary

Everything in this component is inside the sensitive health-data boundary. Keep it isolated from `apps/website`, `apps/practice`, `apps/wake`, and Apple-side analytics/OAuth Workers. Do not import their code, share bindings, proxy requests through them, or reuse their databases, buckets, secrets, sessions, or deployment configuration.

- Never commit real health payloads, names, email addresses, access tokens, magic links, session cookies, production IDs, screenshots, database dumps, bucket objects, or Wrangler state.
- Test fixtures must be obviously synthetic and use reserved domains.
- Never log request bodies, authorization headers, cookies, email addresses, health dates, metric values, object keys, or raw identifiers.
- The Worker profile keeps health exports only in private R2 as application-encrypted ciphertext; D1 holds minimum metadata. The separate EXE.dev VM profile uses private SQLite and application-encrypted filesystem objects. The owner expressly accepts permanent data-loss risk and does not want an off-host backup for the **disposable single-user pilot**, including its separately authenticated public read-only MCP connector. Backup/restore and independent external security-review sign-off are **not pilot release gates**; do not claim durability, recovery, production security approval, or regulated compliance. Keep private storage, real authentication, read-only reader identity, token revocation, erasure/reconciliation, bounded responses, health-free logs, and dedicated HTTPS ingress. Never turn the write-only export token into a read credential.
- Worker secrets are Wrangler secrets. The VM profile must use separate owner-only service credentials and directories, never the Wrangler preview keys/state. Keep all production, preview, and local resources separate.
- All authenticated and ingestion responses are `Cache-Control: no-store`. No third-party scripts, fonts, analytics, session replay, wildcard CORS, or public object URLs.

## Product boundary

The first release receives the existing `healthmd.api_export` v1/v2 compatibility envelope from Apple and Android API Endpoint targets. It does not change any mobile export schema. A repeated `records[].date` is a replacement snapshot; the newest `exported_at` wins.

A separate VM-only read-only MCP reader and offline read-token CLI are deployed at `https://mcp.healthmd.app/mcp` for the disposable pilot. The reader has a dedicated UID, read-only data mount, distinct per-request read-token auth/revocation, bounded responses, health-free audit records and a separate TLS Tunnel; a dedicated aggregate-only Muse token was later issued with the owner's consent, but Muse's actual connection remains unverified. The owner subsequently consented to Muse default handling of every **retained** export data point, including sensitive raw JSON and embedded binary, using bounded full-export MCP tools. Existing tokens remain aggregate-only; a separate 30-day full-export Muse token was explicitly issued and verified against the public tool catalog, but Muse's vault capture/client connection is still unverified. Revoke the original aggregate token only after client rotation succeeds. Grokbot still requires its own product/retention qualification and consent. Preserve those boundaries and verify denial of unauthenticated or write-token requests after every change. Do not claim Muse/Grokbot/other client compatibility without checking the actual client's bearer-header support and health-data retention; obtain owner consent before issuing any third-party read token. OAuth/PKCE remains necessary for hosted clients that require it; do not put tokens in URLs. The owner chose to forego backups and an independent external-review sign-off for this disposable pilot; accurately document those risks. Ingestion tokens are write-only and must never become MCP credentials.

## Release and operations

The checked-in Wrangler configuration contains placeholder resource IDs and closed signup. Never deploy it unchanged. The disposable public VM MCP pilot is not a production Cloudflare Worker launch: do not invent a restore drill, production certification, or compliance approval. Keep the source changes reviewable and verified, preserve unrelated user edits, inspect migration state before a controlled writer restart, and require explicit owner authorization for health-data disclosure to each agent. No backup/restore proof or independent external security sign-off is required for this pilot; production claims require a separate decision.

D1 migrations are forward-only under `migrations/`. Never rewrite an applied migration. Encryption key IDs are durable; do not remove an old key until every object using it has been re-encrypted or deleted and verified.

Run from `apps/cloud`:

```bash
npm ci
npm run check
npm run dry-run
```

Before finishing a change, also run `npm audit --audit-level=moderate` and `git diff --check`. Use Node 24 and Wrangler 4.x.
