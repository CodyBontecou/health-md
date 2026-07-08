# Health provider beta test checklist

Use this checklist when a tester has access to a device/account that maintainers do not. Ask testers to share the redacted diagnostics report from **Settings → Health diagnostics → Share redacted diagnostics** rather than screenshots of health data or token screens.

## What the diagnostics report contains

The report is designed for provider verification and support triage. It includes:

- App version/build type.
- Whether an export folder is configured.
- Selected and connected health-provider IDs.
- For each supported provider: installed yes/no, OAuth configured yes/no, OAuth token present yes/no, provider availability, and Health Connect permissions where relevant.
- Last export result category, failed-date counts, and failure reasons.

The report intentionally excludes:

- Health measurements.
- OAuth access tokens and refresh tokens.
- Provider client secrets.
- Raw file paths.
- Full provider API responses.

## General tester flow

1. Install the internal/beta build.
2. Open **Settings → Health sources**.
3. Confirm **Health Connect** is still selected by default.
4. For the provider being tested, complete the setup path:
   - Health Connect source providers: enable sharing from the provider app into Health Connect, then grant Health.md Health Connect permissions from the Export screen.
   - OAuth providers: connect through the provider sign-in flow only if the app build is configured with a client ID or token broker.
5. Export **yesterday** first, then **today** if the provider normally syncs same-day data.
6. Confirm the output has the expected categories for that provider: steps/activity, sleep, heart, body, workouts, or vitals.
7. If anything is missing or wrong, share:
   - the redacted diagnostics report,
   - provider name/device model,
   - which date was exported,
   - which category looked wrong,
   - whether the provider app showed data for that date.

## Provider-specific checks

### Samsung Health

- Verify Samsung Health is installed and syncing from the wearable/phone.
- In Samsung Health, enable sharing to Health Connect if available.
- In Health Connect, confirm Health.md has read permissions.
- Export a date with known steps, sleep, and workout data.

### Huawei Health

- Verify Huawei Health is installed.
- Note whether this is a Play build or an HMS/AppGallery build.
- Direct HMS Health Kit import is not considered verified until the HMS app configuration is complete.

### Fitbit

- Prefer Health Connect validation first if Fitbit is writing to Health Connect on the tester device.
- For direct OAuth validation, confirm the build has `FITBIT_CLIENT_ID` or `FITBIT_TOKEN_BROKER_URL` configured.
- Export a date with sleep, steps, heart rate, and weight if available.

### Garmin Connect

- Direct Garmin import requires Garmin Health API partner approval and usually backend/webhook sync.
- For now, verify Garmin-origin data only if it reaches Health Connect through the tester's setup.

### Withings

- For direct OAuth validation, confirm the build has `WITHINGS_CLIENT_ID` or `WITHINGS_TOKEN_BROKER_URL` configured.
- Export a date with scale/body data and activity/sleep if available.
- Check weight units and body-fat percentage carefully.

### Oura

- For direct OAuth validation, confirm the build has `OURA_CLIENT_ID` or `OURA_TOKEN_BROKER_URL` configured.
- Export a date with sleep, readiness/activity, heart-rate samples, and workouts if available.
- Oura often finalizes sleep after sync; prefer yesterday over today.

### Polar Flow

- Direct Polar history import still needs an AccessLink transaction cache before production verification.
- For now, validate only token setup state or Health Connect-origin data if available.

### WHOOP

- For direct OAuth validation, confirm the build has `WHOOP_CLIENT_ID` or `WHOOP_TOKEN_BROKER_URL` configured.
- Export a date with sleep/recovery and workout data.
- WHOOP recovery is cycle-based; prefer a fully processed prior day.

## Maintainer triage

When a tester sends a diagnostics report:

1. Check app version/build type first.
2. Confirm the intended provider is selected and connected.
3. Confirm OAuth configured/token-present state for direct providers.
4. Confirm Health Connect availability/permissions for Health Connect source providers.
5. Compare last export failure categories with the tester's narrative.
6. If the report shows permissions/token ready but data is absent, request a redacted sample export for one date and add a fixture test for that provider response shape before changing mapping logic.
