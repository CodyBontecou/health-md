import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { weeklyReviewFiles, buildWeeklyReviewSample, ARCHIVE_PATH, SAMPLE_DIR, ROOT_NAME } from '../scripts/build-weekly-review-sample.mjs';
import { sampleFiles } from '../scripts/build-spreadsheet-samples.mjs';
import { zipVault } from '../scripts/build-starter-vault.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
function python(args) {
  const result = spawnSync('python3', args, { cwd: ROOT, env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' }, encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  return result;
}

test('weekly review download is reproducible and reuses the published daily CSV inputs', async () => {
  const files = await weeklyReviewFiles();
  assert.equal(files.size, 33);
  const daily = [...sampleFiles()].filter(([name]) => name.startsWith('daily/'));
  assert.equal(daily.length, 28);
  for (const [name, bytes] of daily) assert.deepEqual(files.get(name), bytes);
  const manifest = JSON.parse(files.get('manifest.json'));
  assert.equal(manifest.fictional, true);
  for (const [name, digest] of Object.entries(manifest.files)) {
    assert.equal(createHash('sha256').update(files.get(name)).digest('hex'), digest);
  }
  assert.match(files.get('LICENSE').toString(), /MIT License/);
  assert.deepEqual(await fs.readFile(ARCHIVE_PATH), zipVault(files, { rootName: ROOT_NAME }));
  await buildWeeklyReviewSample({ check: true });
});

test('downloaded ZIP runs with no additional packages and matches the published expected report', async () => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'healthmd-weekly-example-'));
  try {
    const result = python(['-c', `
from pathlib import Path
import hashlib, json, subprocess, sys, zipfile
archive, destination, root_name = sys.argv[1:]
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist())
    z.extractall(destination)
root = Path(destination) / root_name
manifest = json.loads((root / 'manifest.json').read_text())
for name, digest in manifest['files'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest
subprocess.run([sys.executable, str(root / 'weekly_review.py')], check=True, cwd=root)
actual = (root / 'weekly-review.md').read_bytes()
assert actual == (root / 'expected-weekly-review.md').read_bytes()
print('Extracted download, checked every hash, and reproduced the expected report.')
`, ARCHIVE_PATH, temporary, ROOT_NAME]);
    assert.match(result.stdout, /reproduced the expected report/);
    assert.deepEqual(await fs.readFile(path.join(SAMPLE_DIR, 'expected-weekly-review.md')), await fs.readFile(path.join(temporary, ROOT_NAME, 'weekly-review.md')));
  } finally {
    await fs.rm(temporary, { recursive: true, force: true });
  }
});

test('weekly CSV parsing preserves missingness and rejects ambiguous totals', () => {
  python(['-m', 'unittest', 'discover', '-s', 'examples/weekly-review', '-p', 'test_*.py']);
});
