import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { buildDocsMetadataMap } from '../docs-src/lib/docs-metadata.mjs';

test('concurrent metadata preserves per-file Git dates and source order through merges and renames', async (t) => {
  const repositoryRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-docs-history-'));
  t.after(() => rm(repositoryRoot, { recursive: true, force: true }));
  const contentRoot = path.join(repositoryRoot, 'docs');
  await mkdir(contentRoot);
  let sequence = 0;
  const git = (...args) => execFileSync('git', [
    '-c', 'user.name=Metadata Test', '-c', 'user.email=metadata@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', ...args,
  ], {
    cwd: repositoryRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      GIT_AUTHOR_DATE: new Date(Date.UTC(2020, 0, 1, 0, 0, sequence)).toISOString(),
      GIT_COMMITTER_DATE: new Date(Date.UTC(2020, 0, 1, 0, 0, sequence++)).toISOString(),
    },
  });
  git('init', '-b', 'main');
  await writeFile(path.join(contentRoot, 'index.md'), '# Docs');
  await writeFile(path.join(contentRoot, 'old.md'), '# Original');
  git('add', '.');
  git('commit', '-m', 'Initial docs');
  git('checkout', '-b', 'feature');
  await writeFile(path.join(contentRoot, 'branch.md'), '# Branch');
  git('add', '.');
  git('commit', '-m', 'Branch docs');
  git('checkout', 'main');
  await writeFile(path.join(contentRoot, 'index.md'), '# Updated docs');
  git('add', '.');
  git('commit', '-m', 'Main docs');
  git('merge', '--no-ff', 'feature', '-m', 'Merge docs');
  git('mv', 'docs/old.md', 'docs/renamed with spaces.md');
  git('commit', '-m', 'Rename docs');
  await writeFile(path.join(contentRoot, 'untracked.md'), '# Untracked');

  const map = await buildDocsMetadataMap({ contentRoot, repositoryRoot });
  assert.equal(map.size, 4);
  assert.deepEqual([...map.keys()], ['/docs/branch/', '/docs/', '/docs/renamed with spaces/', '/docs/untracked/']);
  for (const entry of map.values()) {
    const expected = git('log', '-1', '--format=%cI', '--', path.relative(repositoryRoot, entry.sourcePath)).trim();
    assert.equal(entry.lastModified?.toISOString(), expected ? new Date(expected).toISOString() : undefined);
  }
  assert.equal(new Set([...map.values()].map((entry) => entry.lastModified?.toISOString())).size, 4);

  git('add', '.');
  git('commit', '-m', 'Track new doc');
  const refreshed = await buildDocsMetadataMap({ contentRoot, repositoryRoot });
  assert.ok(refreshed.get('/docs/untracked/').lastModified instanceof Date);
});

test('metadata still works without Git history and with an empty content directory', async (t) => {
  const contentRoot = await mkdtemp(path.join(os.tmpdir(), 'healthmd-docs-no-git-'));
  t.after(() => rm(contentRoot, { recursive: true, force: true }));
  assert.equal((await buildDocsMetadataMap({ contentRoot, repositoryRoot: contentRoot })).size, 0);
  await writeFile(path.join(contentRoot, 'index.md'), '# Docs');
  const map = await buildDocsMetadataMap({ contentRoot, repositoryRoot: contentRoot });
  assert.equal(map.get('/docs/').lastModified, undefined);
});
