import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { test } from 'node:test';
import { createPlan, runVerification, verificationReport } from '../verification-workflow.mjs';

function repository(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'healthmd-verification-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  execFileSync('git', ['init', '-q', root]);
  fs.writeFileSync(path.join(root, '.gitignore'), '.pi/\n');
  fs.writeFileSync(path.join(root, 'AGENTS.md'), 'Read owner instructions; device QA is opt-in.\n');
  fs.mkdirSync(path.join(root, 'src'));
  fs.writeFileSync(path.join(root, 'src', 'owner.mjs'), 'export const value = 1;\n');
  return root;
}
const options = { task: 'Check guard workflow', inputs: ['src'], tier: 'focused', toolchains: ['node'], configuration: 'Host-only, default Node features' };

test('plans load instructions and unauthorized device commands never reach execution', async t => {
  const root = repository(t);
  const plan = createPlan(root, 'agent-one', options);
  assert.ok(plan.instructions.some(item => item.path === 'AGENTS.md' && item.content.includes('opt-in')));
  // Even a broken guard must never reach a real native executable in host QA.
  const bin = path.join(root, '.pi/native-stubs');
  fs.mkdirSync(bin, { recursive: true });
  const marker = path.join(root, '.pi/native-attempt');
  fs.writeFileSync(path.join(bin, 'xcrun'), `#!/bin/sh\nprintf attempted > '${marker}'\nexit 99\n`);
  fs.chmodSync(path.join(bin, 'xcrun'), 0o755);
  const originalPath = process.env.PATH;
  process.env.PATH = `${bin}${path.delimiter}${originalPath}`;
  t.after(() => { process.env.PATH = originalPath; });
  await assert.rejects(runVerification(root, 'agent-one', plan, { command: 'xcrun simctl boot ABC' }), /authorization/);
  assert.equal(fs.existsSync(marker), false);
  assert.throws(() => createPlan(root, 'agent-one', { ...options, inputs: ['../'] }), /inside/);
});

test('a reusable pass survives irrelevant edits but expires after edits, additions, deletions, or config changes', async t => {
  const root = repository(t);
  const plan = createPlan(root, 'agent-one', options);
  const command = `node -e 'require("node:fs").appendFileSync(".pi/executions", "run\\n")'`;
  const request = { command, reuse: true };
  assert.equal((await runVerification(root, 'agent-one', plan, request)).reused, false);
  fs.writeFileSync(path.join(root, 'unrelated.md'), 'Unrelated inputs do not expire a pass.');
  assert.equal((await runVerification(root, 'agent-one', plan, request)).reused, true);
  fs.writeFileSync(path.join(root, 'src', 'owner.mjs'), 'export const value = 2;\n');
  assert.equal((await runVerification(root, 'agent-one', plan, request)).reused, false);
  fs.writeFileSync(path.join(root, 'src', 'added.mjs'), 'export const extra = 1;\n');
  assert.equal((await runVerification(root, 'agent-one', plan, request)).reused, false);
  // Track a file first to ensure deleted tracked files invalidate evidence too.
  execFileSync('git', ['-C', root, 'add', 'src/added.mjs']);
  fs.unlinkSync(path.join(root, 'src', 'added.mjs'));
  assert.equal((await runVerification(root, 'agent-one', plan, request)).reused, false);
  const configured = createPlan(root, 'agent-one', { ...options, configuration: 'Different features' });
  assert.equal((await runVerification(root, 'agent-one', configured, request)).reused, false);
  assert.equal(fs.readFileSync(path.join(root, '.pi/executions'), 'utf8').split('\n').filter(Boolean).length, 5);
});

test('reused evidence is linked into a new plan report with explicit unrun surfaces', async t => {
  const root = repository(t);
  let plan = createPlan(root, 'agent-one', options);
  const request = { command: 'node --version', reuse: true };
  const original = await runVerification(root, 'agent-one', plan, request);
  plan = createPlan(root, 'agent-one', { ...options, task: 'Continue same verified behavior' });
  const replay = await runVerification(root, 'agent-one', plan, request);
  assert.equal(replay.reused, true);
  const report = verificationReport(root, 'agent-one', plan, [{ surface: 'iOS simulator', reason: 'Not requested' }]);
  assert.equal(report.checks.length, 1);
  assert.equal(report.checks[0].reusedFrom, original.id);
  assert.deepEqual(report.notRun, [{ surface: 'iOS simulator', reason: 'Not requested' }]);
});

