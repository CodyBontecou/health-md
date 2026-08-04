# Health.md Android simulator screenshots

- **Version:** 1.6.0 (26)
- **Emulator:** `capture_healthmd_api35`
- **Device profile:** Pixel 5, Android API 35
- **Resolution:** 1080 × 2340 PNG
- **Theme:** light
- **Full-resolution captures:** 88

Open [`index.html`](index.html) for the browsable gallery. The five `contact-sheet-*.jpg` files provide quick overviews.

## Coverage

| Area | Captures |
| --- | ---: |
| Onboarding | 8 |
| Export | 25 |
| Settings and customization | 24 |
| Schedule | 12 |
| History | 4 |
| Widgets | 10 |
| Global and system | 5 |


The set covers every static in-app route, bottom tab, onboarding page, settings subpage, visible dropdown/menu, primary dialog, widget setup page, and the principal Android system flows reachable from the app. Production-only UI such as release notes and the non-debug paywall was captured from the signed 1.6.0 release APK. Files containing `debug` are debug-only states; files containing `system` are Android-owned UI.

## External or dynamic states not included

- Google Play’s purchase confirmation sheet (the Google APIs AVD has no Play Store)
- email, browser, Discord, GitHub, Obsidian, and paired desktop-CLI destination UIs
- rare injected failures, a missed-schedule recovery prompt, and long-running transfer states that require synthetic fault/job setup

During capture, selecting the custom Markdown template exposed an Android-only regex crash. The working tree includes a portability fix plus an on-device regression test, and `54`–`56` show the repaired editor and preview.
