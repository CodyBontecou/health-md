# Health.md Wear OS advertising assets

These portrait and square creatives extend the visual system used by the Android
Google Play phone screenshots: warm off-white, near-black Geist-like type, a
faceted purple gem, translucent lavender document paths, geometric facets, and
restrained device rendering.

## Deliverables

- `01-your-health-on-your-wrist.png` — 1080×1920 RGB PNG
- `02-your-day-one-glance.png` — 1080×1920 RGB PNG
- `square/01-your-health-on-your-wrist-square.png` — 1200×1200 RGB PNG
- `square/02-your-day-one-glance-square.png` — 1200×1200 RGB PNG

`alternates/01-dashboard-fidelity-pass.png` retains the screen-only iteration for
comparison; the primary first image has the cleaner display crop.

## Copy

1. **Your health. On your wrist.**
   See your latest synced metrics at a glance.
2. **Your day. One glance.**
   Steps and exercise in a Wear OS Tile.

## Inputs

- Style/edit references:
  - `../../play-console/screenshots/en-US/phone/7-home-screen-widgets.png`
  - `../../play-console/screenshots/en-US/phone/5-scheduled-exports.png`
- Wear UI references:
  - `../../play-store/wear/previews/1-wear-app-dashboard-emulator-preview.png`
  - `../../play-store/wear/previews/2-wear-activity-tile-emulator-preview.png`

## Generation

Generated with the built-in image-generation tool using the `ads-marketing` use
case. The first prompt replaced the phone in the campaign reference with a black
round Wear OS watch, retained the campaign background and gem, inserted the real
dashboard reference, and rendered the exact first copy block. A focused
`compositing` pass then corrected only the watch display. The second prompt applied
the same treatment to the system-rendered Daily Activity Tile and rendered the
exact second copy block.

The generated 9:16 RGB sources were normalized non-destructively to the campaign's
1080×1920 delivery size. Square recompositions were generated from those portrait
deliverables and normalized to 1200×1200 for upload fields requiring a 1:1 aspect
ratio. These are promotional renders, not raw Wear OS Play-listing screenshots or
release evidence. Review copy and rendered UI visually before a paid campaign is
launched.
