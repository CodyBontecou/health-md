import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const guide = await readFile(new URL('../docs-src/src/content/docs/release-status.md', import.meta.url), 'utf8');
const fixtures = JSON.parse(await readFile(new URL('./fixtures/release-status-response-excerpts.json', import.meta.url), 'utf8'));
const examples = [...guide.matchAll(/```json\s*\n([\s\S]*?)\n```/g)].map((match) => JSON.parse(match[1]));

function validateExcerpt(example) {
  assert.ok(Object.hasOwn(fixtures, example.schema), 'Unknown readiness/capabilities schema');
  assert.deepEqual(example, fixtures[example.schema], 'Example differs from the source-reviewed response projection');
}

// These are documentation contract tests, not runtime or device qualification.
test('release-status examples cover each actual readiness/capabilities surface once', () => {
  assert.deepEqual(examples.map(({ schema }) => schema).sort(), Object.keys(fixtures).sort());
});

for (const schema of Object.keys(fixtures)) {
  test(`release-status ${schema} JSON matches the reviewed response excerpt`, () => {
    validateExcerpt(examples.find((example) => example.schema === schema));
  });
}

test('invented qualification/history fields are rejected even when false or null', () => {
  for (const example of examples) {
    for (const [field, value] of Object.entries({
      preview_unqualified: true,
      cli_1_0_qualified: false,
      certified_for_macos_27: false,
      history_authorization: null,
      encrypted_bytes: 0,
    })) {
      assert.equal(Object.hasOwn(example, field), false);
      assert.throws(() => validateExcerpt({ ...example, [field]: value }));
    }
  }
});

test('job progress bytes cannot be inserted as an encrypted query-store footprint', () => {
  const example = structuredClone(fixtures['healthmd.local_readiness']);
  for (const field of ['committed_bytes', 'encrypted_bytes']) {
    const changed = structuredClone(example);
    changed.query_store[field] = 0;
    assert.throws(() => validateExcerpt(changed));
  }
});

test('ready Android raw export cannot be rewritten as typed-query parity', () => {
  const example = examples.find(({ schema }) => schema === 'healthmd.direct_readiness');
  assert.equal(example.ready, true);
  assert.equal(example.raw_export_ready, true);
  assert.equal(example.query_ready, false);
  assert.throws(() => validateExcerpt({ ...example, query_ready: true }));
});

test('cache readiness cannot be rewritten as a connected fresh-acquisition path', () => {
  const example = examples.find(({ schema }) => schema === 'healthmd.local_readiness');
  assert.equal(example.status, 'ready');
  assert.equal(example.query_store.owner_date_count, 2);
  assert.equal(example.iphone.can_trigger_fresh_acquisition, false);
  const changed = structuredClone(example);
  changed.iphone.can_trigger_fresh_acquisition = true;
  assert.throws(() => validateExcerpt(changed));
});

test('schema version drift is rejected rather than silently rewriting the fixture', () => {
  for (const example of examples) {
    assert.throws(() => validateExcerpt({ ...example, schema_version: 2 }));
  }
});

test('release-status explains missingness, storage, and qualification without runtime promises', () => {
  // Prose guards supplement (not replace) the typed JSON contract tests above.
  assert.match(guide, /not complete responses or device captures/);
  assert.match(guide, /absence means \*\*not reported\*\*, not explicit false qualification, zero bytes, or complete history/);
  assert.match(guide, /Future machine-readable qualification\/history\/footprint fields require separately scoped, versioned implementation and tests/);
  assert.match(guide, /Durable-job `committed_bytes`[^\n]+\*\*not the encrypted context store's on-disk size\*\*/);
  assert.match(guide, /\*\*unqualified for stable 1\.0\*\*/);
  assert.match(guide, /macOS 27 remains \*\*not certified\*\*/);
  assert.match(guide, /Readiness does not currently return a `certified_for_macos_27` field/);
  assert.match(guide, /`all_available_history` is a scope capability, not proof of complete history authorization/);
  assert.match(guide, /MCP initialization `serverInfo\.version`[^\n]+separately from these tool responses/);
  assert.doesNotMatch(guide, /Until then, readiness reports/);
});
