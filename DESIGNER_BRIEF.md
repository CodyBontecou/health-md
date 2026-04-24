# Health.md — Designer Brief

> A prompt for a designer tasked with redesigning Health.md. Read this end-to-end before sketching.

---

## 1. The 30-second pitch

**Health.md** is a privacy-first utility that exports Apple Health data into plain Markdown, JSON, or CSV files the user owns — no cloud, no servers, no account. It ships as a native **iOS app** with an optional **macOS companion** that syncs health data device-to-device over Bluetooth/Wi-Fi (Multipeer Connectivity).

The target user is a quantified-self / Obsidian-vault type: technical, privacy-minded, wants their health data as files on their disk, not locked inside an app.

- **Platforms:** iOS 17+, iPadOS 17+, macOS 14+ (SwiftUI, all native)
- **Business model:** 3 free exports, then one-time $4.99 unlock (no subscription)
- **Scale:** ~27,000 lines of Swift, 9 languages, currently shipping v1.8.2
- **Distribution:** App Store (iOS/iPadOS), direct download (macOS via isolated.tech)

---

## 2. What we want from you

Redesign the product end-to-end with these goals, in priority order:

1. **Keep the privacy-first soul.** Every screen should feel like it's telling the user "this is yours, nothing leaves your device." Don't dilute that for polish.
2. **Make 100+ health metrics feel manageable.** Today they're buried in nested toggle lists. Presets, smart defaults, and progressive disclosure are all on the table.
3. **Introduce visual data.** Today the app has no charts — it's all text. Users trust their Apple Health data; we should show it back to them in ways that reinforce "yes, we read this correctly" before they export.
4. **Unify iOS / iPadOS / macOS.** Same brand, same mental model, platform-native where it matters (menu bar on Mac, split view on iPad, bottom tab on iPhone). Today the three feel like cousins, not siblings.
5. **Surface hidden power features.** Daily-note injection, individual entry tracking, Obsidian Bases export, and scheduled syncs are buried in settings. Power users love them; new users never find them.

**Out of scope:** light mode (the app is deliberately dark-only), new business model, subscription pricing, web presence.

---

## 3. Users

### Primary: "The Vault Keeper"
- 25–45, tech-savvy knowledge worker
- Runs Obsidian, Logseq, or a personal wiki
- Tracks sleep, steps, heart rate, workouts; journals daily
- Actively avoids cloud-based health apps (MyFitnessPal, Oura cloud, etc.)
- Comfortable with folder paths, YAML, Markdown

### Secondary
- **Biohackers** — care about HRV, sleep stages, VO2 max, blood glucose
- **Privacy advocates** — local-first ideology, may self-host
- **Mac + iPhone ecosystem users** — want unified health view across devices

### Jobs-to-be-done
- "Get my health data out of Apple's silo and into files I control"
- "Have today's sleep and workout show up in my daily journal automatically"
- "Analyze my long-term trends in spreadsheets / Python / Obsidian Bases"
- "Back up my health data somewhere I trust"

---

## 4. Core flows to design

### iOS (primary surface)
1. **Onboarding** — 4 steps: welcome → HealthKit permission → pick destination folder → done
2. **Export** — pick date range + subfolder → confirm → progress → toast on success
3. **Schedule** — enable toggle, frequency (daily/weekly), time, next-run preview
4. **Sync to Mac** — toggle advertises iPhone over local network; shows connection status
5. **Settings** — vault location, metric selection (9 categories, 100+ metrics), format (Markdown / Obsidian Bases / JSON / CSV), individual-entry tracking, daily-note injection
6. **Paywall** — appears after 3rd free export; feature list + one-time unlock

### macOS (companion surface)
1. **Menu bar widget** — persistent; shows sync status, "Export Yesterday" quick action
2. **Sync view** — discover nearby iPhones, request data for a date range, cache locally
3. **Export view** — same engines as iOS, but reads from the local cache (Mac has no direct HealthKit access — this is the key macOS constraint)
4. **History** — list of past exports with retry for failures
5. **Settings** — same options as iOS, adapted to desktop idioms

### iPad
- Currently uses `NavigationSplitView` (sidebar + detail). Treat this as its own layout problem — not just a stretched iPhone.

---

## 5. Data to represent

The app reads 9 categories from HealthKit. Any of these metrics can be shown on-screen, exported, or graphed:

| Category | Representative metrics |
|---|---|
| Sleep | total, deep/REM/core/awake, stages over time |
| Activity | steps, active/basal calories, exercise minutes, distance |
| Heart | resting HR, walking HR, HRV, raw samples |
| Vitals | blood pressure, SpO₂, respiratory rate, temperature, glucose |
| Body | weight, BMI, body fat %, lean mass, waist |
| Nutrition | calories, macros, fiber, sodium, water, caffeine |
| Mindfulness | session count, State of Mind (valence + labels, iOS 18+) |
| Mobility | walking speed, step length, asymmetry, stair speed |
| Workouts | 50+ workout types with duration / calories / distance |

---

## 6. Current design system (keep, evolve, or replace — your call)

The codebase calls the current look **"Liquid Glass"**: frosted-glass surfaces, flat colors, a single purple accent, dark-only. Think Apple's modern system materials, not neon/gradient.

