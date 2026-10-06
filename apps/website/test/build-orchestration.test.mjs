import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

const root = new URL('../', import.meta.url);
const pkg = JSON.parse(await fs.readFile(new URL('package.json', root), 'utf8'));

// Execute the real script route with recording tools; no builds or installs.
async function traceRoute(t, name, failStep = '') {
  const directory = await fs.mkdtemp(path.join(tmpdir(), 'website-build-route-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const log = path.join(directory, 'calls');
  for (const tool of ['npm', 'node']) {
    const executable = path.join(directory, tool);
    await fs.writeFile(executable, '#!/bin/sh\nprintf "%s\\n" "${0##*/} $*" >> "$BUILD_TRACE"\nif [ "${FAIL_STEP:-}" = "$*" ]; then exit 9; fi\n');
    await fs.chmod(executable, 0o755);
  }
  let status = 0;
  try {
    execFileSync('/bin/sh', ['-c', pkg.scripts[name]], {
      env: { ...process.env, PATH: `${directory}:${process.env.PATH}`, BUILD_TRACE: log, FAIL_STEP: failStep },
      stdio: 'pipe',
    });
  } catch (error) {
    status = error.status;
  }
  return { status, calls: (await fs.readFile(log, 'utf8')).trim().split('\n') };
}

test('standalone builds install docs once, then use the CI build route', async t => {
  const { status, calls } = await traceRoute(t, 'build');
  assert.equal(status, 0);
  assert.deepEqual(calls, ['npm run docs:install', 'npm run build:ci']);
});

test('CI builds and checks documentation once without reinstalling dependencies', async t => {
  const { status, calls } = await traceRoute(t, 'build:ci');
  assert.equal(status, 0);
  assert.equal(calls.filter(call => call === 'npm run docs:check').length, 1);
  assert.ok(!calls.some(call => /docs:install|docs:build/.test(call)));
  for (const gate of ['npm run three:bundle', 'npm run i18n:check', 'node scripts/build-site.mjs', 'npm run visualizations:seo', 'npm run site:check']) {
    assert.ok(calls.includes(gate), `missing ${gate}`);
  }
  assert.ok(calls.indexOf('npm run docs:check') < calls.indexOf('node scripts/build-site.mjs'));
});

test('documentation check failure prevents later site construction', async t => {
  const { status, calls } = await traceRoute(t, 'build:ci', 'run docs:check');
  assert.equal(status, 9);
  assert.ok(!calls.includes('node scripts/build-site.mjs'));
  assert.ok(!calls.includes('npm run site:check'));
});
