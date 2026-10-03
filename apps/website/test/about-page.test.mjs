import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [about, index, styles, buildScript, llms, sitemap] = await Promise.all([
  readFile(path.join(ROOT, 'about/index.html'), 'utf8'),
  readFile(path.join(ROOT, 'index.html'), 'utf8'),
  readFile(path.join(ROOT, 'assets/about.css'), 'utf8'),
  readFile(path.join(ROOT, 'scripts/build-site.mjs'), 'utf8'),
  readFile(path.join(ROOT, 'llms.txt'), 'utf8'),
  readFile(path.join(ROOT, 'sitemap.xml'), 'utf8'),
]);

function section(id, nextId) {
  const start = about.indexOf(`id="${id}"`);
  const end = nextId ? about.indexOf(`id="${nextId}"`) : about.indexOf('</article>');
  assert.ok(start >= 0, `missing #${id}`);
  assert.ok(end > start, `invalid #${id} boundary`);
  return about.slice(start, end);
}

test('about page opens with a clear category, outcome, and audience value proposition', () => {
  assert.match(about, /<title>About Health\.md \| Local-First Health Data Portability<\/title>/);
  assert.match(about, /<link rel="canonical" href="https:\/\/healthmd\.app\/about\/">/);
  assert.match(
    about,
    /Health\.md is a local-first health data portability platform that turns Apple Health and Health Connect records into private files, automations, and agent-ready answers for people who want control of their health data\./,
  );
  assert.match(about, /Founded<\/span><strong>2026<\/strong>/);
  assert.match(about, /Founder<\/span><strong>Cody Bontecou<\/strong>/);
});

test('about page implements the service, differentiation, audience, team, and operating sections', () => {
  const services = section('what-healthmd-does', 'what-makes-healthmd-different');
  const differences = section('what-makes-healthmd-different', 'who-uses-healthmd');
  const audience = section('who-uses-healthmd', 'team-behind-healthmd');
  const team = section('team-behind-healthmd', 'how-healthmd-works');
  const process = section('how-healthmd-works', 'key-facts');

  assert.match(services, /<h2>What Health\.md does<\/h2>/);
  assert.equal((services.match(/<h3>/g) ?? []).length, 4);
  assert.match(services, /Private health data exports/);
  assert.match(services, /Scheduled local automation/);
  assert.match(services, /CLI, MCP, and direct device access/);

  assert.match(differences, /<h2>What makes Health\.md different<\/h2>/);
  assert.equal((differences.match(/<h3>/g) ?? []).length, 5);
  for (const namedAlternative of ['Guava', 'FitnessSyncer', 'Apple', 'Health Auto Export', 'QS Access', 'Google Health Connect']) {
    assert.match(differences, new RegExp(namedAlternative.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(differences, /10 free export actions/);
  assert.match(differences, /AGPL-3\.0-only/);

  assert.match(audience, /<h2>Who uses Health\.md<\/h2>/);
  assert.equal((audience.match(/<li>/g) ?? []).length, 6);

  assert.match(team, /<h2>The team behind Health\.md<\/h2>/);
  assert.match(team, /Cody Bontecou, founder/);
  assert.match(team, /began in January 2026/);
  assert.match(team, /founder-led, independently operated/);
  assert.match(team, /https:\/\/github\.com\/CodyBontecou/);

  assert.match(process, /<h2>How Health\.md works<\/h2>/);
  assert.match(process, /Install and authorize/);
  assert.match(process, /turnaround depends on the date range/);
  assert.match(process, /Customers work directly with the founder/);
  assert.match(process, /does not currently promise a guaranteed response or resolution SLA/);
});

test('key facts use a crawlable definition list with every requested field', () => {
  const facts = section('key-facts', 'frequently-asked-questions');
  const labels = [...facts.matchAll(/<dt>([^<]+)<\/dt>/g)].map((match) => match[1]);
  assert.deepEqual(labels, [
    'Company Name',
    'Type',
    'Founded',
    'Founder',
    'Headquarters',
    'Website',
    'Core Offering',
    'Pricing',
    'Contract Terms',
    'Services',
    'Communication',
    'Notable Clients',
    'Customers Served',
    'Projects Delivered',
    'Competitors',
    'Social',
  ]);
  assert.match(facts, /<dl class="key-facts">/);
  assert.doesNotMatch(facts, /<table/);
  assert.match(facts, /No public headquarters or storefront is listed/);
  assert.match(facts, /customer count is not publicly reported/);
});

test('FAQ uses visible H3 questions and valid matching structured data', () => {
  const faq = section('frequently-asked-questions');
  assert.match(faq, /<h2>Frequently asked questions<\/h2>/);
  assert.equal((faq.match(/<h3>/g) ?? []).length, 7);

  const schemas = [...about.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
  assert.equal(schemas.length, 1);
  const schema = JSON.parse(schemas[0][1]);
  const graphTypes = schema['@graph'].map((entry) => entry['@type']);
  assert.deepEqual(graphTypes, ['AboutPage', 'Organization', 'FAQPage']);
  const faqSchema = schema['@graph'].find((entry) => entry['@type'] === 'FAQPage');
  assert.equal(faqSchema.mainEntity.length, 7);
  for (const item of faqSchema.mainEntity) {
    assert.ok(faq.includes(`<h3>${item.name}</h3>`), item.name);
    assert.ok(faq.includes(`<p>${item.acceptedAnswer.text}</p>`) || item.name === 'How do I get support?', item.name);
  }
});

test('about page is discoverable, styled, copied by the build, and listed for crawlers', async () => {
  assert.match(index, /href="about\/">About<\/a>/);
  assert.match(buildScript, /'about'/);
  assert.match(llms, /https:\/\/healthmd\.app\/about\//);
  assert.match(sitemap, /<loc>https:\/\/healthmd\.app\/about\/<\/loc>/);
  assert.match(styles, /\.key-facts\s*{/);
  assert.match(styles, /\.about-card-grid\s*{/);
  assert.match(styles, /@media \(max-width: 720px\)/);
  await Promise.all([
    access(path.join(ROOT, 'about/index.html')),
    access(path.join(ROOT, 'assets/about.css')),
    access(path.join(ROOT, 'assets/app-icon/icon_192x192.png')),
  ]);
});
