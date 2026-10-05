import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { publishedLocales } from '../i18n/locales.mjs';

const WEBSITE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPOSITORY_ROOT = path.resolve(WEBSITE_ROOT, '../..');

async function source(relative) {
  return readFile(path.join(REPOSITORY_ROOT, relative), 'utf8');
}

test('Google Drive customer and release documentation preserves required boundaries', async () => {
  const [guide, feature, release, architecture] = await Promise.all([
    source('apps/website/docs-src/src/content/docs/guides/google-drive-export.md'),
    source('docs/features/google-drive-export.md'),
    source('docs/qa/google-drive-export-release-checklist.md'),
    source('docs/architecture/google-drive-export-destination.md'),
  ]);
  const combined = [guide, feature, release, architecture].join('\n');

  for (const required of [
    'drive.file',
    'Picker',
    'Shared Drive',
    'Health.md health-data',
    'token server',
    'best effort',
    'reauthorization_required',
    'Partial completion',
    'Shared Setup',
    'CLI',
    'MCP',
    'does not delete',
    'public health export schema',
  ]) {
    assert.ok(combined.toLowerCase().includes(required.toLowerCase()), `missing Google Drive documentation boundary: ${required}`);
  }
  assert.match(guide, /Planned · not available/);
  assert.match(guide, /Direct Drive is not Files or SAF/);
  assert.match(release, /App Privacy/);
  assert.match(release, /Data safety/);
  assert.match(release, /https:\/\/healthmd\.app\/privacy-policy\.html/);
});

test('every published privacy policy discloses direct Google Drive transfer and retention', async () => {
  for (const locale of publishedLocales('legal')) {
    const relative = locale.path
      ? `apps/website/${locale.path}/privacy-policy.html`
      : 'apps/website/privacy-policy.html';
    const policy = await source(relative);
    assert.match(policy, /<code>drive\.file<\/code>/, `${locale.code} privacy policy must name the requested scope`);
    assert.match(policy, /Picker/, `${locale.code} privacy policy must disclose Picker consent`);
    assert.match(policy, /Google Drive/, `${locale.code} privacy policy must identify Google Drive`);
    assert.match(policy, /api-services-user-data-policy/, `${locale.code} privacy policy must publish the Google API user-data policy disclosure`);
    assert.match(policy, /guides\/google-drive-export\//, `${locale.code} privacy policy must link to the customer guide`);
  }
});

test('Google Drive capability remains planned and points to release evidence', async () => {
  const capabilities = JSON.parse(await source('packages/contracts/product-capabilities.json'));
  const capability = capabilities.capabilities.find(({ id }) => id === 'destination.google-drive');
  assert.ok(capability);
  assert.equal(capability.classification, 'planned');
  assert.equal(capability.platforms.apple.state, 'planned');
  assert.equal(capability.platforms.android.state, 'planned');
  assert.ok(capability.evidence.includes('docs/qa/google-drive-export-release-checklist.md'));
  assert.ok(capability.evidence.includes('apps/website/docs-src/src/content/docs/guides/google-drive-export.md'));
});
