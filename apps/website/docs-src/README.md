# health.md docs

The public `/docs/` section is built with [Astro Starlight](https://starlight.astro.build/).

## Edit content

Markdown source lives in `src/content/docs/`.

The Data Reference page is generated from the app's Swift source of truth by:

```bash
python3 scripts/generate-data-reference.py
```

This runs automatically before `npm run build`.

## Commands

From `website/`:

```bash
npm run docs:dev
npm run docs:build
npm run docs:preview
```

`docs:build` writes the static site into `website/docs/` so the existing marketing landing page, blog, legal pages, and static hosting setup can stay unchanged.
