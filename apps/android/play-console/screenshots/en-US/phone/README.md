# English phone screenshots

These eight 1080×1920 RGB PNGs are the English Google Play sequence, "A Field Guide to Yourself":

1. You, as a text file.
2. Interrogate your own body.
3. The periodic table of you.
4. Your day, itemized.
5. Pin your sleep for closer study.
6. Your month, as a quilt.
7. Preserved on your own devices.
8. Your numbers, at a glance.

The 7-inch (1920×1200) and 10-inch (2560×1600) folders hold the matching five tablet plates.

Filenames determine upload order. Every Play locale has the same plates, rendered from the
"Health.md — Google Play" design canvas with that locale's copy; the copy lives in
`play-store-screenshots/locales/<locale>.json`.

Validate them through the authored-to-canonical pipeline rather than passing this directory directly to `gplay`:

```bash
cd apps/android
./scripts/validate-play-listing.sh
```

Validation does not upload or publish anything.
