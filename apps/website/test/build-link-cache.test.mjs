import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createBuildLinkCache } from '../scripts/lib/build-link-cache.mjs';
import { checkBuiltDocsLinks } from '../docs-src/scripts/check-built-links.mjs';
import { checkBuiltSiteLinks } from '../scripts/check-site-links.mjs';

async function fixture(t) {
  const dist = await mkdtemp(path.join(os.tmpdir(), 'healthmd-link-cache-'));
  t.after(() => rm(dist, { recursive: true, force: true }));
  await mkdir(path.join(dist, 'docs', 'guide'), { recursive: true });
  await writeFile(path.join(dist, 'docs', 'guide', 'index.html'),
    `<h1 id="title">Title</h1><h2 ID='café'>Heading</h2>`);
  await writeFile(path.join(dist, 'docs', 'flat.html'), '<h1 id="flat">Flat</h1>');
  return { dist, cache: createBuildLinkCache(dist, 'path escapes dist') };
}

const url = (pathname) => new URL(pathname, 'https://healthmd.app');

test('repeated routes and fragments reuse resolution and parsing without dropping missing IDs', async (t) => {
  const { dist, cache } = await fixture(t);
  const first = cache.targetFile(url('/docs/guide/#title'));
  const second = cache.targetFile(url('/docs/guide/?q=1#missing'));
  assert.equal(first, second);
  const target = await first;
  assert.equal(target, path.join(dist, 'docs', 'guide', 'index.html'));
  assert.equal(await cache.exists(target), true);
  const ids = await cache.idsFor(target);
  assert.deepEqual([...ids], ['title', 'café']);
  assert.equal(await cache.idsFor(target), ids);
  assert.equal(ids.has('missing'), false);
  assert.equal(ids.has(decodeURIComponent('caf%C3%A9')), true);
});

test('file resolution keeps extension fallback, directory precedence, and escaped filenames', async (t) => {
  const { dist, cache } = await fixture(t);
  await writeFile(path.join(dist, 'docs', 'guide.html'), 'fallback');
  await writeFile(path.join(dist, 'docs', 'with space.html'), 'space');
  await writeFile(path.join(dist, 'docs', 'image.svg'), '<svg/>');
  assert.equal(await cache.targetFile(url('/docs/guide/')), path.join(dist, 'docs', 'guide', 'index.html'));
  assert.equal(await cache.targetFile(url('/docs/flat')), path.join(dist, 'docs', 'flat.html'));
  assert.equal(await cache.targetFile(url('/docs/with%20space')), path.join(dist, 'docs', 'with space.html'));
  assert.equal(await cache.targetFile(url('/docs/image.svg')), path.join(dist, 'docs', 'image.svg'));
});

test('missing files and fragments remain failures; a new validation sees changed builds', async (t) => {
  const { dist, cache } = await fixture(t);
  const missing = await cache.targetFile(url('/docs/missing/'));
  assert.equal(missing, path.join(dist, 'docs', 'missing', 'index.html'));
  assert.equal(await cache.exists(missing), false);
  assert.equal(await cache.exists(missing), false);
  const target = await cache.targetFile(url('/docs/guide/'));
  assert.equal((await cache.idsFor(target)).has('new'), false);
  await writeFile(target, '<h1 id="new">Changed</h1>');
  const next = createBuildLinkCache(dist, 'path escapes dist');
  assert.equal((await next.idsFor(target)).has('new'), true);
});

test('encoded path traversal and malformed paths cannot bypass validation through cached resolution', async (t) => {
  const { cache } = await fixture(t);
  for (const pathname of ['/docs/%2e%2e%2f%2e%2e%2fsecret', '/docs/%ZZ/']) {
    const first = cache.targetFile(url(pathname));
    const second = cache.targetFile(url(pathname));
    assert.equal(first, second);
    await assert.rejects(first, pathname.includes('%ZZ') ? /URI malformed/ : /path escapes dist/);
    await assert.rejects(second);
  }
});

for (const check of [checkBuiltDocsLinks, checkBuiltSiteLinks]) {
  test(`${check.name} rejects empty build output`, async (t) => {
    const { dist } = await fixture(t);
    await rm(path.join(dist, 'docs'), { recursive: true });
    await assert.rejects(check(dist), /No HTML files found/);
  });

  test(`${check.name} retains every repeated missing-target and missing-fragment diagnostic`, async (t) => {
    const { dist } = await fixture(t);
    const links = [
      '/docs/guide/#title',
      '/docs/guide/#caf%C3%A9',
      '/docs/flat#flat',
      '/docs/guide/#missing',
      '/docs/guide/#missing',
      '/docs/missing/',
      '/docs/missing/',
      '/docs/%2e%2e%2f%2e%2e%2fsecret',
      '/docs/%ZZ/',
      'http://[invalid',
    ];
    await writeFile(path.join(dist, 'docs', 'index.html'),
      links.map((href) => `<a href="${href}">Link</a>`).join(''));
    const result = await check(dist);
    assert.equal(result.pages, 3);
    assert.equal(result.checked, 7);
    assert.equal(result.failures.length, 7);
    assert.equal(result.failures.filter((message) => message.includes('missing fragment #missing')).length, 2);
    assert.equal(result.failures.filter((message) => message.includes('-> missing docs/missing/index.html')).length, 2);
    assert.ok(result.failures.some((message) => message.includes('path escapes')));
    assert.ok(result.failures.some((message) => message.includes('URI malformed')));
    assert.ok(result.failures.some((message) => message.includes('invalid URL')));
  });
}

test('documentation and site checkers preserve their distinct route scopes', async (t) => {
  const { dist } = await fixture(t);
  await writeFile(path.join(dist, 'docs', 'index.html'), [
    '<a href="/privacy-policy.html">Legal page built by website</a>',
    '<a href="/unsupported/">Unsupported route</a>',
    '<a href="https://elsewhere.example/docs/missing/">External</a>',
    '<a href="mailto:test@example.com">Email</a>',
  ].join(''));
  const docs = await checkBuiltDocsLinks(dist);
  assert.equal(docs.checked, 0);
  assert.equal(docs.failures.length, 1);
  assert.match(docs.failures[0], /same-origin link escapes supported site paths: \/unsupported\//);
  const site = await checkBuiltSiteLinks(dist);
  assert.equal(site.checked, 2);
  assert.equal(site.failures.length, 2);
});
