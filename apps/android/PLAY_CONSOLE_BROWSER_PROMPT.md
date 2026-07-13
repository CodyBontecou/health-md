# Google Play Console Setup Prompt

Use this prompt verbatim when working with Claude in the browser at https://play.google.com/console

---

## PROMPT

You are helping me set up a Google Play Store listing for my Android app. I'll guide you through each section of the Play Console. Here is everything you need to know about the app — use this as the source of truth for every form field, text box, and decision.

---

### APP IDENTITY

- **App name**: Health.md
- **Package name**: com.healthmd.android
- **Version**: 1.0.0 (versionCode 1)
- **Default language**: English (United States) — en-US

---

### STORE LISTING — MAIN DETAILS

**App name (max 50 chars):**
```
Health.md – Health Data Export
```

**Short description (max 80 chars):**
```
Export 60+ health metrics locally to Markdown, Obsidian, JSON & CSV.
```

**Full description (max 4000 chars):**
```
Health.md is the only app that exports your Health Connect data directly to your device as local files — no cloud, no subscription, no lock-in.

EXPORT YOUR HEALTH DATA, YOUR WAY
Choose from Markdown, Obsidian Bases, JSON, or CSV. Every export lands in a folder you pick on your own device. Your data never leaves your phone unless you choose to move it.

TRACK 60+ HEALTH METRICS
Sleep, heart rate, steps, active calories, blood pressure, blood glucose, body fat, weight, oxygen saturation, respiratory rate, HRV, nutrition, hydration, floors climbed, workouts, and much more — all categories from Health Connect in one place.

AUTOMATE DAILY EXPORTS
Set a schedule and forget it. Health.md runs exports automatically in the background — every 15 minutes, hourly, daily, or on your own cadence. Check the History screen to see every successful run with timestamps.

SEAMLESS OBSIDIAN INTEGRATION
Export directly to your Obsidian vault. Use Obsidian Bases format to build your own health dashboard, link health data to daily notes, or run your own analysis. The only health-to-Obsidian pipeline on Android.

OWN YOUR DATA, FULLY
No account required. No server. No analytics. Health.md reads from Health Connect and writes files to your device — that's it. You control what's exported, which metrics are included, and exactly where files land.

HIGHLY CONFIGURABLE
- Enable or disable any of the 60+ individual metrics
- Choose write mode: Overwrite, Append, or Update
- Organize exports into category subfolders
- Set custom date ranges or export everything at once
- Pick your folder with the system file picker

FREEMIUM — TRY BEFORE YOU BUY
Get 3 free exports to test every feature. Unlock unlimited exports and automated scheduling with a single one-time payment. No subscription, ever.

WHAT USERS SAY
★★★★★ "Extremely fast export, high polished design"
★★★★★ "Works great, I needed a solution to export my health file to markdown locally"
★★★★★ "For anybody who uses Obsidian and collects/tracks health data this is indispensable. Other apps export Health data but not in markdown to Obsidian."

PRIVACY
Health.md reads Health Connect data solely to create exports the user requests. Device Folder exports are written to local or provider-backed storage. If the user explicitly configures and selects API Endpoint, selected JSON records are sent directly over HTTPS to that service; Health.md does not proxy or store the request. Your privacy policy URL must be set in the Play Console — use: https://healthmd.isolated.tech/privacy-policy.html
```

---

### STORE LISTING — CATEGORIZATION

- **App category**: Health & Fitness
- **Tags / keywords** (use all that apply): health data, health export, Obsidian, markdown, Health Connect, fitness tracker, data privacy, self-quantified, health metrics, CSV export
- **Content rating**: Everyone (no mature content, no violence, no user-generated content)

---

### PRICING & DISTRIBUTION

- **Paid or Free**: Free (with in-app purchase)
- **In-app product**: `health_md_premium_lifetime` — One-time purchase, $9.99 USD
  - Title: Unlock Health.md
  - Description: Unlimited exports, automated scheduling, and all future features. One-time payment — no subscription.
- **Countries**: All countries where Google Play is available
- **Contains ads**: No

---

### IN-APP PRODUCTS SETUP

When you reach the "Monetize > Products > In-app products" section, create one product:

| Field | Value |
|---|---|
| Product ID | `health_md_premium_lifetime` |
| Name | Unlock Health.md |
| Description | Unlimited exports and automated scheduling — one-time payment, no subscription. |
| Price | $9.99 USD |
| Type | One-time (not subscription) |
| Status | Active |

---

### CONTENT RATING QUESTIONNAIRE

Answer all questions as follows:
- Violence: No
- Sexual content: No
- Profanity: No
- Controlled substances: No
- User-generated content: No
- Social features: No
- Location sharing: No
- **Health or medical**: **Yes** — reads health data from Health Connect
- Data collection: reads health data locally from Health Connect, nothing transmitted externally
- **Target age group**: 18+ (adults — self-quantifiers, Obsidian users, health enthusiasts)

---

### APP CONTENT — DATA SAFETY

Fill out the Data Safety section as follows:

