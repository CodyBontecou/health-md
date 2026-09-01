import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  docsRouteForSource,
  markdownPathForDocsPath,
} from '../docs-src/lib/docs-metadata.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPOSITORY_ROOT = path.resolve(ROOT, '../..');
const read = (relative) => readFile(path.join(ROOT, relative));
const sha256 = (buffer) => createHash('sha256').update(buffer).digest('hex');

test('Connect an agent guide is a complete released-Mac workflow', async () => {
  const guide = (await read('docs-src/src/content/docs/guides/connect-agent.md')).toString('utf8');
  for (const expected of [
    'https://apps.apple.com/us/app/health-md/id6757763969',
    'Health.md → Sync',
    '~/.codex/config.toml',
    'Claude Desktop or Claude Code',
    '"schema": "healthmd.local_readiness"',
    '"status": "ready"',
    'healthmd_refresh',
    'healthmd_metric_chart',
    'all_pages',
    'Verify completeness before answering',
    'healthmd_job_status',
    'healthmd_job_resume',
    'Never retry blindly',
  ]) assert.match(guide, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(guide, /does not accept an arbitrary destination argument/);
  assert.match(guide, /Do not run `healthmd direct pair`/);
  assert.doesNotMatch(guide, /"destination":/);
});

test('llms.txt is concise discovery metadata with stable authoritative links', async () => {
  const llms = (await read('llms.txt')).toString('utf8');
  assert.match(llms, /emerging convention, not a web standard/);
  assert.match(llms, /\/docs\/guides\/connect-agent\//);
  assert.match(llms, /\/docs\/reference\/source-manifest\.json/);
  assert.match(llms, /\/agents\/mcp\/mac-tools-v1\.json/);
  assert.match(llms, /\/agents\/skills\/healthmd-cli\/manifest\.json/);
  assert.doesNotMatch(llms, /llms-full/i);
  assert.ok(Buffer.byteLength(llms) < 4_000);
});

test('repository, CLI, and website docs publish selective agent-skill installation', async () => {
  const [readme, cliReadme, repositoryGuide, agents] = await Promise.all([
    readFile(path.join(REPOSITORY_ROOT, 'README.md')),
    readFile(path.join(REPOSITORY_ROOT, 'apps/cli/README.md')),
    readFile(path.join(REPOSITORY_ROOT, 'docs/agents/skills.md')),
    read('docs-src/src/content/docs/agents.md'),
  ]).then((buffers) => buffers.map((buffer) => buffer.toString('utf8')));
  for (const text of [readme, cliReadme, repositoryGuide, agents]) {
    assert.match(text, /https:\/\/skills\.sh\/CodyBontecou\/health-md\/healthmd-cli/);
    assert.match(text, /npx skills add CodyBontecou\/health-md@healthmd-cli/);
    assert.match(text, /does[^.\n]{0,20}not[^.\n]{0,20}install/i);
    for (const skill of ['healthmd-cli-operator', 'healthmd-cli-development', 'healthmd-cli-qa']) {
      assert.match(text, new RegExp(skill));
    }
  }
  for (const text of [cliReadme, repositoryGuide, agents]) {
    assert.match(text, /npx skills add CodyBontecou\/health-md --list/);
    assert.match(text, /npx skills update healthmd-cli --project --yes/);
  }
  assert.match(repositoryGuide, /npx skills add \. --skill healthmd-cli/);
  assert.match(repositoryGuide, /sync-agent-assets\.mjs --write/);
});

test('published agent assets are byte-exact and checksum-backed', async () => {
  const sourceProvenance = await read('docs-src/reference-source.json');
  assert.deepEqual(await read('docs-src/public/reference/source-manifest.json'), sourceProvenance);
  assert.deepEqual(await read('docs-src/public/reference/source-manifest-v1.json'), sourceProvenance);
  const provenance = JSON.parse(sourceProvenance);
  assert.equal(provenance.source_app_commit, null);
  assert.match(provenance.source_revision_strategy, /content-addressed/);
  assert.match(provenance.docs_reference_git_tree, /^[0-9a-f]{40}$/);

  const portableSource = await readFile(path.join(
    REPOSITORY_ROOT,
    'apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json',
  ));
  assert.deepEqual(await read('docs-src/public/agents/mcp/portable-tools-v1.json'), portableSource);

  const skillSource = await readFile(path.join(REPOSITORY_ROOT, '.agents/skills/healthmd-cli/SKILL.md'));
  const skillV1 = await read('docs-src/public/agents/skills/healthmd-cli/v1/SKILL.md');
  const skillV2 = await read('docs-src/public/agents/skills/healthmd-cli/v2/SKILL.md');
  const skillV3 = await read('docs-src/public/agents/skills/healthmd-cli/v3/SKILL.md');
  const skillV4 = await read('docs-src/public/agents/skills/healthmd-cli/v4/SKILL.md');
  const publishedSkill = await read('docs-src/public/agents/skills/healthmd-cli/v5/SKILL.md');
  assert.equal(skillV1.length, 15_734);
  assert.equal(sha256(skillV1), '6f36d8e479552745ae282a30a8471bc2ce477e7d1d6d8040f6ba72cd75047792');
  assert.equal(sha256(skillV2), '400468f3dd7ddb79e969bea6567db0d3d2b30d64430e0c4295d8e4e04012afd3');
  assert.equal(sha256(skillV3), '5e77d61461ce2806e3285b8e6794aeb272401db042b869036a45b88e2ed6612f');
  assert.equal(sha256(skillV4), '1d18de03c162e8ce343b6763986c18f206331371e1b90162d81219f04c99b095');
  assert.match(skillV2.toString('utf8'), /0\.1\.0-alpha\.2.*public preview/s);
  assert.deepEqual(publishedSkill, skillSource);
  assert.equal(sha256(publishedSkill), 'bb96f4f7416a1cf59b1229b9947be1eb407b790cce2cdd806b2bf054c1c17e04');
  const skillManifest = JSON.parse(await read('docs-src/public/agents/skills/healthmd-cli/manifest.json'));
  assert.equal(skillManifest.latest.version, 5);
  assert.equal(skillManifest.latest.path, '/agents/skills/healthmd-cli/v5/SKILL.md');
  assert.equal(skillManifest.latest.bytes, publishedSkill.length);
  assert.equal(skillManifest.latest.sha256, sha256(publishedSkill));
  assert.equal(skillManifest.versions.length, 5);
  assert.equal(skillManifest.versions[0].sha256, sha256(skillV1));
  assert.equal(skillManifest.versions[1].sha256, sha256(skillV2));
  assert.equal(skillManifest.versions[2].sha256, sha256(skillV3));
  assert.equal(skillManifest.versions[3].sha256, sha256(skillV4));
  assert.deepEqual(skillManifest.versions[4], skillManifest.latest);
  assert.equal(skillManifest.install_as, 'healthmd-cli/SKILL.md');
  assert.equal(skillManifest.availability, 'public_preview');
  const skillText = publishedSkill.toString('utf8');
  assert.match(skillText, /0\.1\.0-alpha\.3.*public preview/s);
  assert.match(skillText, /explicitly unqualified public preview/);
  assert.match(skillText, /schema-v8 `healthmd\.health_data`/);
  assert.match(skillText, /Android raw remains provider-native/);
  assert.match(skillText, /mcp serve-read-only/);
  assert.match(skillText, /local model inference/);
  assert.match(skillText, /brew install CodyBontecou\/tap\/healthmd/);
  assert.match(skillText, /git checkout healthmd-cli\/v0\.1\.0-alpha\.3/);

  const macTools = JSON.parse(await read('docs-src/public/agents/mcp/mac-tools-v1.json'));
  const portableTools = JSON.parse(portableSource);
  assert.equal(macTools.length, 21);
  assert.equal(portableTools.length, 19);
  assert.equal(new Set(macTools.map(({ name }) => name)).size, 21);
  assert.equal(new Set(portableTools.map(({ name }) => name)).size, 19);
});

test('CLI launch post uses runnable preview commands and honest privacy boundaries', async () => {
  const [post, cliReadme] = await Promise.all([
    readFile(path.join(ROOT, 'content/blog/healthmd-cli-direct-iphone-mcp.md')),
    readFile(path.join(REPOSITORY_ROOT, 'apps/cli/README.md')),
  ]).then((buffers) => buffers.map((buffer) => buffer.toString('utf8')));
  assert.match(post, /0\.1\.0-alpha\.3/);
  assert.match(post, /brew install CodyBontecou\/tap\/healthmd/);
  assert.match(post, /healthmd status --job JOB_UUID/);
  assert.match(post, /healthmd resume JOB_UUID/);
  assert.doesNotMatch(post, /healthmd setup claude/);
  assert.doesNotMatch(post, /never a dump of everything/);
  assert.match(post, /complete-corpus operation you explicitly request/);
  assert.match(post, /No Health\.md cloud/);
  assert.match(cliReadme, /0\.1\.0-alpha\.5` explicitly unqualified preview candidate/);
  assert.match(cliReadme, /After the exact GitHub prerelease and tap formula are public/);
});

test('localized agent docs preserve released-Mac and portable-preview boundaries', async () => {
  for (const locale of ['', 'es', 'de', 'fr', 'pt-br', 'it', 'nl', 'ja', 'ko', 'zh-hans']) {
    const prefix = locale ? `${locale}/` : '';
    const [agents, configuration, mcp, cli] = await Promise.all([
      read(`docs-src/src/content/docs/${prefix}agents.md`),
      read(`docs-src/src/content/docs/${prefix}configuration.md`),
      read(`docs-src/src/content/docs/${prefix}mcp.md`),
      read(`docs-src/src/content/docs/${prefix}cli.md`),
    ]).then((buffers) => buffers.map((buffer) => buffer.toString('utf8')));
    const combined = `${agents}\n${configuration}\n${mcp}\n${cli}`;
    assert.match(combined, /21/);
    assert.match(combined, /19/);
    assert.doesNotMatch(combined, /17(?:\s|-)*(?:tools|tool|herramient|werkzeug|outil|ferrament|strument|個|개|个)/iu);
    assert.match(agents, /https:\/\/skills\.sh\/CodyBontecou\/health-md\/healthmd-cli/);
    assert.match(agents, /npx skills add CodyBontecou\/health-md@healthmd-cli/);
    assert.match(agents, /healthmd-cli-operator/);
    assert.match(agents, /healthmd-cli-development/);
    assert.match(agents, /healthmd-cli-qa/);
    assert.match(mcp, /`tools\/list`/);
    assert.match(mcp, /"destination"\s*:\s*"\/absolute\/existing\/HealthVault"/);
    assert.doesNotMatch(cli, /iOS[^\n]{0,120}Windows|Windows[^\n]{0,120}iOS/iu);
  }
});

test('documentation routes have deterministic Markdown alternate paths', () => {
  assert.equal(docsRouteForSource('index.md'), '/docs/');
  assert.equal(docsRouteForSource('configuration.md'), '/docs/configuration/');
  assert.equal(docsRouteForSource('es/configuration.md'), '/es/docs/configuration/');
  assert.equal(docsRouteForSource('reference/generated/automation/index.md'), '/docs/reference/generated/automation/');
  assert.equal(markdownPathForDocsPath('/docs/'), '/docs/index.md');
  assert.equal(markdownPathForDocsPath('/docs/configuration/'), '/docs/configuration/index.md');
  assert.equal(markdownPathForDocsPath('/es/docs/configuration/'), '/es/docs/configuration/index.md');
});

test('docs metadata uses Git dates for HTML and sitemap freshness', async () => {
  const config = (await read('docs-src/astro.config.mjs')).toString('utf8');
  const head = (await read('docs-src/src/components/Head.astro')).toString('utf8');
  const middleware = (await read('docs-src/src/route-middleware.ts')).toString('utf8');
  const stage = (await read('docs-src/scripts/stage-public-paths.mjs')).toString('utf8');
  assert.match(config, /lastUpdated: true/);
  assert.match(config, /lastmod: lastModified/);
  assert.match(config, /routeMiddleware: '.\/src\/route-middleware\.ts'/);
  assert.match(middleware, /starlightRoute\.lastUpdated = lastModified/);
  assert.match(head, /dateModified/);
  assert.match(head, /entry\.data\.lastUpdated instanceof Date/);
  assert.match(head, /article:modified_time/);
  assert.match(head, /type="text\/markdown"/);
  assert.match(stage, /walkMarkdownSources/);
});

test('generated query fixtures distinguish typed partial coverage and structured errors', async () => {
  const error = JSON.parse(await read('docs-src/public/reference/generated/automation/agent-query-error.json'));
  assert.deepEqual(
    { schema: error.schema, version: error.schema_version, code: error.code, retryable: error.retryable },
    { schema: 'healthmd.query_error', version: 1, code: 'invalid_timeout', retryable: false },
  );
  assert.deepEqual(error.details, {});

  const partial = JSON.parse(await read('docs-src/public/reference/generated/automation/agent-query-response-partial.json'));
  assert.equal(partial.schema, 'healthmd.query_response');
  assert.equal(partial.schema_version, 1);
  assert.equal(partial.coverage.status, 'partial');
  assert.equal(partial.coverage.missing[0].status, 'failed');
  assert.ok(partial.items.length > 0);
  assert.ok(partial.limitations.length > 0);
  assert.equal(Object.hasOwn(partial, 'status'), false);
});
