import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { buildBlog } from '../scripts/build-blog.mjs';
import { funnelLink } from '../assets/seo-funnel.js';
import { funnelPage } from '../assets/funnel-contract.js';

const ORIGIN = 'https://healthmd.app';
const ANDROID = 'export-health-connect-to-obsidian';

test('guide directory offers both phone stores recognized by the existing funnel', async t => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-directory-downloads-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  await buildBlog({ outputRoot });
  const html = await readFile(path.join(outputRoot, 'blog/index.html'), 'utf8');
  const header = html.match(/<header[\s\S]*?<\/header>/)[0];
  const destinations = [...header.matchAll(/<a[^>]+href="([^"]+)"/g)]
    .map(match => funnelLink(new URL(match[1], ORIGIN).href, ORIGIN))
    .filter(target => target?.action === 'store_click').map(target => target.target);
  assert.deepEqual(destinations, ['app_store', 'google_play']);
});

test('Oura chooser offers both phone stores while preserving the native-download-first decision', async t => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-oura-downloads-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  await buildBlog({ outputRoot });
  const html = await readFile(path.join(outputRoot, 'blog/export-oura-data/index.html'), 'utf8');
  const header = html.match(/<header[\s\S]*?<\/header>/)[0];
  for (const label of ['App Store', 'Google Play']) assert.ok(header.includes(`>${label}</a>`));
  const body = html.match(/<div class="article-body">([\s\S]*?)<\/main>/)[1];
  assert.ok(body.includes('https://membership.ouraring.com/'));
  assert.ok(body.includes('https://apps.apple.com/'));
  assert.ok(body.indexOf('https://membership.ouraring.com/') < body.indexOf('https://apps.apple.com/'));
  assert.ok(body.includes('https://play.google.com/store/apps/details?id=com.healthmd.android'));
});

test('Android acquisition guide offers working Android destinations recognized by the existing funnel', async t => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-platform-downloads-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  const posts = await buildBlog({ outputRoot });
  const html = await readFile(path.join(outputRoot, 'blog', ANDROID, 'index.html'), 'utf8');
  const header = html.match(/<header[\s\S]*?<\/header>/)[0];
  assert.ok(header.includes('href="https://play.google.com/store/apps/details?id=com.healthmd.android"'));
  assert.ok(header.includes('>Google Play</a>'));
  assert.ok(!html.includes('apps.apple.com'), 'Android readers are not sent to an Apple-only download');
  assert.deepEqual(funnelPage(`/blog/${ANDROID}/`), { page: 'android_obsidian', locale: 'en' });
  const body = html.match(/<div class="article-body">([\s\S]*?)<\/main>/)[1];
  const targets = [...body.matchAll(/<a[^>]+href="([^"]+)"/g)]
    .map(match => funnelLink(new URL(match[1], ORIGIN).href, ORIGIN)).filter(Boolean);
  for (const expected of [
    { action: 'store_click', target: 'google_play' },
    { action: 'csv_sample_download', target: 'android_csv' },
  ]) assert.ok(targets.some(target => target.action === expected.action && target.target === expected.target), JSON.stringify(expected));
  assert.ok(body.includes('fictional steps and walking distance rows'));
  assert.ok(body.includes('does not migrate app state or purchases'));
  assert.ok(body.includes('installed app'));
  assert.ok(body.includes('F-Droid catalog publication is pending'));
  assert.ok(body.includes('href="/docs/android/#distribution-status"'));
  assert.ok(!body.includes('f-droid.org/packages/'));
  for (const post of posts.filter(post => post.platform === 'apple')) {
    const page = await readFile(path.join(outputRoot, 'blog', post.slug, 'index.html'), 'utf8');
    assert.ok(page.match(/<header[\s\S]*?<\/header>/)[0].includes('>App Store</a>'), post.slug);
  }
});

test('pending F-Droid publication is not advertised as a live catalog download', async () => {
  const { renderLanding, loadCatalog } = await import('../scripts/build-localized-pages.mjs');
  const { publishedLocales } = await import('../i18n/locales.mjs');
  const root = new URL('../', import.meta.url);
  const source = await readFile(new URL('index.html', root), 'utf8');
  const english = await loadCatalog('en');
  for (const locale of publishedLocales('landing')) {
    const catalog = await loadCatalog(locale.code);
    const home = renderLanding(source, locale.code, english, catalog);
    assert.ok(!home.includes('https://f-droid.org/packages/com.healthmd.android/'), locale.code);
    assert.ok(home.includes('#distribution-status'), locale.code);
    assert.ok(home.includes(catalog.landing.static.fdroidBadgeKicker), locale.code);
    const doc = await readFile(new URL(`docs-src/src/content/docs/${locale.code === 'en' ? '' : locale.code + '/'}android.md`, root), 'utf8');
    assert.ok(doc.includes('id="distribution-status"'), locale.code);
    assert.ok(!doc.includes('https://f-droid.org/packages/com.healthmd.android/'), locale.code);
  }
  const hub = await readFile(new URL('health-connect-export/index.html', root), 'utf8');
  assert.ok(!hub.includes('https://f-droid.org/packages/com.healthmd.android/'));
  assert.ok(hub.includes('Catalog publication is pending.'));
});
