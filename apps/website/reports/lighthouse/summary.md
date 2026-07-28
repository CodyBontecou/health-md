# Lighthouse audit: https://healthmd.app/

Run date: 2026-06-26 01:25–01:26 UTC
Tool: `lighthouse@latest` via Chrome headless
Reports:
- `reports/lighthouse/healthmd-desktop.json`
- `reports/lighthouse/healthmd-mobile.json`

## Scores

| Form factor | Performance | Accessibility | Best Practices | SEO | Agentic Browsing |
| --- | ---: | ---: | ---: | ---: | ---: |
| Desktop | 99 | 100 | 100 | 100 | 100 |
| Mobile | 99 | 100 | 100 | 100 | 100 |

## Core Web Vitals / key metrics

| Metric | Desktop | Mobile |
| --- | ---: | ---: |
| First Contentful Paint | 0.6 s | 1.1 s |
| Largest Contentful Paint | 0.7 s | 2.0 s |
| Total Blocking Time | 0 ms | 10 ms |
| Cumulative Layout Shift | 0.052 | 0.002 |
| Speed Index | 1.2 s | 1.5 s |
| Time to Interactive | 0.7 s | 2.8 s |

## Main findings

1. **Desktop payload is large because three below-the-fold PNG screenshots are ~8.8 MB combined.**
   - `assets/screenshots/latest/iphone-export.png`
   - `assets/screenshots/latest/iphone-metrics.png`
   - `assets/screenshots/latest/iphone-schedule.png`
   - Referenced in `index.html:2358`, `index.html:2362`, `index.html:2366`.
   - Lighthouse estimates ~8,806 KiB savings if using resized/modern responsive images.

2. **Visualization bundle has unused/unminified JavaScript.**
   - `assets/healthmd-plugin-visualizations.js`
   - Referenced in `index.html:44`.
   - Estimated savings: ~110 KiB unused JS, ~60 KiB minification.

3. **Small render-blocking CSS file.**
   - `assets/theme-icons.css`, referenced in `index.html:2050`.
   - Low impact, but can inline/minimize or load non-critical.

4. **Minor label/name mismatch on desktop.**
   - Brand link visible label does not match `aria-label="Health.md Home"` at `index.html:2055`.
   - Theme toggle visible text `Auto` did not match accessible name in the desktop run.

5. **Cache lifetime notes are from Cloudflare scripts.**
   - `static.cloudflareinsights.com/beacon.min.js`
   - `cdn-cgi/scripts/.../email-decode.min.js`
   - Low priority / mostly provider-controlled.

## Recommended next actions

1. Replace the three `latest/*.png` iPhone screenshots with optimized WebP/AVIF responsive versions or existing optimized assets.
2. Minify/tree-shake `assets/healthmd-plugin-visualizations.js`; consider loading it only on pages/sections that need visualizations.
3. Fix the accessible-name warnings by aligning visible labels with aria labels.
4. Optionally inline/minify `theme-icons.css`.

## After local image optimization

Implemented in `index.html` and `assets/screenshots/optimized/`:

- Added responsive WebP variants at 220w/420w/640w for:
  - `iphone-export`
  - `iphone-metrics`
  - `iphone-schedule`
- Added a 220w WebP variant for the hero `iphone-preview`.
- Replaced oversized PNG references with `<picture>`/`srcset` so browsers choose the smallest appropriate asset.

Local static verification reports:
- `reports/lighthouse/healthmd-local-desktop-after-image-optimization-final.json`
- `reports/lighthouse/healthmd-local-mobile-after-image-optimization-final.json`

Local desktop image-delivery audit now passes. Total local desktop byte weight dropped from the hosted baseline's ~9,182 KiB to ~960 KiB. Hosted production should be re-audited after deployment.
