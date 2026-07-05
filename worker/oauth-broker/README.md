# Health.md OAuth Broker

Minimal Cloudflare Worker for third-party health provider OAuth flows.

The broker only:

1. builds provider authorization URLs from server-side provider client IDs;
2. exchanges authorization codes for tokens with provider client secrets;
3. refreshes provider tokens.

It does **not** store provider tokens, health data, vault paths, or export files. Health.md stores tokens in iOS Keychain and calls provider APIs directly from the device.

## Endpoints

- `GET /health`
- `GET /v1/providers`
- `POST /v1/oauth/authorize-url`
- `POST /v1/oauth/token`
- `POST /v1/oauth/refresh`

## Required provider app redirect URI

Register this redirect URI in each provider dashboard:

```text
healthmd://oauth/callback
```

## Secrets

```bash
wrangler secret put FITBIT_CLIENT_ID
wrangler secret put FITBIT_CLIENT_SECRET
wrangler secret put OURA_CLIENT_ID
wrangler secret put OURA_CLIENT_SECRET
wrangler secret put WHOOP_CLIENT_ID
wrangler secret put WHOOP_CLIENT_SECRET
wrangler secret put WITHINGS_CLIENT_ID
wrangler secret put WITHINGS_CLIENT_SECRET
wrangler secret put STRAVA_CLIENT_ID
wrangler secret put STRAVA_CLIENT_SECRET
```

Optional weak mobile gate:

```bash
wrangler secret put BROKER_CLIENT_TOKEN
```

Then set the app build settings / Info.plist substitutions:

- `OAUTH_BROKER_ENDPOINT_URL`
- `OAUTH_BROKER_CLIENT_TOKEN` if using the optional broker token

## Local development

```bash
npm install
npm run typecheck
npm run dev
```
