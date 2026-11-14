# Subscription retention messages and offers

Paste-ready store configuration for the cancel flow on both stores. Nothing here has been created in App Store Connect or Play Console. Offer identifiers and reference names are permanent once saved, so confirm each one before saving it. Every `[YOUR PRICE]` is an owner decision set per storefront or region; the apps never hard-code these prices.

Sources: the Health.md iOS design canvas, page "Retention Messages" (boards `RM_*`), and the Android canvas, page "Retention Flow" (boards `RF_*`). Product IDs match `apps/apple/HealthMd.storekit` and `PurchasePlan` in `apps/android/app/src/main/java/com/healthmd/domain/repository/PurchaseRepository.kt`.

## How each store shows these

- **App Store.** Apple shows the retention message when a subscriber taps Cancel in Apple's subscription management. It appears inside Health.md because the app's "Manage subscriptions" control opens `.manageSubscriptionsSheet` (`apps/apple/HealthMd/iOS/Views/PaywallView.swift`), not a Safari link. You write the header, body and image. Apple renders the buttons and the offer card. An eligible subscriber sees the offer in place of the image.
- **Dates on Android.** The Play Billing client exposes no renewal or end date. Settings › Subscription sends the owned subscription's purchase token to `POST https://myself.md/api/health-md/play-subscription`, which reads `purchases.subscriptionsv2.get` with the owner's service account and returns only the product, state, expiry and auto-renew flag. The app then shows "Next billing date" or "Access until" with that date, and "Before you go" says "You keep access until <date>". If the read fails (endpoint not deployed, service account lacks subscription access), the rows say "Shown in Google Play" as before and the app retries at most hourly.
- **Google Play.** Play renders its own cancel screens, and developers can't set text or images there. You only configure the offers. The app's own "Before you go" sheet (Settings › Subscription › Manage or cancel) states the facts and then opens `https://play.google.com/store/account/subscriptions?sku=<productId>&package=<applicationId>`.

## Copy rules (both stores)

- Header, body and image contain no prices, discounts or free time. Offer terms appear only in the store's offer card.
- Loss statements are factual and match the app's gating. Both platforms allow one free export. After that, new exports, scheduled exports and automations need an active subscription or Lifetime. Exported files stay in the folder the user chose.
- No urgency, superlatives, all-caps or exclamation marks.

## App Store Connect: retention messages

Subscription group: **Health.md Pro**. Lifetime (`com.codybontecou.obsidianhealth.unlock`, `…unlock.family`) is a non-consumable, so it gets no retention message. The plan below uses 4 of the 10 available messages.

### RM-A · Individual Weekly · What stops

| Field | Value |
|---|---|
| Reference name | `RM-A · Individual Weekly · What stops` |
| Subscription | Individual Weekly · `com.codybontecou.obsidianhealth.pro.weekly` |
| Header (44 chars) | Daily notes stop when your subscription ends |
| Body (152 chars) | You'll lose access to new exports, scheduled daily notes and automations when your subscription ends. Notes you've already exported stay in your folder. |
| Image | Board `RM_Img_A`, exported at 1× as a 3840×2160 PNG |

Why: weekly subscribers use the app most, so the message names exactly what stops.

### RM-B · Individual Yearly · Yours to keep

| Field | Value |
|---|---|
| Reference name | `RM-B · Individual Yearly · Yours to keep` |
| Subscription | Individual Yearly · `com.codybontecou.obsidianhealth.pro.yearly.v2` |
| Header (36 chars) | Your health archive is yours to keep |
| Body (143 chars) | Every note you've exported is a plain file in the folder you chose, and it stays there. When your subscription ends, new days won't be written. |
| Image | Board `RM_Img_B`, exported at 1× as a 3840×2160 PNG |

Why: yearly subscribers have the largest archive, so the message talks about the files they already own.

### RM-C · Family · Shared access

| Field | Value |
|---|---|
| Reference name | `RM-C · Family · Shared access` |
| Subscriptions | Family Weekly · `com.codybontecou.obsidianhealth.pro.family.weekly` and Family Yearly · `com.codybontecou.obsidianhealth.pro.family.yearly.v2` |
| Header (29 chars) | Your family's access ends too |
| Body (184 chars) | When this subscription ends, everyone you share it with through Family Sharing loses access to new exports, schedules and automations. Exported files stay where each person saved them. |
| Image | Board `RM_Img_C`, exported at 1× as a 3840×2160 PNG. Its "Family Sharing · up to 6" caption is an Apple fact; remove it if family size changes. |

If App Store Connect ties a message to a single subscription, duplicate this one as `RM-C · Family Weekly` and `RM-C · Family Yearly`.

### Localization

The primary language is English (U.S.). Localize the header and body for every storefront where the subscriptions are sold. The app ships de, es, fr, it, ja, ko, nl, pt-BR and zh-Hans. Still to do: write the translations, confirm the storefront list, and check the character limits App Store Connect enforces for the header and body.

## App Store Connect: retention offers

Each offer appears in Apple's offer card for eligible subscribers. Set per-country prices for every storefront.

