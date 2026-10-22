import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const slugs = [
  'analyze-apple-health-with-claude',
  'apple-health-to-google-sheets',
  'export-health-data-without-the-cloud',
];
const posts = {};
for (const slug of slugs) {
  const raw = await readFile(path.join(ROOT, 'content/blog', `${slug}.md`), 'utf8');
  posts[slug] = matter(raw).content;
}

for (const slug of slugs) {
  test(`${slug}: privacy claims name the local folder workflow and exclude the owner-only pilot`, () => {
    const body = posts[slug];
    assert.doesNotMatch(body, /Health\.md(?: itself)? (?:keeps|has|operates|runs|provides) no (?:health-data cloud|cloud hop)/i);
    assert.doesNotMatch(body, /nothing to leak|no retention policy to read/i);
    assert.match(body, /local folder (?:export|workflow)/i);
    const pilotBoundary = body.split(/\n\s*\n/).find((paragraph) => /Health\.md Cloud pilot/.test(paragraph));
    assert.ok(pilotBoundary, 'the separate pilot is distinguished from the tutorial workflow');
    for (const qualifier of [/separate/i, /opt-in/i, /single-owner/i, /not generally available/i]) {
      assert.match(pilotBoundary, qualifier);
    }
    assert.match(pilotBoundary, /only[^.\n]*exports[^.\n]*(?:intentionally|explicitly)/i);
    assert.match(pilotBoundary, /no public signup or automatic device sync/i);
  });
}

test('Claude tutorial documents file upload without making a global ChatGPT MCP capability claim', async () => {
  const ledger = await readFile(path.join(ROOT, 'content/blog/_review/analyze-apple-health-with-claude.md'), 'utf8');
  const registry = await readFile(path.join(ROOT, 'content/blog/_review/verified-snippets.md'), 'utf8');
  const snippet = registry.split('## ChatGPT path is file upload\n')[1]?.split(/^## /m)[0];
  assert.ok(snippet, 'the corresponding ChatGPT evidence entry exists');
  for (const text of [posts['analyze-apple-health-with-claude'], ledger, snippet]) {
    assert.doesNotMatch(text, /ChatGPT[^.!?]*(?:has no MCP|no MCP client connection|there is no MCP connection)/i);
    assert.match(text, /(?:this|the) file-upload (?:workflow|tutorial)/i);
  }
  assert.match(posts['analyze-apple-health-with-claude'], /AI provider[^.\n]*(?:policies|terms)/i);
});

test('Sheets tutorial discloses the Google upload and synced-folder boundary', () => {
  const body = posts['apple-health-to-google-sheets'];
  assert.match(body, /Google[^.\n]*(?:stores|receives)[^.\n]*(?:file|spreadsheet)[^.\n]*terms/i);
  assert.match(body, /synced folder[^.\n]*provider[^.\n]*rules/i);
});

test('local-only checklist requires a non-synced folder and avoids anonymization/deletion guarantees', () => {
  const body = posts['export-health-data-without-the-cloud'];
  assert.match(body, /non-synced[^.\n]*(?:folder|On My iPhone)/i);
  assert.match(body, /(?:records|files)[^.\n]*(?:identifiers|anonym)/i);
  assert.match(body, /(?:copies|backups)[^.\n]*(?:retention|deletion)[^.\n]*rules/i);
});
