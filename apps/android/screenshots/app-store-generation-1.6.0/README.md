# Health.md Google Play screenshot generation kit

## Contents

- `source/`: eight ordered screenshots to attach to ChatGPT
- `alternates/08-raw-snapshot.png`: optional replacement for the Direct CLI image
- `PROMPT.md`: ready-to-paste generation prompt
- `generated/en-US/images/phoneScreenshots/`: save final 1080×1920 outputs here

The source files are curated copies. The complete simulator gallery remains unchanged at `../simulator-1.6.0-2026-08-04/`.

## Workflow

1. Attach all eight files from `source/` to ChatGPT.
2. Paste `PROMPT.md`.
3. Generate image 1, then say `NEXT` for each subsequent image.
4. Save the final images in filename order under `generated/en-US/images/phoneScreenshots/`.
5. Validate the generated directory before any Google Play upload.

Do not upload generated images without visually confirming that the embedded app UI remains accurate and readable.
