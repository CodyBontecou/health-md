import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const BLOG_DIR = path.join(ROOT, 'content', 'blog');
const REVIEW_DIR = path.join(BLOG_DIR, '_review');

// Posts published on or after this date must carry verification metadata.
// Earlier posts are grandfathered until their next update (the gate keys off
// both `date` and `updated`).
const VERIFICATION_CUTOFF = '2026-09-26';
const METHODS = new Set(['executed', 'traced', 'mixed']);

function ymd(value) {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value ?? '').slice(0, 10);
}

const entries = await readdir(BLOG_DIR, { withFileTypes: true });
const posts = entries
  .filter((entry) => entry.isFile() && entry.name.endsWith('.md'))
  .map((entry) => entry.name);

const scoped = [];
for (const filename of posts) {
  const raw = await readFile(path.join(BLOG_DIR, filename), 'utf8');
  const { data } = matter(raw);
  const slug = filename.replace(/\.md$/, '');
  if (data.draft === true) continue;
  const inScope =
    ymd(data.date) >= VERIFICATION_CUTOFF || ymd(data.updated ?? data.date) >= VERIFICATION_CUTOFF;
  if (inScope) scoped.push({ slug, data });
}

test(`found posts in verification scope (cutoff ${VERIFICATION_CUTOFF})`, () => {
  assert.ok(scoped.length > 0, 'at least one post is in scope so the gate is live');
});

for (const { slug, data } of scoped) {
  test(`${slug}: verification frontmatter is present and valid`, () => {
    assert.ok(data.verified, 'verified date is set');
    const verified = data.verified instanceof Date ? data.verified : new Date(String(data.verified));
    assert.ok(!Number.isNaN(verified.getTime()), 'verified is a valid date');
    assert.ok(
      typeof data.verified_by === 'string' && data.verified_by.trim().length > 0,
      'verified_by names who verified',
    );
    assert.ok(
      METHODS.has(data.verified_method),
      `verified_method is one of ${[...METHODS].join(', ')}`,
    );
  });

  test(`${slug}: claim ledger exists with verified claims`, async () => {
    const ledger = await readFile(path.join(REVIEW_DIR, `${slug}.md`), 'utf8');
    assert.ok(ledger.includes('## Claims'), 'ledger has a Claims section');
    const checked = ledger.match(/^- \[[xX]\]/gm) ?? [];
    assert.ok(checked.length >= 3, `ledger has at least 3 verified claims, found ${checked.length}`);
    const unverified = ledger.match(/^- \[ \]/gm) ?? [];
    assert.equal(unverified.length, 0, 'ledger has no unverified claims');
  });
}

test('verified-snippet registry entries carry verification evidence', async () => {
  const registry = await readFile(path.join(REVIEW_DIR, 'verified-snippets.md'), 'utf8');
  const sections = registry.split(/^## /m).slice(1);
  assert.ok(sections.length >= 1, 'registry has entries');
  for (const section of sections) {
    const name = section.split('\n')[0].trim();
    assert.ok(/^Verified: \d{4}-\d{2}-\d{2}/m.test(section), `${name}: has a Verified date`);
    assert.ok(/^Source: .+/m.test(section), `${name}: has a Source`);
  }
});
