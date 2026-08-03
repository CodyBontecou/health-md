# health.md docs

The public `/docs/` and `/es/docs/` sections are built with [Astro Starlight](https://starlight.astro.build/).

## Edit content

English website-specific feature guides live in `src/content/docs/`. Spanish translations live in
`src/content/docs/es/` with the same filenames. The custom content loader keeps English URLs under
`/docs/` and inserts the locale before the docs segment for Spanish (`/es/docs/`).

Only the Spanish first-success guides are translated today. Other `/es/docs/` routes intentionally
show Starlight's Spanish fallback notice while rendering English content; the custom head marks them
`noindex,follow`, canonicalizes them to English, and excludes them from the sitemap.

The complete Apple Health export reference is owned by the app repository at `../app/docs/reference/`. Do not hand-edit the synchronized files under:

- `src/content/docs/reference/`
- `public/reference/generated/`
- `reference-source.json`

Update that publication snapshot from the website repository root:

```bash
npm run reference:sync -- --source /absolute/path/to/health-md/app
npm run reference:check -- --source /absolute/path/to/health-md/app
npm run reference:verify
```

The sync script transforms reference prose into Starlight pages, copies all generated fixtures byte-for-byte, verifies JSON and generator manifests, rewrites local links, and records source provenance and SHA-256 hashes. Production builds run `reference:verify`; they never fetch or silently import a newer app contract.

## Commands

From `website/`:

```bash
npm run docs:install
npm run docs:dev
npm run docs:check
npm run docs:preview
npm run build
```

`docs:check` verifies the committed reference snapshot, builds Starlight, stages docs-owned public assets under `/docs/`, and validates built internal links. The root build merges `docs-src/dist/` into the website `dist/` so Astro's `/docs/`, `/es/docs/`, `/_astro/`, Pagefind, and sitemap routes retain their generated paths alongside the landing page, blog, legal pages, and other static assets.
