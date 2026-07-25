# Health.md OAuth Broker

Minimal Cloudflare Worker for third-party provider OAuth. WHOOP is the first staged production rollout; other provider definitions remain dormant until their app flags and QA are complete.

The broker only:

1. builds provider authorization URLs from server-side provider client IDs;
2. exchanges authorization codes using provider client secrets;
3. refreshes tokens.

It does **not** store provider tokens, health data, vault paths, or export files. Responses use `Cache-Control: no-store`. Health.md stores WHOOP tokens in iOS Keychain and calls WHOOP's data API directly.

## Endpoints

- `GET /health`
- `GET /v1/providers`
- `POST /v1/oauth/authorize-url`
- `POST /v1/oauth/token`
- `POST /v1/oauth/refresh`

All `/v1/*` endpoints require the exact `BROKER_CLIENT_TOKEN` bearer token. The Worker returns `503 broker_auth_not_configured` when that secret is absent, so deployment mistakes fail closed. This remains a weak mobile-app gate, not a durable secret; shipped app resources can be inspected.

## WHOOP contract

Register this exact redirect in the WHOOP Developer Dashboard:

```text
healthmd://oauth/callback
```

The Worker allowlist in `wrangler.toml` must match exactly. WHOOP authorization requests are limited to:

```text
offline read:recovery read:cycles read:sleep read:workout read:body_measurement
```

WHOOP state must be exactly eight characters. Refresh requests include `scope=offline`, and the broker rejects a success response that omits WHOOP's mandatory rotated refresh token.

## Secrets and deployment

Do not place provider credentials in `wrangler.toml` or app source.

```bash
cd worker/oauth-broker
wrangler secret put WHOOP_CLIENT_ID
wrangler secret put WHOOP_CLIENT_SECRET
wrangler secret put BROKER_CLIENT_TOKEN
npm ci
npm run typecheck
npm test
npm run deploy
```

Verify after deployment:

```bash
curl --fail --silent --show-error https://<worker-host>/health
curl --fail --silent --show-error \
  -H "Authorization: Bearer <BROKER_CLIENT_TOKEN>" \
  https://<worker-host>/v1/providers
```

Then configure the iOS build machine:

```bash
bash scripts/set-oauth-broker-config.sh \
  "https://<worker-host>" \
  "<BROKER_CLIENT_TOKEN>"
```

The script stores the values in macOS Keychain. `scripts/inject-oauth-broker-config.sh` writes them into the built app only when `CONNECTED_APPS_WHOOP_ENABLED=YES`; no token is committed to Git.

## Local development

```bash
npm ci
npm run typecheck
npm test
npm run dev
```

The tests cover WHOOP authorization URL construction, eight-character state validation, exact redirect rejection, scope allowlisting, code exchange, `scope=offline` refresh, rotated refresh-token enforcement, provider error normalization, response cache controls, and broker client authentication.
