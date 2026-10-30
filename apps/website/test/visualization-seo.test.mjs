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

test('studio identity survives saved selections, theme rerenders and Back while explicit selections retain chart URLs', async () => {
  const source = await fs.readFile(path.join(root, 'assets/visualization-customizer.js'), 'utf8');
  const html = await fs.readFile(path.join(root, 'visualizations/index.html'), 'utf8');
  const attributes = new Map();
  const initialTitle = html.match(/<title>(.*?)<\/title>/s)[1];
  for (const match of html.matchAll(/<meta (name|property)="([^"]+)" content="([^"]*)"/g)) {
    attributes.set(`meta[${match[1]}="${match[2]}"]:content`, match[3]);
  }
  attributes.set('link[rel="canonical"]:href', `${origin}/visualizations/`);
  const initialAttributes = new Map(attributes);
  const calls = [];
  const location = { origin, pathname: '/visualizations/', search: '', hash: '' };
  function navigate(method, url) {
    calls.push({ method, url });
    const next = new URL(url, origin);
    Object.assign(location, { pathname: next.pathname, search: next.search, hash: next.hash });
  }
  const window = { location, HealthMdPluginVisualizations: { colorSchemes: { ocean: {}, forest: {} } }, history: {
    replaceState: (_state, _title, url) => navigate('replace', url),
    pushState: (_state, _title, url) => navigate('push', url),
  } };
  const document = {
    title: initialTitle, addEventListener() {},
    head: { querySelector: (selector) => ({
      getAttribute: (name) => attributes.get(`${selector}:${name}`),
      setAttribute: (name, value) => attributes.set(`${selector}:${name}`, value),
    }) },
  };
  const instrumented = source.replace(/\}\)\(\);\s*$/, 'window.testIdentity = { state, readState, captureStudioMetadata, syncPageIdentity, readUrlState, applyUrlState, visualizations }; })();');
  const localStorage = { getItem: () => JSON.stringify({ visualization: 'mood-trend', dataFilter: 'mental', colorScheme: 'ocean' }) };
  vm.runInNewContext(instrumented, { window, document, URLSearchParams, localStorage });
  const api = window.testIdentity;
  api.captureStudioMetadata();
  api.readState();
  const savedChart = api.visualizations.find((item) => item.id === 'mood-trend');
  assert.equal(api.state.visualization, savedChart.id);
  assert.equal(api.state.colorScheme, 'ocean');
  const assertStudio = () => {
    assert.equal(location.pathname, '/visualizations/');
    assert.equal(document.title, initialTitle);
    assert.deepEqual(attributes, initialAttributes);
  };
  api.syncPageIdentity(savedChart); // Initial render with a restored nondefault preference.
  assertStudio();
  api.syncPageIdentity(savedChart); // Site theme changes rerender without navigation intent.
  assertStudio();
  assert.equal(calls.length, 0);

  api.syncPageIdentity(savedChart, { pushUrl: true });
  assert.equal(calls.at(-1).method, 'push');
  assert.equal(location.pathname, '/visualizations/mindfulness-mood/mood-trend/ocean-colors/');
  assert.equal(attributes.get('link[rel="canonical"]:href'), `${origin}/visualizations/mindfulness-mood/mood-trend/theme-colors/`);
  assert.equal(attributes.get('meta[property="og:url"]:content'), origin + location.pathname);

  Object.assign(location, { pathname: '/visualizations/', search: '', hash: '' });
  api.applyUrlState(api.readUrlState());
  api.syncPageIdentity(savedChart, { skipUrl: true }); // popstate/Back to the studio.
  assertStudio();
  assert.equal(calls.length, 1);

  location.search = '?viz=activity-rings&colors=forest&data=activity';
  api.applyUrlState(api.readUrlState());
  const explicitChart = api.visualizations.find((item) => item.id === api.state.visualization);
  api.syncPageIdentity(explicitChart);
  assert.ok(location.pathname.endsWith('/activity-rings/forest-colors/'));
  assert.equal(location.search, '');
  assert.equal(attributes.get('link[rel="canonical"]:href'), `${origin}/visualizations/activity-fitness/activity-rings/theme-colors/`);
  const explicitTitle = document.title;
  api.syncPageIdentity(explicitChart);
  assert.equal(document.title, explicitTitle, 'deep-link theme rerender remains a chart');
});
