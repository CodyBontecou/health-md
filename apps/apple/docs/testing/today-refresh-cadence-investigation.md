# Today Refresh minute-cadence investigation

Refs https://github.com/CodyBontecou/health-md-visualizations/issues/9

## Disposition

**Investigation / partial draft, not an implementation or availability claim.**
At source base `b8fd904f4d299f5af4a22111d2fdccf829705ea7`, today's partial file can be refreshed every 3, 6, or 12 hours after the preferred time. The requested **30-minute and hourly** choices are not available on Apple or Android profile schedules. This work adds executable characterization/compatibility tests and an implementation checklist; it changes no production behavior, user data, schema, capability availability, plugin installation, or cache.

The live issue was refreshed on 2026-10-02. The reporter requests additional refresh windows; the owner agrees these belong in the app. Open PRs in the source repository and cadence-related historical PRs in both repositories were searched; no existing minute-cadence fix was found. Merged source PR #127 supplies profiles and #100 addresses Android stale scheduler generations, not these new choices.

## Deterministic findings and reproduction limits

Run the registered `HealthMdTests` using Apple CI, not by editing production UserDefaults:

1. Decode a schedule with integer `todayRefreshIntervalHours: 1` or `0`: `ExportSchedule` clamps it to **3**. This is not hourly or half-hourly.
2. Decode `todayRefreshIntervalHours: 0.5`: integer decoding throws. `ExportSchedule.load()` catches decode failure and falls back to a default schedule; changing the field type in place risks losing the usable configuration on an older reader.
3. Add a hypothetical `todayRefreshIntervalMinutes: 30` alongside legacy hours `3`: the current reader ignores the new field, still uses 3 hours, and drops the minute intent on re-encoding. An additive key alone does not establish mixed-version safety.
4. With preferred time 08:00, the legacy clamped schedule's next refresh after 08:30 or 09:00 is **11:00**. Neither requested boundary is due once the 08:00 refresh succeeded.
5. Shared Setup v2's reader, writer, and native mapper reject hour values `0` and `1` rather than approximating them. The schema enum and both Swift/Kotlin validators allow exactly `3, 6, 12`.

These are source/host-test reproductions, **not** a physical-phone reproduction of delivery delay or Obsidian refresh. There are no device receipts in this investigation. The tests that characterize current rejection/clamping must be revised deliberately when the replacement contract lands; green characterization tests do not satisfy the feature request.

## Affected surfaces

Paths below are repository-relative unless they start with `HealthMd/` or `HealthMdTests/` (Apple component-relative).

| Surface | Actual dependency / required implementation |
| --- | --- |
| Apple persistence | `HealthMd/Shared/Models/ExportSchedule.swift`: integer hours, clamp, custom decode, `exportSchedule` key. `ScheduledExportEntry.swift`: synthesized Codable, profile store `scheduledExportEntries.list`, migration and `dateMathProjection`. Preserve enable timestamps and independent success markers. |
| Reachable Apple settings | `HealthMd/iOS/Views/ScheduleSettingsView.swift`, `ProfileScheduleSection.swift`, and `HealthMd/iPad/iPadScheduleView.swift`: picker, bindings, badges/help text. Do not update only one of these. |
| Next/due/date selection | `HealthMd/Shared/Utilities/ScheduleDateMath.swift`: next and latest refresh both increment integer wall-clock hours, restart at tomorrow's preferred time. `shouldRunScheduledOccurrence` gates opt-in, same-day freshness, and last success; `exportDates` selects today independently of completed lookbacks. |
| Automatic/recovery paths | `HealthMd/iOS/SchedulingManager.swift`: coalesced run plans, profile projections, fallback notifications, pending drains and progress updates. `ScheduledExportCoordinator.swift` freezes fire date, exact owner dates, profile/destination/settings and pending ID; new slots must not expand an older residual. |
| Push metadata | `HealthMd/Shared/Managers/PushRegistrationManager.swift`: posts integer-hour metadata and uses earliest preferred time as a coalesced nudge. Do not infer that the server supports new slots from changing this client DTO. Verify the deployed server contract separately or retain an explicitly documented legacy nudge; no deployment is authorized here. |
| Portable setup | `packages/contracts/shared-setup/v2`: byte-frozen schema, canonical fixtures, coverage inventories and transaction fixtures. Apple mapper copies the entry's hours directly; both platforms validate the exact old set. Native apply/rollback/Undo must preserve old bytes and bindings. |
| Android profile parity | `ScheduledProfileEntry.kt`, `ScheduledProfileScheduler.kt`, `ProfileScheduleControls.kt`, `ProfileScheduleDialogs.kt`: integer hours and the same 3/6/12 slot set. `ScheduledProfileOccurrenceMath` feeds both arming and worker due evaluation. Preserve its frozen residual priority and refresh-only success semantics. |
| Android single schedule | `ScheduledExportTimeCalculator.kt`, `ScheduledExportOccurrence.kt`: existing minute/hour cadence and today-inclusive date windows. Minimum minute configuration is 15; this is not the independent profile Today Refresh contract. Do not remove those options or round their migration to 3 hours. |
| Consumers/docs | Shared setup codecs and transactions on both platforms, contract/core/CLI/website gates, generated website capability reference, API/destination exports, and the external Obsidian consumer. Daily export bytes need not change just because the same owner day is refreshed more often. |

