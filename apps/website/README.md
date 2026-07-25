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

This component had no explicit license before the monorepo import. Do not assume the repository-root AGPL grant applies until the website's license is selected and documented in `LICENSES.md`.
