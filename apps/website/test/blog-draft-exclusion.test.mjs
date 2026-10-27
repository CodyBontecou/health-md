import assert from 'node:assert/strict';
import { access, mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';
import { buildBlog } from '../scripts/build-blog.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
test('blog publication follows draft status and excludes review ledgers', async (t) => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-blog-drafts-'));
  t.after(() => rm(outputRoot, { recursive: true, force: true }));
  const posts = await buildBlog({ outputRoot });
  assert.ok(posts.length > 0, 'the real builder must still publish existing articles');
  const index = await readFile(path.join(outputRoot, 'blog/index.html'), 'utf8');
  const sitemap = await readFile(path.join(outputRoot, 'sitemap.xml'), 'utf8');
  const entries = await readdir(path.join(ROOT, 'content/blog'), { withFileTypes: true });
  const articles = entries.filter((entry) => entry.isFile() && entry.name.endsWith('.md'));
  assert.ok(articles.length > 0, 'publication check must inspect real sources');
  for (const entry of articles) {
    const raw = await readFile(path.join(ROOT, 'content/blog', entry.name), 'utf8');
    const { data } = matter(raw);
    const slug = data.slug || entry.name.replace(/\.md$/, '');
    const published = data.draft !== true;
    assert.equal(posts.some((post) => post.slug === slug), published, `${slug}: builder publication`);
    assert.equal(index.includes(`href="${slug}/"`), published, `${slug}: index publication`);
    assert.equal(sitemap.includes(`/blog/${slug}/`), published, `${slug}: sitemap publication`);
    if (published) {
      await access(path.join(outputRoot, 'blog', slug, 'index.html'));
    } else {
      await assert.rejects(access(path.join(outputRoot, 'blog', slug)), { code: 'ENOENT' });
    }
  }
  await assert.rejects(access(path.join(outputRoot, 'blog/_review')), { code: 'ENOENT' });
});
