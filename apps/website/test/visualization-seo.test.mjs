import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { execFileSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const origin = 'https://healthmd.app';
const catalog = JSON.parse(await fs.readFile(path.join(root, 'assets/visualizations-catalog.json'), 'utf8'));
const scripts = (html) => [...html.matchAll(/<script\b[^>]*\bsrc="([^"]+)"/g)].map((match) => match[1]);
const visualizationBlock = (xml) => xml.match(/<!-- BEGIN GENERATED VISUALIZATION URLS -->[\s\S]*?<!-- END GENERATED VISUALIZATION URLS -->/)[0];

test('every share variant survives while HTML, schema and sitemap agree on one representative per chart', async () => {
  const output = await fs.mkdtemp(path.join(os.tmpdir(), 'healthmd-viz-seo-'));
  try {
    await fs.mkdir(path.join(output, 'visualizations'));
    const sourceSitemap = await fs.readFile(path.join(root, 'sitemap.xml'), 'utf8');
    await fs.writeFile(path.join(output, 'sitemap.xml'), sourceSitemap);
    execFileSync(process.execPath, [path.join(root, 'scripts/generate-visualization-pages.mjs'), '--output', output]);
    const sitemap = await fs.readFile(path.join(output, 'sitemap.xml'), 'utf8');
    const block = visualizationBlock(sitemap);
    const representatives = [...block.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
    assert.equal(representatives.length, catalog.visualizations.length);
    assert.equal(new Set(representatives).size, representatives.length);
    assert.doesNotMatch(block, /all-health-data|default-colors|ocean-colors|<lastmod>/);
    assert.equal(sitemap.replace(block, ''), sourceSitemap.replace(visualizationBlock(sourceSitemap), ''));
    assert.equal(block, visualizationBlock(sourceSitemap), 'checked-in sitemap must match generated representatives');
    const templateScripts = scripts(await fs.readFile(path.join(root, 'visualizations/index.html'), 'utf8'));
    let generated = 0;
    for (const representative of representatives) {
      assert.ok(representative.endsWith('/theme-colors/'));
      const segments = new URL(representative).pathname.split('/').filter(Boolean);
      const [, category, chart] = segments;
      const item = catalog.visualizations.find((item) => item.type === chart);
      assert.ok(item, chart);
      for (const filter of [category, 'all-health-data']) {
        for (const palette of ['theme', 'default', 'ocean', 'forest', 'sunset', 'aurora', 'monochrome']) {
          const route = `/visualizations/${filter}/${chart}/${palette}-colors/`;
          const html = await fs.readFile(path.join(output, route, 'index.html'), 'utf8');
          assert.equal(await fs.readFile(path.join(root, route, 'index.html'), 'utf8'), html,
            'checked-in previews must match the generator');
          assert.deepEqual([...html.matchAll(/<link rel="canonical" href="([^"]+)"/g)].map((match) => match[1]), [representative]);
          assert.ok(html.includes(`<meta property="og:url" content="${origin}${route}">`), 'sharing retains exact variant');
          const schema = JSON.parse(html.match(/<script type="application\/ld\+json" data-viz-schema>(.*?)<\/script>/s)[1]);
          assert.equal(schema.url, representative);
          assert.doesNotMatch(html, /<meta name="robots" content="[^"]*noindex/);
          assert.deepEqual(scripts(html), templateScripts, 'interactive preview scripts remain intact');
          generated++;
        }
      }
    }
    assert.equal(generated, catalog.visualizations.length * 14);
    // Regeneration must not churn dates or duplicate the sitemap block.
    execFileSync(process.execPath, [path.join(root, 'scripts/generate-visualization-pages.mjs'), '--output', output]);
    assert.equal(await fs.readFile(path.join(output, 'sitemap.xml'), 'utf8'), sitemap);
  } finally { await fs.rm(output, { recursive: true, force: true }); }
});

test('customizer keeps canonical independent of palette/filter while preserving share and history URLs', async () => {
  const source = await fs.readFile(path.join(root, 'assets/visualization-customizer.js'), 'utf8');
  const attributes = new Map();
  const historyCalls = [];
  const window = {
    location: { origin, pathname: '/visualizations/', search: '', hash: '' },
    history: {
      replaceState: (_state, _title, url) => historyCalls.push(url),
      pushState: (_state, _title, url) => historyCalls.push(url),
    },
  };
  const document = {
    addEventListener() {},
    head: { querySelector: (selector) => ({ setAttribute: (name, value) => attributes.set(`${selector}:${name}`, value) }) },
  };
  const instrumented = source.replace(/\}\)\(\);\s*$/, 'window.testSeo = { state, updatePageMetadata, syncUrl, visualizations }; })();');
  vm.runInNewContext(instrumented, { window, document });
  const { state, updatePageMetadata, syncUrl, visualizations } = window.testSeo;
  for (const chart of ['mood-trend', 'activity-rings']) {
    const item = visualizations.find((item) => item.id === chart);
    assert.ok(item);
    for (const filter of ['all', item.category]) {
      for (const palette of ['ocean', 'theme']) {
        Object.assign(state, { visualization: item.id, dataFilter: filter, colorScheme: palette });
        syncUrl(item, true);
        updatePageMetadata(item);
        const shareUrl = attributes.get('meta[property="og:url"]:content');
        assert.equal(shareUrl, origin + historyCalls.at(-1));
        assert.ok(shareUrl.endsWith(`/${item.id}/${palette}-colors/`));
        const canonical = attributes.get('link[rel="canonical"]:href');
        assert.ok(canonical.endsWith(`/${item.id}/theme-colors/`));
        assert.ok(!canonical.includes('/all-health-data/'));
        assert.equal(canonical, chart === 'mood-trend'
          ? `${origin}/visualizations/mindfulness-mood/mood-trend/theme-colors/`
          : `${origin}/visualizations/activity-fitness/activity-rings/theme-colors/`);
      }
    }
  }
});
