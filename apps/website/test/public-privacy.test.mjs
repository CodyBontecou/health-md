import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { marked } from 'marked';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { defaultLocale, publishedLocales } from '../i18n/locales.mjs';
import { routePath } from '../i18n/routes.mjs';
import { buildBlog } from '../scripts/build-blog.mjs';
import { buildLocalizedLanding, loadCatalog, renderLanding } from '../scripts/build-localized-pages.mjs';
import { buildLocalizedLegalPages, renderLegalPage } from '../scripts/build-localized-legal-pages.mjs';
import { renderLocalizedSitemap } from '../scripts/build-localized-sitemap.mjs';
import {
  assertPilotBoundaries,
  assertPublicPrivacyCopy,
  checkBuiltPublicPrivacy,
  publicPrivacyPages,
} from '../scripts/check-public-privacy.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (file) => readFile(path.join(ROOT, file), 'utf8');
const source = await read('index.html');
const english = await loadCatalog(defaultLocale);

for (const file of publicPrivacyPages) {
  test(`${file}: default/local privacy and optional retained-export pilot are consistent, including FAQs`, async () => {
    const html = await read(file);
    assertPublicPrivacyCopy(html, file);
    assertPilotBoundaries(html, defaultLocale, file);
    assert.match(html, /by default/i);
    assert.match(html, /optional/i);
    assert.match(html, /href="\/privacy-policy\.html(?:#retention)?"/);
  });
}

for (const { code, path: localePath } of publishedLocales('landing')) {
  test(`${code}: landing and both authored guides disclose the single-owner pilot in the reader's language`, async () => {
    const catalog = await loadCatalog(code);
    const html = renderLanding(source, code, english, catalog);
    assertPublicPrivacyCopy(html, code);
    assertPilotBoundaries(html, code, `landing/${code}`, { deviceSync: false });
    for (const file of ['android.md', 'guides/platform-features.md']) {
      const guide = await read(path.join('docs-src/src/content/docs', localePath, file));
      assertPublicPrivacyCopy(guide, `${code}/${file}`);
      assertPilotBoundaries(guide, code, `${code}/${file}`);
      assert.match(guide, /\]\(\/privacy-policy\.html\)/);
    }
  });
}

test('local blog workflows and canonical CLI agent index do not deny the optional cloud pilot', async () => {
  for (const file of [
    'content/blog/export-apple-health-data-to-obsidian.md',
    'content/blog/local-first-health-data-architecture.md',
    'docs-src/agent-docs/cli-llms.txt',
  ]) {
    const copy = await read(file);
    assertPublicPrivacyCopy(copy, file);
    assertPilotBoundaries(copy, defaultLocale, file);
  }
});

test('privacy policy keeps the pilot retention, deletion, failure, AI-provider, and analytics boundaries', async () => {
  const privacy = renderLegalPage(await read('privacy-policy.html'), 'privacy', defaultLocale);
  assertPublicPrivacyCopy(privacy, 'privacy');
  assert.match(privacy, /No cloud copy is created by default/);
  assert.match(privacy, /original API-export JSON envelopes[\s\S]*historical revisions[\s\S]*embedded source data/);
  assert.match(privacy, /read-only MCP endpoint[\s\S]*provider may retain or use the results under its own policies/);
  assert.match(privacy, /without an age cutoff[\s\S]*storage quota/);
  assert.match(privacy, /unbacked VM[\s\S]*permanently destroy exports/);
  assert.match(privacy, /Account deletion disables access immediately[\s\S]*completion is not instantaneous/);
  assert.match(privacy, /no off-host backup or account recovery[\s\S]*not an independently audited or generally available service/);
  assert.match(privacy, /No public signup or automatic device sync exists/);
  assert.match(privacy, /health records and exported content cannot be represented in an analytics payload/);
  const description = privacy.match(/<meta name="description" content="([^"]+)"/)[1];
  assert.match(description, /optional single-owner cloud pilot/i);
});

test('generated source sitemap is deterministic and dates track the revised disclosures', async () => {
  const sitemap = await read('sitemap.xml');
  assert.equal(renderLocalizedSitemap(sitemap), sitemap, 'Regenerate with npm run i18n:sitemap');
  const entries = new Map([...sitemap.matchAll(/<url>([\s\S]*?)<\/url>/g)].map(([, entry]) => [
    entry.match(/<loc>([^<]+)<\/loc>/)[1], entry.match(/<lastmod>([^<]+)<\/lastmod>/)?.[1],
  ]));
  for (const { code } of publishedLocales('landing')) {
    assert.equal(entries.get(`https://healthmd.app${routePath('home', code)}`), '2026-10-04');
  }
  for (const [route, file] of [['privacy', 'privacy-policy.html'], ['terms', 'terms-of-service.html']]) {
    const html = await read(file);
    const visibleDate = html.match(/Last updated: ([^<]+)</)[1];
    const date = new Date(`${visibleDate} UTC`).toISOString().slice(0, 10);
    assert.equal(entries.get(`https://healthmd.app${routePath(route, defaultLocale)}`), date);
  }
  for (const file of publicPrivacyPages) {
    assert.equal(entries.get(`https://healthmd.app/${file.replace(/index\.html$/, '')}`), '2026-10-04');
  }
});

