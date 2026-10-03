import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const PAGES = [
  {
    dir: 'apple-health-export',
    url: 'https://healthmd.app/apple-health-export/',
    title: 'Export Apple Health Data — CSV, JSON, Markdown &amp; Obsidian | Health.md',
    h1: 'Export your Apple Health data — your way.',
    minFaqs: 5,
  },
  {
    dir: 'health-data-for-ai',
    url: 'https://healthmd.app/health-data-for-ai/',
    title: 'Use Apple Health with Claude, ChatGPT &amp; Codex | Health.md',
    h1: 'Put your health data to work with AI.',
    minFaqs: 4,
  },
  {
    dir: 'apple-health-to-csv',
    url: 'https://healthmd.app/apple-health-to-csv/',
    title: 'Export Apple Health to CSV — No Xcode, No Scripts | Health.md',
    h1: 'Apple Health to CSV, without the Xcode project.',
    minFaqs: 4,
  },
];

const sources = {};
for (const page of PAGES) {
  sources[page.dir] = await readFile(path.join(ROOT, page.dir, 'index.html'), 'utf8');
}
const index = await readFile(path.join(ROOT, 'index.html'), 'utf8');
const buildScript = await readFile(path.join(ROOT, 'scripts/build-site.mjs'), 'utf8');
const sitemap = await readFile(path.join(ROOT, 'sitemap.xml'), 'utf8');
const vercelTemplate = await readFile(path.join(ROOT, 'vercel.template.json'), 'utf8');

for (const page of PAGES) {
  const html = sources[page.dir];

  test(`${page.dir}: head metadata is exact and complete`, () => {
    assert.ok(html.includes(`<title>${page.title}</title>`), 'exact title');
    assert.ok(html.includes(`<link rel="canonical" href="${page.url}">`), 'canonical');
    assert.ok(html.includes(`<meta property="og:url" content="${page.url}">`), 'og:url');
    assert.ok(html.includes('<meta property="og:type" content="website">'), 'og:type');
    assert.ok(html.includes('<meta name="robots" content="index,follow">'), 'robots');
  });

  test(`${page.dir}: meta description is SEO-length (150-160 chars)`, () => {
    const match = html.match(/<meta name="description" content="([^"]+)">/);
    assert.ok(match, 'meta description exists');
    const length = match[1].length;
    assert.ok(
      length >= 150 && length <= 160,
      `meta description is ${length} chars, expected 150-160`,
    );
  });

  test(`${page.dir}: exactly one H1 with the approved headline`, () => {
    const h1s = html.match(/<h1\b[^>]*>/g) ?? [];
    assert.equal(h1s.length, 1, 'exactly one H1');
    assert.ok(html.includes(`>${page.h1}</h1>`), 'H1 headline matches');
  });

  test(`${page.dir}: JSON-LD FAQ questions all appear in visible content`, () => {
    const jsonLd = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
    assert.ok(jsonLd, 'JSON-LD block exists');
    const graph = JSON.parse(jsonLd[1])['@graph'];
    assert.ok(graph, 'JSON-LD @graph exists');
    const faq = graph.find((node) => node['@type'] === 'FAQPage');
    assert.ok(faq, 'FAQPage entity exists');
    const questions = faq.mainEntity.map((entity) => {
      assert.equal(entity['@type'], 'Question');
      return entity.name;
    });
    assert.ok(questions.length >= page.minFaqs, `at least ${page.minFaqs} FAQs, found ${questions.length}`);
    const body = html.replace(/<script type="application\/ld\+json">[\s\S]*?<\/script>/, '');
    for (const question of questions) {
      assert.ok(body.includes(question), `FAQ question visible: ${question}`);
    }
    assert.ok(graph.some((node) => node['@type'] === 'WebPage'), 'WebPage entity');
  });

  test(`${page.dir}: App Store CTA uses the exact badge markup`, () => {
    assert.ok(
      html.includes('class="hero-store-badge hero-store-badge-apple"'),
      'badge classes',
    );
    assert.ok(
      html.includes('href="https://apps.apple.com/us/app/health-md/id6757763969"'),
      'badge URL',
    );
    assert.ok(
      html.includes('/assets/store-badges/download-on-app-store.svg'),
      'badge image',
    );
  });
}

test('landing pages are copied into dist by the build script', () => {
  for (const page of PAGES) {
    assert.ok(buildScript.includes(`'${page.dir}'`), `${page.dir} in STATIC_DIRECTORIES`);
  }
});

test('landing pages are listed in sitemap.xml', () => {
  for (const page of PAGES) {
    assert.ok(sitemap.includes(`<loc>${page.url}</loc>`), `${page.url} in sitemap`);
  }
});

test('/mcp redirects to the AI landing page', () => {
  assert.ok(vercelTemplate.includes('{ "source": "/mcp"'), '/mcp redirect exists');
  // With trailingSlash:true Vercel normalizes /mcp -> /mcp/ before matching,
  // so the trailing-slash variant must be registered too (see legal redirects).
  assert.ok(vercelTemplate.includes('{ "source": "/mcp/"'), '/mcp/ redirect exists');
  assert.ok(vercelTemplate.includes('"destination": "/health-data-for-ai/"'), 'redirect target');
});

test('homepage footer links the landing pages', () => {
  for (const page of PAGES) {
    assert.ok(index.includes(`href="${page.dir}/"`), `footer link to ${page.dir}`);
  }
});
