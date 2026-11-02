# Health.md paid-access privacy review

**Unpublished candidate review. No deployment, submission, release, price change or remote data deletion.**

Apple and Android Play app analytics and attribution are removed. F-Droid continues without telemetry. Receipt verification for earlier paid access, APNs scheduling, direct-device sessions, optional provider OAuth, user-selected endpoints and the separately opt-in single-owner Cloud pilot remain disclosed. The local Apple privacy manifest removes analytics-only declarations and retains the existing App Functionality declaration pending a full essential-service taxonomy review.

## Shared removal policy

The candidate contains no custom analytics client, event queue, upload job, persistent analytics identifier, pricing-experiment assignment or app advertising-attribution collector. Debug flags and bundle/environment endpoints cannot re-enable the removed implementation. Upgrade cleanup removes known analytics-only local state while preserving purchase entitlements, local content, export history, scheduling identities and app settings used by essential features.

The analytics-only Worker is replaced locally with a storage-free retirement responder: legacy uploads receive HTTP 204 and are discarded without reading the body. No D1/KV binding, analytics cron, aggregate generation or analytics retention mechanism remains in the candidate Worker. The abandoned opt-in/30-day event design is superseded and its unapplied migration is removed. Historical applied migrations remain as provenance. No migrations or remote deletions were executed.

## Older versions and existing records

This is an unpublished source change. Previously distributed binaries, submitted builds and deployed services remain unchanged and can still send/accept analytics. No claim that collection has stopped in production is approved here. Retained installation-linked events are pseudonymous, not anonymous. Updating or uninstalling does not erase previously received events, operator exports, provider logs or recovery copies.

After separate owner approval: deploy the discard responder first, confirm writes have stopped, erase the dedicated analytics database and analytics-only exports, review processor logs/recovery retention, and record actual deletion/expiry evidence. Inspect ownership before deleting resources. Do not reassign analytics identifiers to essential services. A new signed app candidate and an approved cutover are required before the replacement policy becomes effective.

## Essential services and review decisions

Purchase validation/restoration, scheduling, provider authorization, selected file/API destinations, local diagnostics and support remain governed by their actual purpose and existing implementation. They must not gain product-event logging. Removing analytics does not establish a new retention or deletion guarantee for those services. Do not claim universal “Data Not Collected,” “anonymous,” “no servers,” or deletion on uninstall.

Before submission, review App Privacy / Play Data Safety for the exact candidate and every essential processor. Remove analytics purposes only where no remaining collection supports them; retain App Functionality declarations for applicable identifiers, purchase verification and scheduling. Verify provider logs, account linkage, legal URLs and native-language text. No questionnaire or store metadata was changed remotely. Prices and product IDs are unchanged. Myself.md claim entry points remain disabled; earlier retained grants need their existing disclosure.

Website traffic measurement is separate from in-app collection and remains disclosed under the website policy. No website measurement exemptions are asserted by this change.

## Prepared candidate cutover

The 3.5.0 candidate must be qualified against its exact processed build before submission. Development-build, simulated StoreKit, and single-account checks do not establish release-binary or cross-account Family Sharing qualification. Public policy/terms and App Privacy publication remain held. The staged policy applies to this candidate when released and preserves earlier-version and historical-record disclosures.

The candidate Apple privacy manifest retains linked User ID and Device ID for App Functionality. The scheduling service stores APNs device tokens with the scheduling user ID in its `devices` table; these device identifiers remain essential after analytics retirement. The published Device ID declaration must include App Functionality and identity linkage while retaining Analytics until the older collector retires. Purchase History, Product Interaction, Advertising Data and Other Usage Data remain analytics declarations from older versions; prepare their removal only after the legacy endpoint stops accepting records. Do not remove Device ID with the analytics-only types. Keep the essential scheduling/receipt/provider service disclosures; the separately opted-in Cloud/CLI pilot is described in the wider product policy and is not a claim of default app upload. The Mac companion remains free and receives selected exports from iPhone; it does not read HealthKit on its own.

The existing analytics declarations remain necessary for older clients while their collector is live. Correcting the essential device-identifier purpose does not retire those analytics declarations. Do not publish a reduced declaration or claim that historic data is erased before the coordinated service cutover. No Worker deployment, database deletion or questionnaire publication is included in candidate preparation.

The final App Store description and staged terms distinguish eligible seven-day trials, auto-renewal, immediate one-time Lifetime billing, cancellation in Apple Account settings, existing paid rights, and Family access versus private content. No live lifetime price or regional schedule is changed. New Mac listing translations are machine assisted and checked mechanically; native-language sign-off is not claimed.

Reference: [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
