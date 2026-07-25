# health.md docs

The public `/docs/` section is built with [Astro Starlight](https://starlight.astro.build/).

## Edit content

Website-specific feature guides live in `src/content/docs/`.

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

`docs:check` verifies the committed reference snapshot, builds Starlight, and validates built internal links. The root build copies `docs-src/dist/` into `dist/docs/` alongside the landing page, blog, legal pages, and other static assets.