## Compatibility decision needed before production edits

The desired platform-neutral outcome is: request today's partial snapshot every **30/60/180/360/720 minutes**, independently of the completed-day cadence and its lookback. Requested windows are best effort, not timers or guaranteed delivery.

A safe implementation needs a reviewed minute-capable persistence/portable intent strategy, not `0 hours = 30 minutes`, fractional values in an integer field, or a new enum value silently assigned to frozen v2:

- Preserve missing legacy fields as refresh-off / default 180 minutes, and legacy `3/6/12` hours as exact `180/360/720` minutes. Keep daily, weekly, custom anchors, targets, lookback, opt-in and progress unchanged.
- Choose an explicit local persistence version and downgrade policy. Prove older binaries cannot silently execute a different interval, erase minute intent, or discard the whole profile list. A dual-key or dual-flag scheme also needs edit/disable/downgrade round-trip tests; simply adding an optional minute key is insufficient.
- Shared Setup v2 cannot express either new choice. The v2 contract declares its fixtures and inventories byte-frozen. Repository ADR-0006 also explicitly makes v2 the sole accepted setup version. Obtain a separately reviewed successor/extension decision, **or** explicitly block sharing unrepresentable minute schedules with a safe user-facing explanation while retaining v2 unchanged. Do not export a guessed three-hour fallback or omit an active schedule without disclosure.
- Decide civil-slot semantics for DST gaps and folds before implementing minute iteration. Current 3-hour slots are local civil times: 00:30 → 03:30 spans 2 elapsed hours in spring and 4 in autumn in Los Angeles. This is verified characterization, not evidence of a delivery bug. A minute engine must specify skipped/repeated times, deterministic occurrence identity, exclusive next/inclusive due, preferred-minute phase, and reset at the next local day. Do not substitute fixed 86,400-second days.
- Implement the same profile outcome on Android in the same workstream when feasible. If staged, mark the new capability `planned` on the unstaged platform with a concrete minute-cadence target in `product-capabilities.json`, rather than claiming the existing `shared` capability already provides it. This investigation stages neither platform; the existing truthful 3/6/12 inventory stays unchanged.

**Version impact of this PR:** none. No production model, fixture, registry identity, daily schema, API envelope, raw snapshot, settings snapshot, or direct protocol changes. A future setup successor versions independently of Apple daily v8, Android daily v4/v5 and the direct protocol. Pending requests already freeze dates rather than interval intent; retain that property. Daily exporters/Obsidian parsing can remain byte-compatible, but require refreshed-day smoke receipts before claiming end-to-end completion.

## Public SDK constraints (read 2026-10-02)

- [BGTaskRequest.earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate): a lower bound only; Apple explicitly does **not** guarantee launch at that date.
- [HKHealthStore.enableBackgroundDelivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)): observer delivery is triggered by saved/deleted samples, at most at the requested frequency, with some types capped hourly (including iOS steps). It requires the background-delivery entitlement. Apple's docs require device testing; background queries are not supported on the Simulator. It is not a 30-minute polling timer.
- [Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy): locked devices encrypt the store and can prevent background reads. Denied read authorization can look like empty data; do not promise to detect it or bypass protection.

Existing scheduling combines background tasks, HealthKit observer delivery, app-open catch-up, local recovery and best-effort silent push. A faster requested interval must retain those boundaries. Connected Mac must be open/ready; quota remains one use per new durable request with exported dates, not one use per retry. A 30-minute setting could exhaust the shared Apple free quota rapidly. Setup/help text must disclose this, not promise near-real-time Obsidian updates.

