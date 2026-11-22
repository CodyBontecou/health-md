# Huawei export claim verification

Verified 2026-11-22 by Claude (agent), method traced; Huawei pages re-read live 2026-11-22. Earlier trace 2026-10-31 by Codex (agent). No vendor account, actual health data/export, device, simulator or visual QA accessed.

## Claims

- [x] Huawei Aspiegel regional privacy statement (path identifier 20250626; statement says last updated April 2025), sections 5.1/5.3, documents native device/portal request and machine-readable portability. No CSV schema, deadline, full-history or universal region promise. Article derives fewer than 200 words from this source.
- [x] Huawei hkgroup statement (path identifier 20260910; statement says last updated September 9, 2026), sections 4/5, documents Apple Health Kit and Android Health Connect fitness/sleep sharing with consent and the sharing menu. Explicit regional/device/history/field caveats. Fewer than 200 words derived; no third-party universal compatibility inference.
- [x] Huawei support en-us01057432 describes cloud auto/manual sync, not authorization for another phone health-store reader. No recommendation to change cloud settings or erase data.
- [x] docs-src/src/content/docs/iphone-first-export.md and health-connect-export/index.html establish permission, preview, one-day, folder and format workflow. Store links reuse maintained destinations. Health.md is downstream of phone health stores, not a Huawei account integration or importer.
- [x] apps/apple/HealthMd/Shared/Managers/HealthKitManager.swift fetchActivityData uses selected-day querySum(.stepCount) with compatibilityStatisticsPredicate, no Huawei source predicate. CSV/JSON output is not promised as original series. No new schema or metric claims.
- [x] verified-snippets.md scopes no-account/no-server copy to core folder export; chosen destinations retain separate rules. No pricing/download outcome claim.
- [x] New blog verification metadata and related navigation use existing generator; incoming related link from Zepp guide. No translated authored docs changed. Both measurement registries unchanged; no new-page action measurement claimed.

## Added 2026-11-22 refresh

- [x] https://consumer.huawei.com/es/support/content/es-es15919588/ (Huawei, Spanish; read live): HUAWEI ID → Privacy Centre → Request Your Data → Health; email when ready, "puede tardar varios días"; unzip with the password set during the request; "motion path detail data & description" folder; JSON records covering 15 days, not one file per workout; convert before Strava import, no converter named; single route: Health → Exercise records → outdoor workout → Route → Export route, choose format; Strava: update app, Me → Privacy management → Data sharing and authorization → Strava → connect. The article does not say older activities are copied; the page says so only as "does not say".
- [x] https://consumer.huawei.com/en/support/content/en-us00746223/ (Huawei; read live): Privacy Centre > Request Your Data; data available for download for 21 days, then resubmit; app data as .json, .csv or .pdf. Presented as HUAWEI ID account-data rule, not Health-specific.
- [x] https://privacy.consumer.huawei.com/tool kept as the portal link (unchanged).
- [x] Troubleshooting (email address, spam folder) is generic practical advice, not a Huawei claim; the 21-day and several-days points are from the sources above. No claims about Huawei internal delays.
- [x] Not cited: Strava's upload limits (not used). No claim about Huawei → Health Connect/Apple Health mappings beyond the existing regional statement. Post never says Health.md imports, connects to Huawei, backfills or converts Huawei JSON.
- [x] Inbound link added from export-strava-data; related list now export-strava-data, export-zepp-amazfit-data, export-health-connect-to-obsidian.
