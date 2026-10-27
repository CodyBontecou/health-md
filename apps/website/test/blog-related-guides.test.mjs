import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { buildBlog, resolveRelatedGuides } from '../scripts/build-blog.mjs';

test('curated recommendations retain editorial order and use published target metadata', () => {
  const first = { slug: 'first', title: 'First', related: ['third', 'second'] };
  const second = { slug: 'second', title: 'Second' };
  const third = { slug: 'third', title: 'Third' };
  const resolved = resolveRelatedGuides([first, second, third]);
  assert.deepEqual(resolved.get('first'), [third, second]);
  assert.deepEqual(resolved.get('second'), []);
});

for (const [name, related] of Object.entries({
  'self references': ['source'],
  'unpublished or missing targets': ['draft'],
  'duplicate targets': ['target', 'target'],
  'non-array configuration': 'target',
  'non-string targets': [null],
  'more than three targets': ['a', 'b', 'c', 'd'],
})) {
  test(`recommendations fail the build for ${name}`, () => {
    assert.throws(() => resolveRelatedGuides([
      { slug: 'source', related }, { slug: 'target' },
    ]), /source: /);
  });
}

test('ambiguous published slugs fail before resolving recommendations', () => {
  assert.throws(() => resolveRelatedGuides([{ slug: 'same' }, { slug: 'same' }]), /unique slugs/);
});

test('every published guide renders three distinct, crawlable recommendations with target-owned labels', async t => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-related-guides-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  const posts = await buildBlog({ outputRoot });
  const bySlug = new Map(posts.map(post => [post.slug, post]));
  const incoming = new Set();
  assert.ok(posts.length > 0);
  const index = await readFile(path.join(outputRoot, 'blog/index.html'), 'utf8');
  assert.ok(!index.includes('class="article-related"'), 'the directory is not an article');
  for (const post of posts) {
    const html = await readFile(path.join(outputRoot, 'blog', post.slug, 'index.html'), 'utf8');
    const nav = html.match(/<nav class="article-related" aria-labelledby="related-guides-title">([\s\S]*?)<\/nav>/)?.[1];
    assert.ok(nav, post.slug);
    assert.ok(nav.includes('<h2 id="related-guides-title">'));
    const links = [...nav.matchAll(/<a href="\/blog\/([^/]+)\/">([^<]+)<\/a>/g)];
    assert.equal(links.length, 3, post.slug);
    assert.deepEqual(links.map(link => link[1]), post.related, 'editorial order survives rendering');
    assert.equal(new Set(links.map(link => link[1])).size, 3);
    for (const [, slug, label] of links) {
      assert.notEqual(slug, post.slug);
      assert.ok(bySlug.has(slug), 'target is published');
      incoming.add(slug);
      const target = await readFile(path.join(outputRoot, 'blog', slug, 'index.html'), 'utf8');
      assert.equal(label, target.match(/<h1>([\s\S]*?)<\/h1>/)[1], 'link label follows target title');
      assert.ok(nav.includes(target.match(/<meta name="description" content="([^"]+)">/)[1]), 'description follows target metadata');
      assert.ok(target.includes(`<link rel="canonical" href="https://healthmd.app/blog/${slug}/">`));
    }
  }
  assert.equal(incoming.size, posts.length, 'all published guides have a related-guide inbound link');
});
