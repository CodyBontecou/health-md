# Native hosts and shared UI tasks

Read this branch for Apple/Android hosts, shared React features, system surfaces or native state/security adapters. Consult the [native/UI design](../../architecture/javascript-unified-layer-design-reference.md#native-and-ui-migration) and the nearest actual component instructions. RN phone UI is selected; RN macOS is a candidate requiring proof.

## Prove hosts before broad UI migration

Separate Apple and Android audits feed `BASE-NATIVE`'s reconciliation of target/channel/feature/entrypoint/state authority. `SPLIT-NATIVE-HOSTS` produces a bounded packet for an iOS Release host, Android Play host, Android F-Droid dependency graph, candidate Mac host, one cold App Intent and one cold Android Worker. `SPLIT-NATIVE-FEATURES` separately plans the first feature outcomes. Each host task pins runtime/bridge/bundle versions and executes a bounded synthetic operation. Packaged offline execution, cancellation, bounded bridge/backpressure, teardown and cold lifecycle are acceptance requirements; Metro success alone is insufficient.

Mac presentation and Mac app/title acquisition are separate decisions/proofs. Resolve the signed collector's supported APIs, permission and channel/sandbox constraints independently of React presentation. Test actual signed distributions before promising title capture; retain a concrete alternative when a host/channel cannot satisfy the outcome.

## Decomposition cuts

| Design coverage | Bounded outcomes to assign | Required source/admission evidence |
| --- | --- | --- |
| Host ports/C07/C12 | One credential namespace; one destination capability; settings/profile transaction; journal reader; crypto/transport capability | Existing principals/versions, unavailable/protected data, cross-process identity, retry/crash and exact native contracts. Store relocation is separate work. |
| U01–U03 | Token/theme/font map; one readiness feature; one metric selector; profile/export configuration | Preserve existing source/readiness/selection meaning, navigation identity, accessibility and localization. Common operation owns mutations. |
| U04–U06 | Export progress/cancel; history/recovery action; one schedule configuration/entrypoint | Frozen jobs/occurrences, once-only admission, retained old-state recovery and cold execution. Split configuration from platform registration. |
| U07–U09 | One direct/local integration; provider callback/status; raw archive page; Shared Setup review/Undo | Actual protocol/provider state and authority. Unqualified setup/data capabilities remain planned. |
| U10 | Report configuration/model; native tagged PDF renderer | Existing local-only 11-metric clinician report, factual missingness, paired BP and ephemeral display-name policy. No Practice/network side effect. |
| U11 | Entitlement presentation; Apple lifetime/restore; Play admission; F-Droid/Mac exclusions | Preserve platform accounting/commerce differences and actual prices/restore authority. Mac Release does not initialize StoreKit. |
| U12 | One diagnostics/privacy/help/release-note projection | Allowlisted content-free telemetry, channel exclusions and deliberate external navigation. |
| U13–U16 | One source/domain selector; bounded timeline; visit/correction/map feature; usage history/category/title feature; combined export/import/schedule preview | Corresponding personal-data operations and qualified source capabilities. Aggregate/display-only/partial states are visible. |
| U17–U18 | One Cloud destination/account/archive state; one agent consent/revoke/lifecycle feature | Cloud operations and current grant/identity contracts; source/recipient admission; no automatic authority from sign-in or purchase. |
| Native extensions | One widget family; independent watch HealthKit snapshot; location watch queue/Stop Live Activity; native automation action; Wear snapshot adapter | Existing IDs/wire/app-group/expiry/grants, native lifecycle. Watch retains independent capture; Wear remains phone-authoritative with separate publication gates. |

## Qualification and integration

Every UI child tests observable actions/state and its real operation wiring. Cover existing themes, large text, RTL, screen readers, keyboard/Back/focus, reduced motion and adaptive layouts as applicable. Reuse portable feature-model tests; native E2E covers integration rather than duplicating every pure assertion. Native permissions/maps/reports/purchases remain explicit adapters.

One writer owns each Xcode project/target graph, Gradle configuration, lockfile, generated bridge and shared UI primitive/interface. Reserve those resources when a task needs them; parallelize feature modules only after stable interfaces. React rendering never admits capture or writes state. Capture, background services and cold intents operate without a mounted screen.

Split code/synthetic, host integration, physical lifecycle, signed distribution and store publication into separate child tasks/receipts. Physical tests cover kill/reboot/first unlock, revoke/permission loss, energy and actual capture coverage. Store approval and minimum-OS/support changes are product/release decisions. An implemented screen cannot close a platform-capability, installed-state, distribution or retirement gate.
