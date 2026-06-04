# Scheduled APNs Worker Contract

This checkout currently contains `worker/pricing-analytics/`, not the scheduled-export APNs worker implementation. Treat this file as the migration contract for the scheduled worker when it is added or updated.

## Client endpoints

The Health.md client keeps using the existing production worker base URL configured in `PushRegistrationManager`:

```text
https://healthmd-receipt-verifier.costream.workers.dev
```

The reusable client contract lives in `HealthMd/Shared/ExportAutomationKit/ExportAutomationScheduling.swift`.

### `POST /devices/register`

Register or refresh APNs routing metadata for one app installation.

Allowed JSON fields:

```json
{
  "userId": "stable-install-id",
  "platform": "ios",
  "apnsToken": "hex-apns-token",
  "bundleId": "com.example.app",
  "appVersion": "1.2.3",
  "appBuild": "456"
}
```

`appVersion` and `appBuild` are optional. Health.md currently omits them from live requests to preserve the deployed worker behavior until the worker migration stores those fields.

### `POST /schedules/upsert`

Create, update, disable, or unregister one installation's schedule. A disabled payload is the unregister/update path.

Allowed JSON fields:

```json
{
  "userId": "stable-install-id",
  "timezone": "America/New_York",
  "schedule": {
    "isEnabled": true,
    "frequency": "weekly",
    "hour": 8,
    "minute": 30,
    "weekday": 1
  }
}
```

For daily schedules, omit `weekday`. To unregister/disable server pushes, send the same shape with `schedule.isEnabled` set to `false`.

## Stored server state

The scheduled worker may store only routing and timing metadata:

- stable install/user id;
- platform;
- bundle/app id;
- APNs token;
- optional app version/build;
- timezone;
- schedule enabled flag;
- frequency;
- hour;
- minute;
- weekly weekday;
- computed next-fire timestamp and worker bookkeeping.

The worker must not store exported records, generated files, user destination paths, template strings, selected data categories, category names, values, vault contents, or local pending-export retry dates.

## Silent APNs payload

Due schedules send background-only APNs:

Headers:

```text
apns-push-type: background
apns-priority: 5
apns-topic: <bundleId>
```

Body:

```json
{
  "aps": { "content-available": 1 },
  "type": "scheduled-export",
  "scheduledFireDate": "2026-06-04T08:00:00Z"
}
```

`scheduledFireDate` is optional but recommended so the app can prepare/reuse the exact scheduled occurrence. The payload must not include alerts, sounds, badges, exported data, file contents, destination paths, template strings, selected categories, category names, or category values.

## Migration notes

- Do not modify `worker/pricing-analytics/` for scheduled APNs; it is a separate analytics worker.
- Add the scheduled worker in its own worker directory or upstream worker repo.
- Keep the current Health.md endpoint paths (`/devices/register`, `/schedules/upsert`) unless the client is migrated in the same release.
- Compute `next_fire_at` server-side from timezone, frequency, hour, minute, and optional weekday.
- Cron should find due enabled schedules, send the silent APNs payload above, then advance `next_fire_at`.
- If a future visible fallback is added, it must use a separate client acknowledgement model and remain routing-only.
