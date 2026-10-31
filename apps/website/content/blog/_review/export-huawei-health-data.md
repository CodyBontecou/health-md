# Huawei export claim verification

Verified 2026-10-31 by Codex (agent), method traced. No vendor account, actual health data/export, device, simulator or visual QA accessed.

## Claims

- [x] Huawei Aspiegel regional privacy statement (path identifier 20250626; statement says last updated April 2025), sections 5.1/5.3, documents native device/portal request and machine-readable portability. No CSV schema, deadline, full-history or universal region promise. Article derives fewer than 200 words from this source.
- [x] Huawei hkgroup statement (path identifier 20260910; statement says last updated September 9, 2026), sections 4/5, documents Apple Health Kit and Android Health Connect fitness/sleep sharing with consent and the sharing menu. Explicit regional/device/history/field caveats. Fewer than 200 words derived; no third-party universal compatibility inference.
- [x] Huawei support en-us01057432 describes cloud auto/manual sync, not authorization for another phone health-store reader. No recommendation to change cloud settings or erase data.
- [x] docs-src/src/content/docs/iphone-first-export.md and health-connect-export/index.html establish permission, preview, one-day, folder and format workflow. Store links reuse maintained destinations. Health.md is downstream of phone health stores, not a Huawei account integration or importer.
- [x] apps/apple/HealthMd/Shared/Managers/HealthKitManager.swift fetchActivityData uses selected-day querySum(.stepCount) with compatibilityStatisticsPredicate, no Huawei source predicate. CSV/JSON output is not promised as original series. No new schema or metric claims.
- [x] verified-snippets.md scopes no-account/no-server copy to core folder export; chosen destinations retain separate rules. No pricing/download outcome claim.
- [x] New blog verification metadata and related navigation use existing generator; incoming related link from Zepp guide. No translated authored docs changed. Both measurement registries unchanged; no new-page action measurement claimed.
