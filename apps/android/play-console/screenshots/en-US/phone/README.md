# English phone screenshots

These eight 1080×1920 RGB PNGs are the reviewed English Google Play sequence:

1. Core export
2. Export formats
3. Health metrics
4. Privacy and read-only access
5. Scheduled exports
6. File preview
7. Home-screen widgets
8. Direct desktop CLI

Filenames determine upload order. The images follow the matching copy in `play-store-screenshots/locales/en-US.json` and use `100+` rather than a brittle exact metric count in the marketing headline.

Validate them through the authored-to-canonical pipeline rather than passing this directory directly to `gplay`:

```bash
cd apps/android
./scripts/validate-play-listing.sh
```

Validation does not upload or publish anything.