test('guard rejects each prior blanket promise in body, metadata, and JSON-LD separately', () => {
  for (const promise of [
    'Health.md never stores your health data.',
    'Health.md does not keep a server-side health corpus.',
    'Health.md does not store your health data.',
    'There is no Health.md health-data cloud.',
    'There is no Health.md health-data cloud in the loop.',
    'Health.md keeps no health-data cloud.',
    'Health.md cloud copies None',
    'Health.md does not provide a health-data cloud.',
    'There is no Health.md cloud account for your health archive.',
    'Health.md betreibt keine Cloud für Gesundheitsdaten.',
    'Health.md no opera una nube de datos de salud.',
    'Health.md n’exploite pas de cloud pour les données de santé.',
    'Health.md n’exploite aucun cloud de données de santé.',
    'Health.md non gestisce alcun cloud di dati sanitari.',
    'Health.md beheert geen cloud voor gezondheidsgegevens.',
    'O Health.md não opera uma nuvem de dados de saúde.',
    'Health.mdはヘルスデータ用クラウドを運用していません。',
    'Health.md는 건강 데이터 클라우드를 운영하지 않습니다.',
    'Health.md 不运营任何健康数据云端。',
    '✓ no Health.md health-data cloud',
    '✓ keine Health.md-Cloud für Gesundheitsdaten',
    '✓ sin nube de datos de salud de Health.md',
    '✓ aucun cloud de données de santé Health.md',
    '✓ nessun cloud di dati sanitari di Health.md',
    '✓ geen Health.md-cloud voor gezondheidsgegevens',
    '✓ sem nuvem de dados de saúde do Health.md',
    '✓ Health.mdのヘルスデータクラウドなし',
    '✓ Health.md 건강 데이터 클라우드 없음',
    '✓ 无 Health.md 健康数据云端',
  ]) {
    for (const html of [
      `<p>${promise}</p>`,
      `<meta name="description" content="${promise}">`,
      `<script type="application/ld+json">${JSON.stringify({ '@type': 'WebPage', description: promise })}</script>`,
    ]) assert.throws(() => assertPublicPrivacyCopy(html, 'regression'), /unqualified no-cloud promise/);
  }
  assert.doesNotThrow(() => assertPublicPrivacyCopy('<p>Health.md does not store your health data by default. Direct CLI requests do not use a Health.md health-data cloud. There is no Health.md health-data cloud hop or account in this direct workflow.</p>', 'local scope'));
});

test('built guard independently verifies translated Markdown and rendered blog disclosures', async () => {
  const output = await mkdtemp(path.join(os.tmpdir(), 'healthmd-public-privacy-'));
  const stage = async (file, content) => {
    await mkdir(path.dirname(path.join(output, file)), { recursive: true });
    await writeFile(path.join(output, file), content);
  };
  try {
    await buildLocalizedLegalPages(output);
    await buildBlog({ outputRoot: output });
    for (const file of publicPrivacyPages) await stage(file, await read(file));
    await stage('docs/cli/llms.txt', await read('docs-src/agent-docs/cli-llms.txt'));
    for (const { code, path: localePath } of publishedLocales('landing')) {
      await buildLocalizedLanding({ outputRoot: output, locale: code });
      for (const slug of ['android', 'guides/platform-features']) {
        const markdown = await read(path.join('docs-src/src/content/docs', localePath, `${slug}.md`));
        await stage(path.join(localePath, 'docs', slug, 'index.md'), markdown);
        await stage(path.join(localePath, 'docs', slug, 'index.html'), marked.parse(markdown));
      }
    }
    await checkBuiltPublicPrivacy(output);
    const file = 'de/docs/android/index.md';
    const markdown = await readFile(path.join(output, file), 'utf8');
    await stage(file, markdown.replace('nur für einen Eigentümer', 'für alle Benutzer'));
    await assert.rejects(checkBuiltPublicPrivacy(output), /index\.md: missing localized pilot boundary/);
    await stage(file, markdown);
    const blog = 'blog/local-first-health-data-architecture/index.html';
    const html = await readFile(path.join(output, blog), 'utf8');
    await stage(blog, html.replace('optional single-owner', 'optional multi-user'));
    await assert.rejects(checkBuiltPublicPrivacy(output), /index\.html: missing localized pilot boundary/);
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});

test('guard rejects JSON-LD/visible answer divergence even when both mention the pilot', () => {
  const html = `<h3>Cloud?</h3><p>Only intentional uploads.</p><script type="application/ld+json">${JSON.stringify({
    '@type': 'FAQPage', mainEntity: [{ name: 'Cloud?', acceptedAnswer: { text: 'Pilot uploads are stored forever.' } }],
  })}</script>`;
  assert.throws(() => assertPublicPrivacyCopy(html, 'FAQ regression'), /visible and JSON-LD answers differ/);
});