### Color (iOS)
- Background: `#141414` → `#1E1E1E` → `#262626` (three elevation tiers)
- Borders: `#2E2E2E` / `#3E3E3E` / `#4E4E4E` (three strengths)
- Text: `#E8E8E8` / `#A8A8A8` / `#6A6A6E` (primary / secondary / muted)
- Accent: `#9B6DD7` (iOS) / `#7A57A7` (macOS — slightly warmer)
- Semantic: success `#4A9B6D`, error `#C74545`, warning `#D4A958`
- **No gradients** anywhere except subtle specular highlights on iPad cards

### Typography
- System font only — no custom faces
- Respects Dynamic Type (non-negotiable, accessibility)
- Monospace system font is used for technical content (paths, values, the Mac brand wordmark)
- Uppercase small-caps labels with tracking `2.0` for section headers

### Surfaces
- Cards: `.ultraThinMaterial` + 15% white border + 20px continuous corner radius + soft shadow
- Primary button: 52px tall, 16px radius, accent @ 75% opacity, white text
- Secondary button: capsule, ultra-thin material, subtle border
- Bottom nav (iOS): floating capsule pill, 4 tabs, ultra-thin material

### Spacing
`6 / 12 / 20 / 32 / 48 / 64 / 96` — use these, don't invent in-between values

### Motion
`0.15s` quick, `0.2s` standard, `0.25s` smooth, spring for presses. No staggered or elaborate animation.

**You're free to propose a new direction** — but if you do, justify it against the privacy-first positioning. "Liquid Glass" was chosen because it feels like a utility, not a consumer app.

---

## 7. Voice & microcopy

Real examples from the app — match this tone:

- "Health.md reads your Apple Health data so it can export it to files you own. Nothing is uploaded or shared."
- "Pick a folder where your health data will be saved. This can be an Obsidian vault, iCloud Drive, or any folder on your device."
- "Note: Your iPhone must be unlocked for exports to work — iOS protects health data when locked."
- "One-time payment — no subscription."

**Characteristics:** direct, technical without being condescending, transparent about limitations, no marketing fluff, no emojis in copy, no exclamation marks. Mentions HealthKit / YAML / CSV by name — the audience knows what those are.

---

## 8. Hard constraints

- **Dark mode only** — every color must work on near-black. No light-mode version needed.
- **Accessibility is non-negotiable** — full VoiceOver labels, Dynamic Type scaling, WCAG AA contrast, no color-only indicators.
- **9 locales** — English, German, Japanese, Korean, Simplified Chinese, Spanish, French, Italian, Dutch, Brazilian Portuguese. Layouts must survive German (long) and Japanese (dense).
- **Platform idioms** — iOS bottom tabs, macOS menu bar + sidebar, iPad split view. Don't fight the OS.
- **macOS cannot read HealthKit directly.** The Mac is always dependent on an iPhone sync. Design around this; don't hide it.
- **Scheduled exports on iOS are imprecise** — iOS, not us, decides when they run. Copy and UI should set honest expectations (we already do this; don't break it).
- **No external dependencies are in use.** Any illustrations, icons, or custom components need to be producible in SwiftUI.

---

## 9. Opportunities (if you want to be ambitious)

These are known gaps where a designer could add real value:

1. **Data viz layer** — sparklines on daily exports, weekly/monthly summary cards, workout route visualizations. Currently zero charts.
2. **Metric selection redesign** — replace the 100-toggle list with presets ("Fitness," "Sleep," "Mental Health"), frequency-based suggestions, or a wizard.
3. **Mac menu bar popover** — today it's sparse. It could show today's steps, last night's sleep, sync status — a glanceable daily health summary.
4. **iPad as first-class** — multi-column grids, richer settings, keyboard shortcuts.
5. **Onboarding storytelling** — the 4 steps work but feel perfunctory. Illustrations or motion could explain the privacy model better than copy alone.
6. **Feature discovery** — daily-note injection and individual entry tracking are powerful but invisible. A "What's possible?" screen or inline nudges could help.

---

## 10. What to deliver

At minimum:
- **Flows** for iOS onboarding, export, schedule, sync, paywall, settings
- **Screens** for iPad and macOS equivalents
- **Component library** — buttons, cards, toggles, nav, status indicators, modals, form fields
- **Empty / loading / error / success states** for the main flows
- **Tokens** — colors, type scale, spacing, radii, shadows, motion curves (you can reuse or rework the current ones; either way, document them)
- **Interaction notes** — anything non-obvious in how a component should behave

Nice to have:
- A one-page "design principles" rationale so engineers know why when making micro-decisions later
- A short motion spec for any novel transitions
- Dark-mode asset exports for the app icon and any illustrations

---

## 11. Reference material inside this repo

- `README.md` — product positioning, user-facing feature list
- `Shared/Theme/` — current color, type, spacing, and component tokens
- `iOS/`, `iPad/`, `macOS/` — current per-platform screens
- `Shared/Models/` — the data shapes you'd be visualizing
- `Localizable.xcstrings` — all current microcopy, in all 9 languages

If anything in this brief contradicts what's in the code, the **code is the source of truth** for what exists today — but you're designing what comes next, so don't feel bound by it.