test('a later failure cannot be hidden by replaying an earlier pass', async t => {
  const root = repository(t);
  const plan = createPlan(root, 'agent-one', options);
  const request = { command: 'node -e \'process.exit(require("node:fs").existsSync(".pi/fail") ? 7 : 0)\'' };
  assert.equal((await runVerification(root, 'agent-one', plan, request)).status, 'passed');
  fs.writeFileSync(path.join(root, '.pi/fail'), 'Inject a failing check outside the declared source.');
  assert.equal((await runVerification(root, 'agent-one', plan, request)).exitCode, 7);
  const third = await runVerification(root, 'agent-one', plan, { ...request, reuse: true });
  assert.equal(third.reused, false);
  assert.equal(third.status, 'failed');
});

test('checks that change their own inputs are recorded but not reusable', async t => {
  const root = repository(t);
  const plan = createPlan(root, 'agent-one', options);
  const receipt = await runVerification(root, 'agent-one', plan, { command: 'node -e \'require("node:fs").appendFileSync("src/owner.mjs", "// changed\\n")\'' });
  assert.equal(receipt.status, 'passed');
  assert.equal(receipt.reusable, false);
  assert.equal(verificationReport(root, 'agent-one', plan).checks[0].sourceCurrent, false);
});

test('explicitly selected ignored fixture directories are fingerprinted', async t => {
  const root = repository(t);
  fs.appendFileSync(path.join(root, '.gitignore'), 'generated-fixtures/\n');
  fs.mkdirSync(path.join(root, 'generated-fixtures'));
  const fixture = path.join(root, 'generated-fixtures/vector.json');
  fs.writeFileSync(fixture, '{"value": 1}');
  const plan = createPlan(root, 'agent-one', { ...options, inputs: ['src', 'generated-fixtures'] });
  const request = { command: 'node --version', reuse: true };
  await runVerification(root, 'agent-one', plan, request);
  fs.writeFileSync(fixture, '{"value": 2}');
  assert.equal((await runVerification(root, 'agent-one', plan, request)).reused, false);
});

test('owner instructions load and symlinked paths cannot escape the worktree', t => {
  const root = repository(t);
  fs.writeFileSync(path.join(root, 'src/AGENTS.md'), 'Use the focused owner test.');
  const plan = createPlan(root, 'agent-one', options);
  assert.ok(plan.instructions.some(item => item.path === 'src/AGENTS.md' && item.content.includes('focused')));
  fs.symlinkSync(os.tmpdir(), path.join(root, 'outside'));
  assert.throws(() => createPlan(root, 'agent-one', { ...options, inputs: ['outside'] }), /inside/);
});

test('pre-cancelled work never launches the command', async t => {
  const root = repository(t);
  const plan = createPlan(root, 'agent-one', options);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(runVerification(root, 'agent-one', plan, { command: 'node --version' }, { signal: controller.signal }), /cancel|abort/i);
});

test('post-check toolchain validation failure preserves exit evidence but disables reuse', async t => {
  const root = fs.realpathSync(repository(t));
  fs.mkdirSync(path.join(root, '.pi/tools'), { recursive: true });
  const version = path.join(root, '.pi/version');
  fs.writeFileSync(version, 'Python fixture version');
  const python = path.join(root, '.pi/tools/python3');
  fs.writeFileSync(python, `#!/bin/sh\n[ -f '${version}' ] || exit 1\nprintf 'Python fixture version\\n'\n`);
  fs.chmodSync(python, 0o755);
  const originalPath = process.env.PATH;
  process.env.PATH = `${path.dirname(python)}${path.delimiter}${originalPath}`;
  t.after(() => { process.env.PATH = originalPath; });
  const plan = createPlan(root, 'agent-one', { ...options, toolchains: ['node', 'python'] });
  const result = await runVerification(root, 'agent-one', plan, { command: `node -e 'require("node:fs").unlinkSync(${JSON.stringify(version)})'` });
  assert.equal(result.exitCode, 0);
  assert.equal(result.reusable, false);
  assert.match(result.validationError, /probe/);
});

test('toolchain receipts do not persist Java option environment echoes', async t => {
  const root = fs.realpathSync(repository(t));
  fs.mkdirSync(path.join(root, '.pi/tools'), { recursive: true });
  const java = path.join(root, '.pi/tools/java');
  fs.writeFileSync(java, '#!/bin/sh\nprintf \'Picked up JAVA_TOOL_OPTIONS: -Dpassword=synthetic-secret\\nopenjdk version "24"\\n\' >&2\n');
  fs.chmodSync(java, 0o755);
  const originalPath = process.env.PATH;
  process.env.PATH = `${path.dirname(java)}${path.delimiter}${originalPath}`;
  t.after(() => { process.env.PATH = originalPath; });
  const plan = createPlan(root, 'agent-one', { ...options, toolchains: ['node', 'java'] });
  const receipt = await runVerification(root, 'agent-one', plan, { command: 'node --version' });
  assert.equal(JSON.stringify(receipt).includes('synthetic-secret'), false);
  assert.match(receipt.toolchains.java.version, /openjdk/);
});