| Subscription | Message | Offer type | Reference name | Offer identifier | Eligibility |
|---|---|---|---|---|---|
| `…pro.weekly` | RM-A | Pay as you go · 4 weeks at [YOUR PRICE]/week | Individual Weekly · Retention · 4 weeks | `pro.weekly.retention.payg4w` | Minimum paid subscription duration [e.g. 1 month] · wait between offers [e.g. 6 months] |
| `…pro.yearly.v2` | RM-B | Pay up front · 1 year at [YOUR PRICE] | Individual Yearly · Retention · 1 year | `pro.yearly.v2.retention.upfront1y` | Minimum paid duration [e.g. 1 year, so at least one paid renewal] · wait between offers [e.g. 1 year] |
| `…pro.family.weekly` | RM-C | Pay as you go · 4 weeks at [YOUR PRICE]/week | Family Weekly · Retention · 4 weeks | `pro.family.weekly.retention.payg4w` | Minimum paid duration [e.g. 1 month] · wait between offers [e.g. 6 months] |
| `…pro.family.yearly.v2` | RM-C | Pay up front · 1 year at [YOUR PRICE] | Family Yearly · Retention · 1 year | `pro.family.yearly.v2.retention.upfront1y` | Minimum paid duration [e.g. 1 year] · wait between offers [e.g. 1 year] |

As an alternative for any plan, a free offer of [1 week / 1 month] can bridge the gap instead of a discount.

## Google Play Console: retention and win-back offers

Package `com.healthmd.android`. Android sells Individual plans only: weekly, yearly and Lifetime. There are no Family or monthly plans. Both subscriptions already have the `trial-7d` offer. The offers below mirror iOS: weekly gets 4 weeks pay-as-you-go and yearly gets 1 year up front.

| Product · base plan | Offer | Offer ID | Phases | Eligibility |
|---|---|---|---|---|
| `health_md_premium_weekly` · `weekly` (P1W) | Retention (Play cancel flow) | `retention-4w` | 4 × P1W discounted recurring at [YOUR PRICE]/week, then the base plan | Active paid subscriber with at least [e.g. 4 paid weeks]; once per [e.g. 6 months] |
| `health_md_premium_weekly` · `weekly` | Win-back | `winback-4w` | 4 × P1W at [YOUR PRICE]/week, then the base plan | Lapsed subscriber of this product, lapsed for [e.g. 2 weeks–12 months]; once per [e.g. 12 months] |
| `health_md_premium_yearly` · `yearly` (P1Y) | Retention (Play cancel flow) | `retention-1y` | 1 × P1Y at [YOUR PRICE], then the base plan | At least [e.g. 1 paid year, one renewal]; once per [e.g. 1 year] |
| `health_md_premium_yearly` · `yearly` | Win-back | `winback-1y` | 1 × P1Y at [YOUR PRICE], then the base plan | Lapsed subscriber of this product [e.g. within 12 months]; once per [e.g. 12 months] |
| `health_md_premium_lifetime` | none | — | One-time INAPP: nothing to cancel, no offers. The app shows "Lifetime · nothing to renew". | — |

Notes:

- Some cancel-flow retention offers are in Early Access. Confirm enrolment and the Console eligibility type before relying on them.
- **Plan Change is omitted.** Play shows Plan Change only when the same subscription has a lower-priced base plan. Each subscription has a single base plan, so no target exists today. Subscribers who aren't eligible for an offer go straight from Play's offer step to the cancellation survey. To enable Plan Change later, add a cheaper base plan to the same subscription at a price the owner approves. Weekly → Yearly is a different product with a higher single charge, so don't present it as a downgrade.
- **In-app offer card (board `RF_BeforeYouGoOffer`): Weekly → Yearly switch.** The app ships the card but shows it only when Play returns this offer, so nothing appears until it is created. Create on `health_md_premium_yearly` · base plan `yearly`:

  | Field | Value |
  |---|---|
  | Offer ID | `switch-yearly-1y` |
  | Eligibility | Developer determined |
  | Tags | `retention-in-app` |
  | Phases | 1 × P1Y single payment (finite, 1 cycle) at [YOUR PRICE], below the Yearly base price, then the base plan |

  The app hides the card unless the offer has exactly that shape in one currency (`selectYearlySwitchOffer`), and shows it only to an active, renewing Weekly subscriber. Prices come from `ProductDetails`. Taking it replaces Weekly with `WITH_TIME_PRORATION`: it starts now and Play credits the unused Weekly time. The card's button is outlined and smaller than the two sheet actions, so Continue to cancel stays one tap away and equally prominent. The paywall never shows this offer. A discount on the *same* plan (e.g. `inapp-keep-1y` for Yearly subscribers) still isn't possible in-app: Billing can't re-buy an owned product. That needs Google's in-app subscription management API (boards `RF_FutureSheet`, `RF_FutureApplied`), still "Coming soon".

## Placeholders to resolve

- `[YOUR PRICE]`: every offer and base-plan price, set per storefront or region.
- Eligibility durations shown as `[e.g. …]`.
- Translations for every shipped locale (both stores).
- Android subscriptions are active on Internal Testing. Production release with subscriptions is still pending.
- Deploy the myself.md endpoint (branch `feat/healthmd-play-subscription-status`) and confirm the service account can read `com.healthmd.android` subscriptions; until then Android shows no dates.
- Create `switch-yearly-1y` (above); until then Android shows no offer card.
