# Treg evaluation for Health.md

Investigated: 2026-10-19. Upstream source reviewed at [`50faed150f4810b16e9ba11ad487c854961917c1`](https://github.com/superdesigndev/treg/tree/50faed150f4810b16e9ba11ad487c854961917c1). This is an exploratory recommendation, not an adopted dependency or security qualification.

## Local trial (2026-10-19)

At the user's request, started Treg 0.26.0 from the pinned source revision above as a separate local service. No Health.md application dependency or upstream source modification was needed.

- Dashboard: `http://127.0.0.1:18790/app`, accessible on this Mac only.
- Source: `~/dev/treg-healthmd-local`.
- Runtime/state: `~/.local/share/healthmd-treg-local/` (private SQLite database, local keys, configuration, management script, log, and verification receipt).
- Uses upstream's single-user mode with a synthetic local identity: no hosted account, email, or GitHub sign-in.
- Explicitly bound to `127.0.0.1`, not upstream's default `0.0.0.0`. Do not tunnel or expose this no-login instance.
- Inherited environment cleared; private HOME; telemetry and ordinary answer archiving disabled. No provider keys, payment credentials, or Health.md credentials imported.

```bash
~/.local/share/healthmd-treg-local/control status
~/.local/share/healthmd-treg-local/control cli catalog search 'app store reviews'
~/.local/share/healthmd-treg-local/control stop
~/.local/share/healthmd-treg-local/control start
```

A subsequent user-requested agent setup added `~/.local/bin/treg`, project-only `.pi/mcp.json` for `treg-local`, and `.pi/skills/treg/SKILL.md`. Authentication is read from the private local configuration by a credential command, not embedded in project files. Pi's native MCP client connected successfully; five research tools are directly exposed and other operations are hidden. Pi's skill loader reported no diagnostics. Real public lookups passed through both the CLI and MCP. Run `/reload` to load the new MCP tools/skill into an already-running Pi session. Global agent settings and other clients' configurations were left unchanged.

Verified frontend typecheck/build, real-browser dashboard auto-login, local catalog search, loopback listener, 0600 key/config files, and token/tool persistence across restart. Registered one credential-free own tool scoped to Apple's public app-lookup endpoint; a real proxied lookup returned Health.md's App Store listing `6757763969`. Provider secrets remain zero. Non-secret evidence and operating instructions are in the runtime directory's `verification.json` and `README.md`.

**Actual spend: $0.** The approved ceiling remains $5; no paid-provider authority was configured. Self-hosting does not supply the hosted service's provider accounts or credit. The subsequent [Apple-only competitor review brief](../experiments/2026-10-19-apple-export-competitors.md) completed a free public-source pass: 97 review entries fetched, 78 retained, and $0 spent. Android reviews and paid SEO research remain unexecuted; paid-provider work would need separately approved credentials and budget controls.

The local checkout/runtime are intentionally retained for this trial (approximately 411 MiB). Removed the runtime's setup-only bootstrap installer and uv/npm caches, plus the checkout's `frontend/node_modules` (approximately 307 MiB reclaimed); verified restart and compiled dashboard assets afterward. This smoke test is not a full upstream test-suite run or security qualification. The earlier investigation-only limits below describe the initial source review, not this subsequently executed local trial.

## Initial recommendation

Trial the hosted service as an optional **public-data research tool** for Health.md: competitor reviews, website SEO, and public product discussions. Keep it outside the health-data path and outside authenticated Practice. Do not add a mobile/runtime dependency, upload repository credentials, or replace Health.md's CLI/MCP.

Start with one manually approved research brief, not a self-hosted deployment or an autonomous publishing agent.

## What Treg provides

Treg describes itself as “OpenRouter for Tools”: a catalog of external APIs, a credential-injecting HTTP gateway, a CLI, MCP, and shared skill bundles. Its hosted catalog can use Treg's provider accounts with prepaid per-call billing; a team's own credentials take precedence and are not metered by Treg. That does not waive the upstream provider's charges. Self-hosting the software does not itself supply Treg's hosted provider accounts. [1][2]

Its MCP interface uses discovery (`catalog_search`, `catalog_get`) followed by a generic `call`, rather than publishing thousands of individual tools. The team `/mcp/` surface also serves registered team tools and imported skills. The narrower `/mcp/v2/` connector surface is catalog-only, splits read/write calls by HTTP method, and is feature-flagged. Neither interface should be assumed to import an arbitrary existing stdio MCP server. [3]

The source package identifies itself as `tools-registry` version `0.26.0`, beta. The security policy calls the project pre-1.0 and recommends commit pinning for stability. [4][5]

## Useful applications

These are proposed workflows, not workflows executed during this investigation.

| Priority | Workflow | Health.md output | Boundary |
| --- | --- | --- | --- |
| First | Review Health.md and comparable apps on App Store / Google Play | Recurring export, setup, pricing, reliability, and documentation complaints; candidates for the backlog | Keep platform/storefront samples separate; omit reviewer identities and personal health disclosures |
| First | Research web keywords, SERPs, and competitor backlinks | Prioritized article and landing-page briefs for `apps/website`, e.g. Apple Health to CSV, Health Connect export, Obsidian health notes | Web search volume is not App Store keyword volume; preserve provider, locale, and measurement date |
| Next | Monitor public product discussions | A small, cited digest about export/automation needs | No individual health profiling, contact enrichment, unsolicited messages, or automatic replies |
| Later | Generate promotional concepts | Draft visuals or scripts using synthetic content | No real readings, account screenshots, testimonials, or medical claims; human review before publication |
| Optional | Find research publications | Source-linked documentation research | Discovery is not evidence appraisal, medical advice, or permission to send a person's health context |

The review, SEO, social, generation, and paper-discovery categories are documented in Treg's README and web-access skill; the specific API examples below were also visible in the live catalog. [1][6][7]

### Catalog spot-check

Only anonymous discovery/schema GETs were made. No provider tool was invoked. These are **catalog-listed prices on 2026-10-19**, not observed charges, throughput measurements, or guarantees of provider availability.

| Endpoint | Catalog-listed pricing | Source |
| --- | --- | --- |
| `litescrape.app_store.reviews` | $0.00015 per successful response | [App Store details](https://treg.to/catalog/endpoints/litescrape.app_store.reviews) |
| `litescrape.google_play.reviews` | $0.00015 per successful response | [Google Play details](https://treg.to/catalog/endpoints/litescrape.google_play.reviews) |
| `scrapecreators.reddit.search.posts` | $0.00188 per call | [Reddit details](https://treg.to/catalog/endpoints/scrapecreators.reddit.search.posts) |
| `treg.google.keywords.volume` | Routed children listed at $0.00179–$0.09; attempts can accumulate charges | [Keyword details](https://treg.to/catalog/endpoints/treg.google.keywords.volume) |
| `treg.web.backlinks.summary` | Routed children listed at $0.013334–$0.024; attempts can accumulate charges | [Backlink details](https://treg.to/catalog/endpoints/treg.web.backlinks.summary) |

Re-read the endpoint schema before each trial: inputs, pagination, locale, provider routes, and prices can change. A routed endpoint's lowest advertised price is not necessarily the final bill. Explicit vendor calls generally relay that vendor's shape; `treg.*` routed calls add a capability envelope. [1][2]

## Relationship to Health.md's existing agent tools

Health.md already publishes a [consumer skill](../../.agents/skills/healthmd-cli/SKILL.md) and [contributor skills](skills.md). Its [CLI/MCP](../../apps/cli/README.md#mcp-for-local-and-remote-clients) provides fixed, bounded health operations. The [remote MCP architecture](../../apps/cli/docs/remote-mcp.md) preserves a live, direct-backed source rather than a synchronized server-side health corpus.

Use separate execution contexts:

```text
Public-research session, without health credentials or artifacts
  -> Treg -> public store / web / SEO APIs
  -> reviewed, sanitized research brief

User-authorized health session
  -> local healthmd MCP -> encrypted direct channel -> foreground paired phone
```

Simply giving one agent both toolsets does not enforce this boundary: it could send returned health values as external API arguments. Keep the research session free of Health.md MCP tools, trust material, private exports, and authenticated account/Practice access. Local stdio also does not imply local model inference; the health session must still respect the MCP host/model provider's data handling.

Sharing a sanitized public Health.md skill through Treg is a possible team-library convenience, not a new health transport. Recipe-only bundles are supported, but imports can also collect companion files and infer API credentials. The existing GitHub/skills.sh distribution is simpler unless there is a concrete team-library need. [8]

The [cross-platform policy](../architecture/cross-platform-unification-policy.md) still applies to any resulting feature proposals: public reviews do not prove Apple/Android semantic equivalence. Android typed MCP queries must not be presented as available merely because Treg supports Android-store research.

## Risks and adoption gates

### Retention is not zero

The checked-in privacy page says that request/response bodies are not recorded, but its own retention table includes stored answers. The architecture explicitly documents an answer archive/cache, including eligible own-key catalog answers. Source models include stored request bodies and response snapshots. Treat the service as capable of retaining API content; do not rely on the shorter no-body-storage claim. [9][10][11]

`treg org archive off` opts a team out of new ordinary archive lookups/recording. It does not erase existing answers or remove audit records, idempotency replay storage, or async settlement evidence. Provider and hosting retention remain additional questions. No BAA, clinical qualification, or end-to-end zero-retention guarantee was established by this investigation. [2][10]

**Decision:** no user health data, phone pairing material, health artifacts, or authenticated Practice traffic. Practice is governed by a separate [clinical boundary](../../apps/practice/AGENTS.md); even authenticated identity/request metadata is inside that boundary.

### Credential and execution scope

For HTTP tools, Treg injects provider credentials server-side. Local CLI execution is different: credentials can be delivered to an isolated local runner, and the docs describe a best-effort fallback without that setup. The security policy also explicitly says server CLI runs do not yet have full filesystem/network isolation. Do not generalize “keys never leave the server” to every execution mode. [5][12]

`treg upload` can register discovered `.env` credentials, skills, and CLI profiles. Avoid bulk upload, broad OAuth grants, and shell/proxy interception in the pilot. If credentials are needed later, register only an explicitly approved, narrowly scoped non-health credential. [1][8]

The CLI documents PostHog usage telemetry on the hosted service, disabled with `TREG_TELEMETRY=0` or `DO_NOT_TRACK=1`. That opt-out is not an archive or server-log opt-out. [2]

### License is not ordinary Apache-2.0

The actual LICENSE adds restrictions on providing hosted, managed, or embedded services to third parties, including a component of a commercially distributed product, without prior written authorization. This is broader than the README's shorthand about a competing hosted registry. Internal team use/self-hosting is expressly permitted. The README and hosted terms separately allow calling the hosted API inside a product. [1][13][14]

**Decision:** do not vendor Treg code into Health.md's AGPL components or ship a customer-facing Treg-backed registry without license review and any necessary written permission. Internal use of the hosted API avoids that code-embedding question, not the privacy/security questions.

### Cost and reliability

Inspect prices before calls. Set `X-Treg-Route-Max-Cost` for each approved call; routed fallbacks may incur multiple vendor charges. Direct calls have no default per-call ceiling. Treg's integration guide says per-customer aggregate caps are advisory under concurrency, so they are not a substitute for a locally enforced total experiment budget. Hosted terms describe early access with no uptime/support commitment. [2][14][15]

## Suggested first experiment

**Question:** Which product/documentation gaps and search topics should Health.md prioritize?

1. Obtain approval for a separate research-only account/context and a **$5 maximum total spend**, with automatic top-up disabled. No existing production credentials are needed for the proposed catalog trial.
2. Use one public storefront/locale per platform. Identify Health.md and three comparable export apps with valid listings; do not invent cross-platform counterparts.
3. Fetch one bounded review page per listing first. Validate relevance and coverage before expanding. Preserve sample dates/counts and source links; report generalized product themes without reviewer identities or individual health details.
4. Check a small list of non-personal queries such as “Apple Health export CSV”, “Health Connect export”, and “Obsidian health data”. Inspect Health.md's and selected competitors' public backlink profiles.
5. Run serially with explicit per-call ceilings and cumulative accounting. Stop before estimated next-call cost exceeds the approved remaining budget; handle a refused or unavailable tool without silently switching to an uncapped route.
6. Produce one brief: five recurring product themes, five article/landing-page ideas, evidence links, sample limitations, provider trail, and total actual spend. Draft recommendations only; no code changes, publishing, account writes, or outreach.

Continue only if the brief reveals useful information beyond ordinary public browsing and our existing tools. Otherwise stop without introducing a dependency.

### Discovery commands after a separately approved installation/login

These inspect schemas and prices; they do not execute provider calls:

```bash
export TREG_TELEMETRY=0

treg catalog search "app store reviews"
treg catalog search "google play reviews"
treg catalog get litescrape.app_store.reviews
treg catalog get litescrape.google_play.reviews
treg catalog get treg.google.keywords.volume
treg catalog get treg.web.backlinks.summary
```

For a no-install preview, the public `https://treg.to/catalog/search?q=app+store+reviews` and endpoint-detail URLs above work without an account, as checked during this investigation. Do not run an installer, login, upload, or paid call merely to repeat this discovery.

## Verification and limits

Reviewed upstream README, license, security policy, CLI reference, architecture documents, selected source models/MCP code, and hosted catalog schemas. Compared these with Health.md's consumer skill, CLI/remote-MCP documentation, cross-platform policy, and Practice instructions.

No Treg installation, account creation, authentication, secret upload, paid/provider call, phone connection, clinical access, or runtime integration was performed. Provider execution quality, real charges, deletion behavior, production settings, and client-specific MCP compatibility remain unverified. No application code or public contract was changed.

## Sources

Upstream source links are pinned to the reviewed revision; live catalog links above are time-sensitive.

1. [README](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/README.md)
2. [CLI usage, routing, archive opt-out, and telemetry](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/USAGE.md)
3. [MCP/OAuth architecture](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/docs/context/architecture/mcp-oauth.md)
4. [Package metadata](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/pyproject.toml)
5. [Security policy and known limitations](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/SECURITY.md)
6. [Web-access skill](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/skills/web-access/SKILL.md)
7. [Live research-publication catalog search](https://treg.to/catalog/search?q=search+research+publications)
8. [Skill, environment, and CLI import behavior](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/docs/context/interface/env-import.md)
9. [Privacy-page source](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/src/treg/web/privacy.html)
10. [Archive architecture and opt-out limits](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/docs/context/architecture/archive.md)
11. [Storage models](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/src/treg/models.py)
12. [Local CLI execution and credential grants](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/docs/context/architecture/local-run.md)
13. [LICENSE, especially Additional Terms §1](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/LICENSE)
14. [Hosted terms source](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/src/treg/web/terms.html)
15. [Product integration and budget semantics](https://github.com/superdesigndev/treg/blob/50faed150f4810b16e9ba11ad487c854961917c1/src/treg/web/integrate.md)
