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

function textContent(html) {
  return html.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
}

function aiSectionHtml(id) {
  const match = sources['health-data-for-ai'].match(
    new RegExp(`<section\\b[^>]*id="${id}"[^>]*>([\\s\\S]*?)<\\/section>`),
  );
  assert.ok(match, `AI section exists: ${id}`);
  return match[1];
}

function aiSection(id) {
  return textContent(aiSectionHtml(id));
}

function assertLocalMcpTopologies(text) {
  // Factual contract from the MCP guide and CLI qualification/compatibility ledgers.
  const facts = [
    ['standalone command', /healthmd mcp serve/],
    ['standalone host platforms', /macOS, Linux, and Windows/],
    ['standalone qualification', /explicitly unqualified preview, not a qualified stable release/],
    ['direct paired-phone backend without the Mac app', /connects directly to a paired foreground phone without the Mac app/],
    ['explicit standalone pairing', /healthmd direct pair/],
    ['phone opt-in', /enable Direct CLI Access/],
    ['local host transport', /local MCP host with stdio support/],
    ['legacy Mac-app prerequisite', /legacy bundled[^]*healthmd-mcp[^]*requires Health\.md for Mac installed and open/i],
    ['legacy query backend', /queries encrypted Mac context/],
    ['legacy fresh-work prerequisite', /connected foreground iPhone for explicit refreshes and fresh exports/],
    ['typed-query platform limit', /Typed queries require a query-capable iPhone; Android typed MCP queries are not supported/],
  ];
  for (const [fact, pattern] of facts) {
    assert.match(text, pattern, fact);
  }
}

test('health-data-for-ai: cards distinguish standalone preview and legacy Mac MCP requirements', () => {
  assertLocalMcpTopologies(aiSection('two-paths'));
});

test('health-data-for-ai: setup separates standalone pairing and credentials from the Mac helper', () => {
  const setup = aiSection('per-assistant');
  assertLocalMcpTopologies(setup);
  assert.match(setup, /Manual IP or Tailscale/, 'standalone reachability');
  assert.match(setup, /Keychain on macOS, an unlocked Secret Service on Linux, or Credential Manager on Windows/, 'native credentials, including the Linux prerequisite');
  assert.match(setup, /For standalone, configure the absolute installed healthmd path with arguments mcp serve/, 'Claude standalone stdio entry');
  assert.match(setup, /For standalone, use healthmd setup codex/, 'Codex standalone setup command');
});

function visibleAiFaqAnswers() {
  const html = aiSectionHtml('frequently-asked-questions');
  return new Map([...html.matchAll(/<h3>([^<]+)<\/h3>\s*<p>([\s\S]*?)<\/p>/g)]
    .map(([, question, answer]) => [question, textContent(answer)]));
}

function structuredAiFaqs() {
  const jsonLd = sources['health-data-for-ai'].match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
  assert.ok(jsonLd, 'AI JSON-LD block exists');
  const faq = JSON.parse(jsonLd[1])['@graph'].find((node) => node['@type'] === 'FAQPage');
  assert.ok(faq, 'AI FAQPage entity exists');
  return faq.mainEntity;
}

test('health-data-for-ai: visible and structured FAQs agree on both MCP topologies', () => {
  const answers = visibleAiFaqAnswers();
  const question = 'Do I need the Mac app to use MCP?';
  assert.ok(answers.has(question), 'visible Mac-app prerequisite FAQ');
  assertLocalMcpTopologies(answers.get(question));
  const faq = structuredAiFaqs();
  const prerequisite = faq.find((entity) => entity.name === question);
  assert.ok(prerequisite, 'structured Mac-app prerequisite FAQ');
  assertLocalMcpTopologies(prerequisite.acceptedAnswer.text);
  for (const entity of faq) {
    assert.equal(entity.acceptedAnswer['@type'], 'Answer');
    assert.equal(entity.acceptedAnswer.text, answers.get(entity.name), `visible/JSON-LD answer parity: ${entity.name}`);
  }
});

test('health-data-for-ai: local MCP does not imply Cloud consent, live retained reads, or hosted-client qualification', () => {
  const answers = visibleAiFaqAnswers();
  const cloudAnswer = answers.get("Is my health data sent to Health.md's servers for AI use?");
  assert.ok(cloudAnswer, 'visible server/privacy FAQ');
  for (const text of [aiSection('scoped'), cloudAnswer]) {
    assert.match(text, /Local pairing does not authorize Cloud uploads or third-party Cloud reads/, 'separate consent boundaries');
    assert.match(text, /separately authorized read-only Cloud MCP pilot reads retained exports, not a live phone/, 'retained-export topology is not a live-phone query');
    assert.match(text, /disposable single-user VM pilot has no backups or independent security-review sign-off/, 'disposable pilot is not production security/durability approval');
    assert.match(text, /General production rollout remains unapproved/, 'production approval blocker preserved');
  }
  assert.match(answers.get('Which AI assistants work with Health.md?'), /not a hosted-client compatibility guarantee/, 'local setup does not qualify hosted clients');
  const body = sources['health-data-for-ai'].split('<body')[1];
  assert.doesNotMatch(body, /Health\.md never stores your health data|keeps no health-data cloud|there is no Health\.md health-data cloud/, 'local-only claims must not deny the separate retained-export pilot');
});
