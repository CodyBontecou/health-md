# health.md docs

The public English documentation and every locale published by `../i18n/locales.mjs` are built with [Astro Starlight](https://starlight.astro.build/), using `/docs/` for English and `/<locale>/docs/` for translated routes.

## Edit content

English website-specific feature guides live in `src/content/docs/`. Localized translations live in
`src/content/docs/<locale>/` with the same filenames. The custom content loader keeps English URLs
under `/docs/` and inserts the configured locale before the docs segment.

Each published locale translates every authored top-level user guide. Generated contract and
reference pages intentionally show Starlight's fallback notice while rendering canonical English
content. The custom head marks fallbacks `noindex,follow`, canonicalizes them to English, and
excludes them from hreflang and the sitemap. Localized guides link to locale-prefixed fallback HTML
routes but keep direct generated-file URLs canonical. Locale metadata and translated slug coverage are
authoritative in `../i18n/locales.mjs`; sidebar and shared documentation labels live in
`../i18n/docs-ui.mjs`.

The shared first-export onboarding capture and each locale's metric-selection and preview captures
are mapped in `../i18n/locales.mjs`. A translated guide must use those configured paths; the English
onboarding fallback must be declared explicitly. The authentic onboarding foreground and the shared
setup-required reference remain English in the current app; their translated captions say so.

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

`docs:check` verifies the committed reference snapshot, builds Starlight, stages docs-owned public assets under `/docs/`, and validates built internal links. The root build merges `docs-src/dist/` into the website `dist/` so English and all configured localized docs routes, `/_astro/`, Pagefind, and sitemap routes retain their generated paths alongside the landing page, blog, legal pages, and other static assets.
