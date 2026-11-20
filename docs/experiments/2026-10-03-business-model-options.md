# Business-model experiment options

Date: 2026-10-03. Status: proposal / research only; no production products, prices,
entitlements, store listings, or experiments changed. Store documentation was checked
on this date. Recommendations below are proposals, not measured results or a promise
of App Review approval.

Later direction: this proposal was not adopted as written. See
[five free exports and the next export journey](./2026-10-24-five-free-exports.md) and
[paid access, trials, and subscriptions](../../apps/apple/docs/experiments/subscription-pricing-rollout.md)
for what was subsequently implemented.

## Store feasibility

Both stores permit recurring subscriptions for continuing value. Apple requires ongoing
value; Google requires sustained or recurring value and directs effectively one-time
benefits to one-time products. Recurring automated exports could provide that value,
but charging monthly for the existence of a scheduling toggle is a weaker proposition
than consistently delivering maintained automation. This distinction is our product
judgment, not a store decision about Health.md.
Sources: [Apple subscription guidance](https://developer.apple.com/app-store/subscriptions/)
and [Google subscription policy](https://support.google.com/googleplay/android-developer/answer/9900533?hl=en).

Apple allows subscriptions alongside other purchase types and explicitly says a transition
must preserve primary functionality existing customers already paid for. New functionality
and product changes must be documented and accessible to reviewers. Configure every
experiment arm so it can be reviewed; do not hide a future paywall behind remote activation.
Sources: [App Review Guidelines, sections 2.1, 2.3.1, and 3.1.2](https://developer.apple.com/app-store/review/guidelines/).

A lifetime unlock should use a non-consumable Apple purchase and a non-consumed Google
one-time purchase. Monthly and annual access use subscription products. Apple's
non-consumables do not expire or decrease with use; changing the selling price cannot
change the scope of an already purchased entitlement. The latter is our migration rule.
Sources: [Apple purchase types](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/)
and [Google billing integration](https://developer.android.com/google/play/billing/integrate).

Default to StoreKit / Play Billing for digital features. Regional alternative-payment
programs have separate conditions and are unnecessary for an initial packaging experiment.
Show localized store prices, billing period, renewal terms, trial conversion price, paid
benefits, and whether users can continue for free. Annual totals must be conspicuous.
Sources: [Apple App Review Guidelines, section 3.1.1](https://developer.apple.com/app-store/review/guidelines/),
[Google payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en),
and [Google subscription presentation policy](https://support.google.com/googleplay/android-developer/answer/9900533?hl=en).

## Three different kinds of testing

| Test | Mechanism | What it answers |
| --- | --- | --- |
| Acquisition presentation | Apple's Product Page Optimization tests icons, screenshots, and previews; Play listing experiments test graphics and localized text | Which store presentation gets installs / retention; it does not configure app entitlements |
| Lifetime price | Google Play price experiments randomize prices for active one-time products / purchase options in selected regions | Which one-time price produces more revenue; not subscription versus lifetime or free exports versus paid scheduling |
| Business-model packaging | Persistent random assignment inside the app selects approved products, paywall presentation, and free/paid feature policy | Whether an alternative package improves activation, retention, and proceeds |

Sources: [Apple Product Page Optimization](https://developer.apple.com/app-store/product-page-optimization/),
[Google listing experiments](https://google.play/business/store-listing-experiments/),
[Google one-time price experiments](https://support.google.com/googleplay/android-developer/answer/16643292?hl=en),
and [Firebase app A/B testing](https://firebase.google.com/docs/ab-testing).

Firebase demonstrates that both iOS and Android can test behavior through Remote Config.
It is an available mechanism, not a recommendation to add its analytics SDK: Health.md
already has a deliberately bounded analytics contract. A small first-party assignment/config
layer can serve the same experiment purpose. Server configuration selects a package;
verified purchase state remains the entitlement authority. That architecture is our proposal.
Source: [Firebase app A/B testing](https://firebase.google.com/docs/ab-testing).

Apple's documented purchase price schedules make immediate or future product/territory
price changes. Those changes should be treated as time/territory cohorts, not a randomized
packaging test. Simultaneous iOS offers at different prices need separately configured
products and app assignment. An approved-product configuration and entitlement migration
must precede rollout.
Source: [Apple managing in-app purchases](https://developer.apple.com/documentation/appstoreconnectapi/managing-in-app-purchases).

On Google Play, subscriptions define benefits, base plans define periods/renewal/prices,
and offers define eligible discounts. Choose a deliberate model for subscription price
variants; a discount that returns to the original base price is a trial/offer test rather
than a permanent-price test. Google documents alternative configurations for experimentation.
Source: [Google subscription object model](https://support.google.com/googleplay/android-developer/answer/12154973?hl=en).

## Required entitlement and measurement work

For a subscription launch, verify purchases and handle renewal, cancellation, expiration,
billing retry/grace, restore, refund, and revocation. Apple offers signed transaction state,
Server API, and Server Notifications V2. Google recommends backend verification and
acknowledgement; RTDN subscription messages require an API read for complete current state.
Sources: [Apple Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/),
[Apple Server API](https://developer.apple.com/documentation/appstoreserverapi),
[Google purchase security](https://developer.android.com/google/play/billing/security),
and [Google RTDN reference](https://developer.android.com/google/play/billing/rtdn-reference).

Proposal: keep a commerce boundary separate from the current privacy-allowlisted analytics
Worker. Do not put receipt payloads, purchase tokens, health content, or account identity into
the existing pricing-event table. Its current contract is documented in the
[pricing Worker runbook](../../apps/apple/worker/pricing-analytics/README.md).

Proposal: exclude existing paid customers from restrictive tests, preserve their paid scope
through restore/reinstall, and randomize new eligible installs persistently. Analyze iOS and
Android separately before pooling; region, version, eligibility, and exposure timing matter.
Use net proceeds per assigned eligible install as the decision metric, with activation,
refunds, paid retention/renewals, and successful scheduled delivery as guardrails. A short
conversion test cannot establish subscription lifetime value. Predeclare the observation
window and a meaningful detectable effect after examining eligible traffic.

## Repository-specific assessment

The shipped product described by the repository is lifetime-based, not an active subscription
business. Apple permits ten accounted export actions shared across manual, scheduled,
Shortcut, and direct workflows; Full Access removes that quota. Android Play permits ten
manual actions and gates scheduling behind premium access; F-Droid includes full access.
These are documented/code behaviors, not a fresh check of deployed store products or prices.
Sources: [Apple Full Access](../../apps/apple/docs/features/full-access-unlock.md),
[Apple scheduling](../../apps/apple/docs/features/scheduled-exports.md),
[Android lifetime/distribution](../../apps/android/docs/features/lifetime-unlock.md),
and [Android scheduling](../../apps/android/docs/features/scheduled-exports.md).

Apple has install-local persisted experiment assignment and privacy-bounded pricing events.
Its assignment store saves the variant supplied by configuration; it does not itself
randomly split users. Pricing configuration supports opt-in product selection. This is useful
scaffolding, not a ready business-model test. The current global unlock/quota model also
needs capability-level decisions for free manual access versus paid automation.
Sources: assignment store (removed; see `b8ded3597:apps/apple/HealthMd/Shared/Analytics/PricingExperimentAssignment.swift`),
pricing config (removed; see `b8ded3597:apps/apple/HealthMd/Shared/Analytics/PricingExperimentConfig.swift`),
and [PurchaseManager](../../apps/apple/HealthMd/Shared/Managers/PurchaseManager.swift).

The current Apple analytics client obtains the baseline assignment by default; the inspected
runtime does not wire the config resolver into a randomized allocator. Apple exposes only
individual/family lifetime purchase choices, and Play Billing queries one lifetime product
using `INAPP`. A subscription test therefore requires billing and entitlement implementation
on both platforms, not only a config change.
Sources: Apple analytics client (removed; see `b8ded3597:apps/apple/HealthMd/Shared/Analytics/PricingAnalyticsClient.swift`),
[Apple purchase manager](../../apps/apple/HealthMd/Shared/Managers/PurchaseManager.swift),
and [Play billing](../../apps/android/app/src/play/java/com/healthmd/data/billing/BillingRepositoryImpl.kt).

Android's current analytics cover onboarding and purchase taps, not completed export and
purchase lifecycle outcomes. Fill that gap before interpreting a Play experiment's revenue
or activation. Report iOS and Play separately, and exclude F-Droid from commerce denominators.
Source: [pricing analytics measurement limits](../../apps/apple/worker/pricing-analytics/README.md).

The recorded Apple $14.99 window (June 1–September 16) had 1,542 activated users, 304 purchases,
and $2.78 proceeds per activated user. Raising the free allowance from three to ten on July 27
approximately halved paywall exposure. Those historical comparisons include cohort, traffic,
and product changes and cannot establish a causal price effect. The prior subscription
transition never became purchasable: all 70 attempts failed `store_unavailable`, so it does
not measure willingness to subscribe. The documented $19.99 experiment remains in progress,
with a planned decision no earlier than October 8. Verify its current outcome and formally
finish or close it before starting an overlapping business-model experiment.
Source: [operational price experiment](2026-09-17-19.99-lifetime-price.md).

## Recommended first experiment

Product hypothesis: unlimited manual portability increases adoption, while people who want
their files and integrations kept current will pay for maintained automation. This is a
hypothesis about demand, not evidence that subscriptions will outperform lifetime sales.

Power users can recreate schedules using external Shortcut, Tasker, or CLI timers if those
export entry points become unlimited. Decide the shared paid boundary explicitly. The
commercial value should include saved setup and maintenance effort, successful execution,
and recovery; an in-app scheduling toggle alone is easy to substitute. This is an inference
from the current shared export gates and automation surfaces.
Sources: [Apple Shortcuts](../../apps/apple/docs/features/apple-shortcuts.md),
[Apple Direct CLI](../../apps/apple/docs/features/cli-direct-iphone.md),
and [Android automation intents](../../apps/android/docs/features/automation-intents.md).

| Arm | New-user offer | Question |
| --- | --- | --- |
| A | Current free allowance and lifetime package, with verified current store prices | Control |
| B | Unlimited manual exports; paid Automation access, offered monthly and annually | Can recurring convenience replace revenue lost from the manual-export gate? |

Keep current paid and legacy entitlements outside restrictive randomization. Make assignment
stable within an installation and keep purchased rights independent of future experiment
configuration. Reinstall/cross-device assignment needs an explicit design; current
install-local persistence does not establish person-level assignment across devices.

An ownership option at a higher lifetime price is worth exploring. If offered in arm B,
the result compares complete packages, including that option; it will not isolate the free
boundary, recurring billing, and price effects. Alternatively, test the lifetime option
after selecting the package. A lifetime price around three to four annual payments is an
illustrative starting hypothesis, not a validated optimum. Preserve the scope originally
promised to existing lifetime buyers, including any promised future premium features.

Subscriptions for the whole app are another feasible hypothesis. They may earn more from
committed users but can reduce adoption among people who only need a backup or occasional
export. Test that package after the first two-arm experiment rather than splitting limited
traffic among three or more models immediately. Annual billing deserves an explicit option;
monthly-only billing does not address users who want a continuing workflow with fewer bills.

Use 60/90-day net proceeds per randomized eligible install, counting renewals, refunds, and
relevant variable costs. If assigning before activation, do not make proceeds per activated
user the primary metric: the offer can itself change who activates. Supporting measures are
first successful export, schedule setup and successful execution, paid retention/renewals,
refunds, support burden, and export failures. Cancellation usually stops renewal while paid
access continues to the applicable expiration; test that distinction in entitlement handling.
Sources for lifecycle semantics: [Apple subscriptions](https://developer.apple.com/app-store/subscriptions/)
and [Google subscription lifecycle](https://developer.android.com/google/play/billing/lifecycle/subscriptions).

The historical window implies roughly 14 activated users/day, or about 200 per arm/month
before eligibility exclusions in a two-way split. This is not current traffic and is not a
power calculation. Set sample requirements using fresh eligible traffic and proceeds variance;
60/90-day reads are maturity checkpoints, not automatic proof of a winner. More subscriptions
or higher first-month conversion do not establish higher lifetime value.

Sell the continuing outcome: keeping a personal health archive and integrations current,
with status and recovery. Scheduling still obeys native limits: iOS silent pushes cannot
guarantee runtime or bypass locked-device HealthKit protection; Android timing depends on
permissions/background execution. The offer must describe these limits accurately, and
successful ongoing execution should be a retention guardrail.
Sources: [Apple scheduling](../../apps/apple/docs/features/scheduled-exports.md)
and [Android scheduling](../../apps/android/docs/features/scheduled-exports.md).

## Market reference and additional ideas

Health Auto Export's own FAQ lists Premium at $0.99/month, $5.99/year, and $24.99 lifetime,
including automation and multi-device sync. That establishes a current public comparison,
not competitor conversion or a ceiling on Health.md pricing. A substantially higher price
needs differentiated workflow value and actual demand evidence. Health Sync also offers
one-time access or a six-month subscription, with a separately subscribed Withings integration.
Sources: [Health Auto Export FAQ](https://help.healthyapps.dev/en/health-auto-export/faq/)
and [Health Sync pricing description](https://healthsync.app/about/).

Additional proposals, in order of proximity to the existing product:

1. **Automation bundle:** multiple scheduled profiles, recurring API/agent workflows, and
   maintained integration convenience. Define manual versus externally scheduled CLI/Shortcut
   use consistently so the same outcome has the same paid boundary on both platforms.
2. **One-time workflow packs:** polished Obsidian templates, dashboards, and report layouts
   can fit customers who prefer ownership. Validate demand before building a catalog, and
   respect existing paid promises when packaging current capabilities.
3. **Paid setup and priority support:** configuration help for personal vaults, APIs, and
   agent workflows; a service opportunity that does not depend on charging for each export.
4. **Optional supporter membership:** investigate whether the open-source/local-first audience
   wants to support maintenance voluntarily, particularly where F-Droid includes full access.
5. **Practice/team licensing:** a separate B2B opportunity when the clinician workflow is ready;
   retain Practice's independent product, service, and clinical-data boundary. Its current
   pilot document records pending approvals, not an approved launch.

Product references: [feature inventory](../../apps/apple/docs/features/index.md),
[Android distribution](../../apps/android/docs/features/lifetime-unlock.md),
and [Practice product status](../product/practice/README.md).

These are candidates for research, not changes to existing access. Monetizing retained health
data or advertising against it would conflict with the local-first promise; the recommended
offers charge for software, continuing convenience, and services instead.
Source: [privacy product promise](../../apps/apple/docs/features/privacy-local-first.md).