**Does your app collect or share any of the required user data types?**
- **Yes** — the app accesses Health and Fitness data

**Data collected:**
| Data type | Collected | Shared | Processed ephemerally | Required |
|---|---|---|---|---|
| Health and fitness (Health Connect) | Yes | No | No | Yes |
| Files and docs (local file write) | Yes | No | No | Yes |

**Is the data encrypted in transit?** Yes — optional API Endpoint exports require HTTPS. Folder exports use the selected Android document provider’s transport behavior.

**Can users request data deletion?** Yes — users can delete exported files from their device at any time.

**Does your app use Health Connect?** Yes — check this box and provide the Health Connect permission rationale:
> Health.md reads health metrics (steps, heart rate, sleep, calories, blood pressure, blood glucose, weight, and 55+ more) from Health Connect to create user-requested exports. Exports stay in user-selected storage unless the user explicitly selects API Endpoint, which sends selected JSON records directly to the HTTPS service they configure.

---

### HEALTH CONNECT PERMISSIONS DECLARATION

In the "App content > Health Connect permissions" section, list every permission the app uses:

```
READ_STEPS, READ_HEART_RATE, READ_SLEEP, READ_EXERCISE, READ_DISTANCE,
READ_ACTIVE_CALORIES_BURNED, READ_TOTAL_CALORIES_BURNED,
READ_BASAL_METABOLIC_RATE, READ_BLOOD_PRESSURE, READ_BLOOD_GLUCOSE,
READ_BODY_FAT, READ_BODY_TEMPERATURE, READ_HEIGHT, READ_WEIGHT,
READ_OXYGEN_SATURATION, READ_RESPIRATORY_RATE,
READ_HEART_RATE_VARIABILITY, READ_NUTRITION, READ_HYDRATION,
READ_FLOORS_CLIMBED
```

**Rationale for each permission group:**
> Health.md reads these metrics only when creating an export requested by the user. The user chooses which metrics to include and whether to write them to selected storage or send JSON directly to an HTTPS endpoint they explicitly configure. Health.md does not proxy or store API Endpoint requests.

---

### SCREENSHOTS

All 5 screenshots are ready at **1290×2796px** (portrait phone) in:
`play-console/screenshots/en-US/phone/`

Upload them in this order:

1. `1.png` — **Export Health Data Locally** (Export dialog with format options)
2. `2.png` — **Own Your Health Data** (Settings / configure your app)
3. `3.png` — **Track 60+ Health Metrics** (Health metrics selection, 61/61)
4. `4.png` — **Automate Daily Exports** (Schedule screen, SCHEDULE ACTIVE)
5. `5.png` — **Sync to Obsidian Seamlessly** (Export settings, Obsidian Bases format)

**Feature graphic**: 1024×500px — not yet generated; skip this field for now.
**App icon**: 512×512px PNG is ready at `play-console/graphics/en-US/icon.png`.

---

### RELEASE TRACK

For the **first upload**, target the **Internal Testing** track:
- Upload the AAB from: `app/build/outputs/bundle/release/app-release.aab`
- Release name: `1.0.0 – Initial Release`
- Release notes (What's New):
```
Initial release of Health.md

• Export 60+ health metrics from Health Connect to local files
• Markdown, Obsidian Bases, JSON, and CSV export formats
• Automated scheduled exports (run every 15 min to daily)
• Choose any folder on your device as the export destination
• Full metric selection — enable or disable any of 61 health metrics
• Beautiful dark UI with purple accent
```

---

### THINGS TO WATCH FOR AS YOU NAVIGATE

1. **Privacy policy URL** — Play Console will ask for this. The developer needs to host one. URL: `https://healthmd.isolated.tech/privacy-policy.html`

2. **Health Connect opt-in** — The manifest already contains `<meta-data android:name="android.health.connect.DATA_TYPES_USED" ...>`. Play Console may still ask you to confirm Health Connect usage in the App Content section — answer Yes.

3. **Target API level** — The app targets SDK 35 (Android 15), which satisfies Google Play's current requirements.

4. **App signing** — Google Play handles signing for AAB uploads. The app is built with release signing locally, but Google will re-sign with Play App Signing. Enroll in Play App Signing when prompted.

5. **Rating questionnaire** — Complete the IARC content rating questionnaire when prompted. It's found under "Policy > App content > Content rating".

6. **Billing declaration** — Under "Policy > App content > Ads", confirm the app has no ads. Under monetization, confirm the in-app purchase type is a one-time purchase (not a subscription or consumable that repeats).

---

### ITERATION INSTRUCTIONS

Work through the Play Console left-nav in order:
1. Dashboard → Set up your app
2. Store presence → Main store listing (fill title, descriptions, screenshots, graphics)
3. Store presence → Store settings (category, tags, contact details)
4. Monetize → In-app products (create `health_md_premium_lifetime`)
5. Policy → App content (complete all sections: privacy policy, ads, content rating, data safety, Health Connect)
6. Release → Internal testing → Create release (upload AAB, set release notes)

After each section is saved, tell me what's done and what's still missing so we can track progress together.
