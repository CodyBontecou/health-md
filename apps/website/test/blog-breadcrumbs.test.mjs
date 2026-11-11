import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { buildBlog } from '../scripts/build-blog.mjs';

const ORIGIN = 'https://healthmd.app';
const schemas = html => [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map(match => JSON.parse(match[1]));

test('published articles have visible breadcrumbs matching structured data and canonicals', async t => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-blog-breadcrumbs-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  const posts = await buildBlog({ outputRoot });
  assert.ok(posts.length > 0);
  const index = await readFile(path.join(outputRoot, 'blog/index.html'), 'utf8');
  assert.deepEqual(schemas(index).map(schema => schema['@type']), ['Blog']);
  const sitemap = await readFile(path.join(outputRoot, 'sitemap.xml'), 'utf8');
  for (const post of posts) {
    const canonical = `${ORIGIN}/blog/${post.slug}/`;
    const html = await readFile(path.join(outputRoot, 'blog', post.slug, 'index.html'), 'utf8');
    const data = schemas(html);
    assert.deepEqual(data.map(schema => schema['@type']), ['BlogPosting', 'BreadcrumbList'], post.slug);
    const [article, breadcrumb] = data;
    assert.equal(article.mainEntityOfPage, canonical);
    assert.equal(article.headline, post.title);
    assert.equal(article.datePublished, post.date.toISOString().slice(0, 10));
    assert.equal(article.dateModified, post.updated.toISOString().slice(0, 10));
    assert.equal(breadcrumb['@context'], 'https://schema.org');
    assert.deepEqual(breadcrumb.itemListElement, [
      { '@type': 'ListItem', position: 1, name: 'Health.md', item: `${ORIGIN}/` },
      { '@type': 'ListItem', position: 2, name: 'Guides', item: `${ORIGIN}/blog/` },
      { '@type': 'ListItem', position: 3, name: post.title, item: canonical },
    ]);
    const nav = html.match(/<nav class="article-breadcrumbs" aria-label="Breadcrumb">([\s\S]*?)<\/nav>/)?.[1];
    assert.ok(nav, post.slug);
    const links = [...nav.matchAll(/<a href="([^"]+)">([^<]+)<\/a>/g)];
    assert.deepEqual(links.map(match => ({ url: match[1], name: match[2] })),
      breadcrumb.itemListElement.slice(0, -1).map(item => ({ url: item.item, name: item.name })));
    assert.equal(nav.match(/<span aria-current="page">([\s\S]*?)<\/span>/)?.[1], html.match(/<h1>([\s\S]*?)<\/h1>/)?.[1]);
    assert.equal((nav.match(/aria-current="page"/g) || []).length, 1);
    assert.equal((nav.match(/aria-hidden="true"/g) || []).length, 2);
    assert.ok(html.includes(`<link rel="canonical" href="${canonical}">`));
    assert.ok(sitemap.includes(`<loc>${canonical}</loc>`));
  }
});
