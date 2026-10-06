import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const script = fileURLToPath(new URL('../verification.mjs', import.meta.url));
const repositoryRoot = path.resolve(path.dirname(script), '..');
test('portable workflow creates plans and receipts but exposes no self-authorization bypass', t => {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'healthmd-verification-cli-')));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  execFileSync('git', ['init', '-q', root]);
  fs.writeFileSync(path.join(root, '.gitignore'), '.pi/\n');
  fs.writeFileSync(path.join(root, 'AGENTS.md'), 'Read owner instructions.');
  fs.writeFileSync(path.join(root, 'source.mjs'), 'export const value = 1;');
  const bin = path.join(root, '.pi/native-stubs');
  fs.mkdirSync(bin, { recursive: true });
  const marker = path.join(root, '.pi/native-attempt');
  fs.writeFileSync(path.join(bin, 'xcrun'), `#!/bin/sh\nprintf attempted > '${marker}'\nexit 99\n`);
  fs.chmodSync(path.join(bin, 'xcrun'), 0o755);
  const cli = (...args) => spawnSync(process.execPath, [script, ...args, '--session', 'portable-agent'], { cwd: root, env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}` }, encoding: 'utf8' });
  const command = 'node --version';
  assert.notEqual(cli('run', '--command', command).status, 0);
  const plan = cli('plan', '--task', 'Host guard regression', '--input', 'source.mjs', '--tier', 'focused', '--toolchain', 'node', '--configuration', 'Default Node features');
  assert.equal(plan.status, 0, plan.stderr);
  assert.ok(JSON.parse(plan.stdout).instructions.some(item => item.path === 'AGENTS.md'));
  assert.equal(cli('run', '--command', command).status, 0);
  const report = cli('report', '--not-run', JSON.stringify([{ surface: 'Device QA', reason: 'Not requested' }]));
  assert.equal(report.status, 0, report.stderr);
  assert.equal(JSON.parse(report.stdout).checks[0].status, 'passed');
  const blocked = cli('run', '--command', 'xcrun simctl boot ABC');
  assert.equal(blocked.status, 2);
  assert.match(blocked.stderr, /authorization/);
  assert.equal(cli('run', '--command', 'xcrun simctl boot ABC', '--approved').status, 2);
  assert.equal(fs.existsSync(marker), false);
  assert.equal(cli('check', '--command', 'rg "xcrun simctl boot" docs').status, 0);
  assert.notEqual(cli('check', '--command', 'make apple-ios').status, 0);
});

test('only the reviewed extension escapes the agent-state ignore rule', () => {
  const result = spawnSync('git', ['check-ignore', '.pi/extensions/verification-guard.ts', '.pi/extensions/private.ts', '.pi/verification/session/report.json', '.pi/todos/task.md'], { cwd: repositoryRoot, encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.deepEqual(result.stdout.trim().split('\n'), ['.pi/extensions/private.ts', '.pi/verification/session/report.json', '.pi/todos/task.md']);
});

test('component-directory launcher explicitly loads the guard without changing cwd or caller flags', t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'healthmd-pi-launcher-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const log = path.join(directory, 'arguments');
  fs.writeFileSync(path.join(directory, 'pi'), '#!/bin/sh\nprintf "%s\\n" "$PWD" "$@" > "$PI_GUARD_LOG"\n');
  fs.chmodSync(path.join(directory, 'pi'), 0o755);
  const result = spawnSync('bash', [path.join(repositoryRoot, 'scripts/agent-pi.sh'), '--offline', '--no-mcp', '--help'], { cwd: directory, env: { ...process.env, PATH: `${directory}${path.delimiter}${process.env.PATH}`, PI_GUARD_LOG: log }, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const args = fs.readFileSync(log, 'utf8').trim().split('\n');
  assert.equal(fs.realpathSync(args[0]), fs.realpathSync(directory));
  assert.deepEqual(args.slice(1), ['--extension', path.join(repositoryRoot, '.pi/extensions/verification-guard.ts'), '--offline', '--no-mcp', '--help']);
});
