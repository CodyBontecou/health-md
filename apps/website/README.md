# Health.md website

The Health.md product website, Astro documentation, blog, and generated visualization catalog live in this monorepo component.

## Development

Run commands from `apps/website`:

```bash
npm ci
npm --prefix docs-src ci
npm test
npm run build
```

`npm run dev` uses the component `Procfile` through Shoreman.

## Localization

English remains at the canonical root routes. Spanish uses `/es/` and `/es/docs/`.
On the first landing-page visit in a browser session, `/` redirects to `/es/` when Spanish
is the first supported browser language. Explicit locale URLs are never overridden, and a
visitor can remove `/es` to remain on the English root for that session. The shared locale
and route contract lives in `i18n/`, while the landing catalogs are `i18n/messages/en.json`
and `i18n/messages/es.json`.

```bash
npm run i18n:check
npm run build
```

The build renders the Spanish landing page from the current English `index.html`, so landing
changes must update both catalogs when visible copy changes. Spanish first-success guides live in
`docs-src/src/content/docs/es/`. Missing Spanish documentation renders the English source with a
Spanish notice, an English canonical URL, and `noindex,follow`; it is not added to the sitemap.
Do not translate commands, schema keys, metric IDs, filenames, JSON/CSV fixtures, or generated
reference artifacts.

Spanish legal pages under `es/` are convenience translations. The English legal pages remain the
controlling versions and are linked from each translation. A qualified human must review Spanish
legal and health terminology before these routes are deployed to production.

## External Obsidian plugin source

The Obsidian plugin remains in [`CodyBontecou/health-md-visualizations`](https://github.com/CodyBontecou/health-md-visualizations). CI checks out the revision recorded in `external-sources.json`.

Commands that regenerate plugin-backed visualization assets require an explicit checkout path:

```bash
HEALTHMD_OBSIDIAN_PLUGIN_REPO=/path/to/health-md-visualizations \
  npm run visualizations:sync
```

Update `external-sources.json` deliberately when adopting a new plugin revision, regenerate assets, and commit both changes together.

## Apple reference documentation

Apple reference sources are read directly from the sibling `apps/apple` component. Override discovery with `HEALTHMD_APP_ROOT` or `--source` when testing another checkout.

## Deployment

The Vercel project must use `apps/website` as its Root Directory. Its build command and output directory remain `npm run build` and `dist`, as configured in `vercel.json`.

## License

The website is available under the [MIT License](LICENSE). Other monorepo components have their own terms documented in [`LICENSES.md`](../../LICENSES.md).