## Criterion-to-evidence and remaining gates

All new tests are in existing synchronized `HealthMdTests` files, with no membership exclusions. `.github/workflows/apple-ci.yml` runs `make test-ios` and macOS `make coverage` without unit-test filters. Its UI job already registers `ExportProfilesJourneyUITests/testQA_ProfileSchedulesToggleCadenceAndEmptyStateFooter`. Cloud run receipts belong in the lane report/PR; no local tests/builds were run.

| Issue criterion | Evidence now | Still required |
| --- | --- | --- |
| Reachable persisted 30/60-minute options; retain old defaults | New `testLegacyHourReaderClampsZeroAndOneRatherThanRepresentingRequestedCadence`, `testLegacySupportedRefreshIntervalsRoundTripWithoutChangingCompletedScheduleOrProgress`; three UI source paths above | Implementation plus selectable/persisted 30/60 behavior/UI tests on iPhone, iPad and Android profiles. |
| Representation, migration, old peers | New `testLegacyReaderIgnoresUnrecognizedMinuteIntentAndDropsItOnReencode`, `testLegacyHourReaderRejectsFractionalHours`, `testLegacyRefreshMigrationPreservesAllSupportedIntervalsAndProgressAcrossReload`, `testFrozenV2RefreshGrammarRejectsZeroAndHourlyRatherThanApproximating` | Approved version/share boundary; new/old reader fixtures, invalid inputs, explicit downgrade behavior, apply/rollback/Undo. |
| Every next/due/retry calculation; 30/60 boundaries | New `testLegacyRefreshCannotMakeThirtyOrSixtyMinuteBoundaryDue`; engine/arming/projection paths above | New minute slots, exact/+epsilon boundaries, enable/disable and edit/rearm, duplicate trigger tests. Current tests prove the gap, not the fix. |
| Day and DST rollover | New `testLegacyRefreshSlotsRetainPreferredMinuteAndRestartAtPreferredTimeNextDay`, `testLegacyRefreshDSTSlotsAreCivilTimesNotFixedElapsedDurations` | 30/60-minute midnight, gap/fold and timezone-change tests for both native engines. |
| Today's partial data alongside completed lookbacks | New `testRefreshSelectsTodayWithoutReplacingCompletedLookbackAtDayRollover`; existing `testMorningAPIProfileSendsFullLookbackAlongsideTodayRefresh` | Repeat at new intervals for local, API and Connected Mac, retain capture-completeness diagnostics. |
| Interrupted retries / schedule updates / local data | Existing `testProfileLookbackRetryRunsOnlyFrozenResidualDatesAfterScheduleEdit`, `testManagerObservesScheduleEditsSavedThroughSeparateStoreInstance`, `testCompletingOlderRetryDoesNotRewindOccurrenceMarkers`, `testDeviceLockedProfileRetrySurvivesPostRunRearm` | Minute-slot retries with frozen settings/destination, cancellation, interrupted writes/relaunch, quota identity and stale notification tests. |
| Authorization/protected data/background/quota/destination | Public SDK docs above, coordinator freezing and existing lock-recovery tests | Physical locked/unlocked recurring delivery and recovery, free-quota exhaustion, unready Mac/unbound destination, denied/empty reads. |
| Equivalent Android outcome or concrete staging | Both native sources inspected; current profile inventory remains truthful | Android minute profile implementation (preferred), or reviewed `planned` target; single-schedule regression tests preserved. |
| Registered behavior and actual UI CI | Existing Apple CI registration described above; new tests execute Codable/date math/store/mapper behavior, not source grep | Successful cloud logs naming tests; add and register actual new picker UI tests when implementation lands. Simulator CI is not HealthKit background QA. |
| Truthful docs/capabilities; plugin/cache untouched | This investigation says the new options are unavailable and classifies version impact; no plugin/cache or production edits | Update setup/help/capability/generated consumer docs only when the real behavior lands. |

## Bounded next action

Review the portable-setup boundary and local downgrade policy first. Then implement minute-capable schedules on both platforms, wire all three Apple setting surfaces and Android profiles, and qualify the matrix above on GitHub-hosted CI. Record physical recurring delivery/relaunch/destination and Obsidian refreshed-day receipts separately. Keep the issue open and this PR draft while implementation, contract review or required QA is outstanding. Hardware unavailability does not justify claiming completion or publishing a release.
