# Receipt verifier and scheduled APNs delivery

This folder restores the deployed `healthmd-receipt-verifier` source recovered
through Wrangler on 2026-10-07. The deployed receipt-verification logic and
daily/weekly timezone calculation are preserved; notification dispatch is split
into modules. This is the existing combined service, not a replacement Worker.

Device registration accepts `apnsEnvironment: "development" | "production"`.
Development tokens use `api.sandbox.push.apple.com`; production tokens use
`api.push.apple.com`. Older clients may omit the field. A known environment is
preserved only for the same token/topic; otherwise a legacy registration retains
the production default. The Worker never probes a token against another host.
The dashboard's historical `APNS_HOST` variable remains untouched for deployment
compatibility, but explicit per-device routing now determines the endpoint.

`BadDeviceToken` and token/topic rejections retain and block the registration.
Re-registering clears the block, and specifying the correct environment recovers
delivery. Only a confirmed APNs `410` with an invalidation timestamp can remove
the exact rejected registration; a late callback cannot delete its replacement.
Updating this Worker alone does not teach an old development app its environment:
it must receive the client update and register again.

Each occurrence/recipient records APNs acceptance independently. Atomic leases
protect overlapping cron ticks; successful recipients are not resent when a
sibling retries. `429`, `5XX`, and transport errors wait at least 15 minutes,
with at most three attempts inside a one-hour acceptance window. APNs acceptance
is not proof of iOS delivery or completed export. Network ambiguity or a Worker
crash after APNs accepts and before D1 persists the result can still cause a
duplicate; the app's occurrence handling must remain idempotent.

The schedule advances after all current recipients are accepted, or after the
window expires with an explicit failure record. A compare-and-swap protects a
schedule edited during delivery. A disabled schedule retains an internal row so
revision numbers cannot be reused. Delivery metadata is retained for 30 days and
contains no tokens or health payloads. APNs credentials remain Worker secrets.

Run the dependency-free synthetic transport and real SQLite/D1 tests:

```sh
npm test
```

Deployment uses the existing authenticated Wrangler session and exact config:

```sh
wrangler deploy --config wrangler.jsonc --dry-run --keep-vars --outdir /tmp/healthmd-apns-dry-run
wrangler d1 migrations apply DB --config wrangler.jsonc --remote
wrangler deploy --config wrangler.jsonc --keep-vars
```

Apply the additive `0002` migration before deploying. Remote migration history
already contains `0001_init.sql`; do not recreate the database. Preserve the
existing receipt and APNs secrets, production variables, D1 binding and cron.
Before claiming the fix works on a physical phone, install the signed client
update, verify a development registration, and observe a scheduled cron push and
background export with no manual push during the measurement window.

References: [APNs environments](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns),
[APNs responses](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns),
[D1 migrations](https://developers.cloudflare.com/d1/reference/migrations/).
