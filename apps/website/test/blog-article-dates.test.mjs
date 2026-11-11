import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildBlog } from '../scripts/build-blog.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('article authors and visible dates agree with source, schema and social metadata', async t => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-article-dates-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  const posts = await buildBlog({ outputRoot });
  const profile = await readFile(path.join(ROOT, 'about/index.html'), 'utf8');
  const sitemap = await readFile(path.join(outputRoot, 'sitemap.xml'), 'utf8');
  let changedDates = 0;
  let originalDates = 0;
  assert.ok(posts.length > 0);
  for (const post of posts) {
    const html = await readFile(path.join(outputRoot, 'blog', post.slug, 'index.html'), 'utf8');
    const article = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
    const byline = html.match(/<p class="article-byline">([\s\S]*?)<\/p>/)?.[1];
    assert.ok(byline, post.slug);
    assert.ok(html.indexOf(byline) > html.indexOf('</h1>'));
    assert.ok(html.indexOf(byline) < html.indexOf('<p class="lead">'));
    const author = byline.match(/By <a href="([^"]+)" rel="author">([^<]+)<\/a>/);
    assert.equal(author[1], article.author.url);
    assert.equal(author[2], article.author.name);
    assert.equal(article.author['@type'], 'Person');
    const authorUrl = new URL(author[1]);
    assert.equal(authorUrl.origin, 'https://healthmd.app');
    assert.equal(authorUrl.pathname, '/about/');
    assert.ok(profile.includes(`id="${authorUrl.hash.slice(1)}"`));
    assert.ok(profile.includes(author[2]));
    const dates = [...byline.matchAll(/(Published|Updated) <time datetime="([^"]+)">([^<]+)<\/time>/g)];
    const published = post.date.toISOString().slice(0, 10);
    const modified = post.updated.toISOString().slice(0, 10);
    assert.equal(article.datePublished, published);
    assert.equal(article.dateModified, modified);
    assert.deepEqual(dates.map(match => [match[1], match[2]]), [
      ['Published', published], ...(modified !== published ? [['Updated', modified]] : []),
    ], post.slug);
    for (const [, , iso, label] of dates) {
      assert.equal(new Date(`${label} UTC`).toISOString().slice(0, 10), iso, 'human-readable date matches machine date');
    }
    assert.ok(html.includes(`<meta property="article:published_time" content="${published}">`));
    assert.ok(html.includes(`<meta property="article:modified_time" content="${modified}">`));
    assert.ok(sitemap.includes(`<loc>https://healthmd.app/blog/${post.slug}/</loc>\n    <lastmod>${modified}</lastmod>`));
    if (modified !== published) changedDates++; else originalDates++;
  }
  assert.ok(changedDates > 0, 'updated articles are covered');
  assert.ok(originalDates > 0, 'unchanged articles avoid a redundant update date');
  const index = await readFile(path.join(outputRoot, 'blog/index.html'), 'utf8');
  assert.ok(!index.includes('class="article-byline"'));
  assert.ok(!index.includes('property="article:modified_time"'));
});
