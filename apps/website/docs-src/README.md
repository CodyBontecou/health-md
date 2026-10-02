# Health.md documentation source ownership

The public documentation uses [Astro Starlight](https://starlight.astro.build/).
English routes live under `/docs/`; published translations live under `/<locale>/docs/`.
Run the commands below from `apps/website`, not `docs-src` or a former standalone checkout.

## Choose the owning source

| Surface | Edit / regenerate here | Publication output |
| --- | --- | --- |
| Authored user guides | [`src/content/docs/`](src/content/docs/); update matching locale guides together | Starlight pages and Markdown routes |
| Apple export/API/helper reference | [`apps/apple/docs/reference`](../../apple/docs/reference/); generated Apple examples use its [generation guide](../../apple/docs/reference/generation.md) | `src/content/docs/reference/`, `public/reference/generated/`, `reference-source.json` via `reference:sync` |
| Shared metric registry and native adapters | [`metric-registry-v1.json`](../../../packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json) and [`generate-registry-adapters.py`](../../../packages/healthmd-core-rust/scripts/generate-registry-adapters.py) | `src/content/docs/shared-metric-registry.md` and `public/reference/metric-registry-v1.json` |
| Portable MCP declarations | [CLI operation registry](../../cli/crates/healthmd-operations/src/registry.rs), then [MCP asset generator](../../cli/scripts/update-mcp-shared-assets.py) | CLI packaged catalog, then published `/agents/mcp/` assets via `agent-assets:sync` |
| Agent discovery/skills | [`agent-docs/`](agent-docs/), [repository skill sources](../../../.agents/skills/), and [`sync-agent-assets.mjs`](scripts/sync-agent-assets.mjs) | `public/docs/cli/`, `public/agents/`, reference provenance copies |
| Obsidian visualization assets and samples | Explicit pinned external checkout; follow the [website README](../README.md#external-obsidian-plugin-source) | Website bundles/sample wrappers and shipped Apple onboarding samples |

Generated publication files carry source/generator cues. Edit their owning source and run its
generator rather than treating a synchronized copy as an authored guide. Raw reference fixtures
are copied byte-for-byte; prose transformation does not change their schema or bytes.

## Authored guides and locales

English website-specific guides live in `src/content/docs/`. Translations mirror their filenames
under `src/content/docs/<locale>/`. The publication contract is
[`i18n/locales.mjs`](../i18n/locales.mjs); shared labels live in
[`i18n/docs-ui.mjs`](../i18n/docs-ui.mjs).

Every published locale translates each authored top-level guide. Generated contract/reference
pages remain canonical English with Starlight's localized fallback notice, English canonical URL,
and `noindex,follow`; they are excluded from hreflang and the sitemap. Localized guides link to
locale-prefixed fallback HTML, while generated-file URLs remain canonical.

Keep fenced commands/examples byte-identical to English, including comments. Translate surrounding
prose, not schema keys, metric IDs, fixture values, filenames, or generated artifacts. Regional unit
conversion is separate product work. Screenshots must use the configured locale paths or declared
English fallback in the locale contract linked above.

## Refresh Apple reference and agent publications

The canonical Apple source is the sibling `apps/apple` component. The sync script rewrites local
links, verifies fixtures/manifests, and records deterministic provenance and hashes. Production
builds verify the committed snapshot; they never fetch a newer app contract silently.

```bash
npm run reference:sync -- --source ../apple
npm run reference:check -- --source ../apple
npm run reference:verify
npm run agent-assets:sync
npm run agent-assets:check
```

For another checkout, supply `--source` or `HEALTHMD_APP_ROOT` pointing to its Apple component.
Paths to external checkouts are examples, not repository navigation targets.

## Local preflight

From the monorepo root, `make check-core-registry` validates generated registry outputs.
Then run from `apps/website`:

```bash
npm run docs:navigation
npm run i18n:check
npm run reference:check -- --source ../apple
npm run agent-assets:check
npm test
npm run docs:check
```

`docs:navigation` checks contributor links and literal navigation paths without building apps.
`docs:check` includes that check, verifies reference/agent snapshots, builds Starlight, stages
public assets, and checks built internal links. These checks are also wired into CI.

For development, use `npm run docs:install`, `npm run docs:dev`, and `npm run docs:preview`.
`npm run build` merges the docs output into the complete website and validates its routes/assets.
