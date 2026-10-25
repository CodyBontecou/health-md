import assert from 'node:assert/strict';
import { access, mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';
import { buildBlog } from '../scripts/build-blog.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DRAFTS = [
  'analyze-apple-health-with-claude',
  'apple-health-to-google-sheets',
  'export-health-data-without-the-cloud',
];

test('review drafts stay out of generated articles, index and sitemap', async (t) => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-blog-drafts-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  const posts = await buildBlog({ outputRoot });
  assert.ok(posts.length > 0, 'the real builder must still publish existing articles');
  const index = await readFile(path.join(outputRoot, 'blog/index.html'), 'utf8');
  const sitemap = await readFile(path.join(outputRoot, 'sitemap.xml'), 'utf8');
  for (const slug of DRAFTS) {
    const raw = await readFile(path.join(ROOT, 'content/blog', `${slug}.md`), 'utf8');
    const { data } = matter(raw);
    assert.equal(data.draft, true, `${slug} requires a separate publication review`);
    assert.equal(data.verified, undefined, 'historical evidence is not publication approval');
    assert.ok(!posts.some((post) => post.slug === slug));
    assert.ok(!index.includes(`/blog/${slug}/`));
    assert.ok(!sitemap.includes(`/blog/${slug}/`));
    await assert.rejects(access(path.join(outputRoot, 'blog', slug)), { code: 'ENOENT' });
  }
  await assert.rejects(access(path.join(outputRoot, 'blog/_review')), { code: 'ENOENT' });
});
