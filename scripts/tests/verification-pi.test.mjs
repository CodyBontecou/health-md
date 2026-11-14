import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { test } from 'node:test';
import extension from '../../.pi/extensions/verification-guard.ts';

function harness(t) {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'healthmd-pi-guard-')));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  execFileSync('git', ['init', '-q', root]);
  fs.writeFileSync(path.join(root, '.gitignore'), '.pi/\n');
  fs.writeFileSync(path.join(root, 'AGENTS.md'), 'Task-scoped QA policy.');
  fs.mkdirSync(path.join(root, 'src'));
  fs.writeFileSync(path.join(root, 'src/owner.mjs'), 'export const value = 1;');
  const events = new Map(), tools = new Map(), commands = new Map(), entries = [], notices = [];
  const pi = {
    on: (name, handler) => events.set(name, handler),
    registerTool: tool => tools.set(tool.name, tool),
    registerCommand: (name, command) => commands.set(name, command),
    appendEntry: (customType, data) => entries.push({ type: 'custom', customType, data }),
    getAllTools: () => [],
    sendMessage: message => notices.push(message.content),
  };
  const ctx = { cwd: root, hasUI: true, mode: 'tui', sessionManager: { getSessionId: () => 'agent-one', getBranch: () => entries }, ui: { notify: message => notices.push(message), confirm: async () => true, setStatus: () => {} } };
  // Entry accepts its real root by default; the test uses an isolated repository
  // at the OS boundary rather than editing this worktree or starting Pi/models.
  extension(pi, root);
  const emit = (name, event = {}) => events.get(name)?.(event, ctx);
  const plan = () => tools.get('verification_plan').execute('plan-call', { task: 'Guard workflow', inputs: ['src'], tier: 'focused', toolchains: ['node'], configuration: 'Host only' }, undefined, undefined, ctx);
  return { root, pi, ctx, emit, plan, tools, commands, entries, notices };
}

test('Pi guard requires plans and a human-only one-shot approval for an exact request', async t => {
  const h = harness(t);
  const call = { toolName: 'bash', toolCallId: 'device-call', input: { command: 'xcrun simctl boot ABC' } };
  assert.match((await h.emit('tool_call', call)).reason, /plan/);
  await h.plan();
  const blocked = await h.emit('tool_call', call);
  assert.equal(blocked.block, true);
  const approval = blocked.reason.match(/\/verification-allow ([a-f0-9-]+)/)[1];
  assert.equal(h.tools.has('verification_allow'), false, 'The model must not be able to grant itself permission.');
  await h.commands.get('verification-allow').handler(approval, h.ctx);
  const changed = { ...call, input: { command: 'xcrun simctl boot DIFFERENT' } };
  assert.equal((await h.emit('tool_call', changed)).block, true);
  assert.equal(await h.emit('tool_call', call), undefined);
  assert.equal((await h.emit('tool_call', call)).block, true, 'Permission is consumed once.');
});

test('authorization expires and is never restored by a new plan, branch, or reload', async t => {
  const h = harness(t);
  await h.plan();
  const call = { toolName: 'mcp__argent__list_devices', toolCallId: 'argent-call', input: {} };
  const allow = async () => {
    const blocked = await h.emit('tool_call', call);
    await h.commands.get('verification-allow').handler(blocked.reason.match(/\/verification-allow ([a-f0-9-]+)/)[1], h.ctx);
  };
  await allow();
  await h.plan();
  assert.equal((await h.emit('tool_call', call)).block, true);
  await allow();
  await h.emit('session_tree');
  assert.equal((await h.emit('tool_call', call)).block, true);
  await allow();
  await h.emit('session_start');
  assert.equal((await h.emit('tool_call', call)).block, true);
  await allow();
  const now = Date.now();
  t.mock.method(Date, 'now', () => now + 11 * 60 * 1000);
  assert.equal((await h.emit('tool_call', call)).block, true);
});

test('print/RPC without confirmation UI cannot authorize a request', async t => {
  const h = harness(t);
  await h.plan();
  h.ctx.hasUI = false; h.ctx.mode = 'print';
  const call = { toolName: 'mcp__argent__list_devices', toolCallId: 'argent-call', input: {} };
  const blocked = await h.emit('tool_call', call);
  await h.commands.get('verification-allow').handler(blocked.reason.match(/\/verification-allow ([a-f0-9-]+)/)[1], h.ctx);
  assert.equal((await h.emit('tool_call', call)).block, true);
});

test('raw checks warn on unexplained breadth, and automatic completion preserves their receipts', async t => {
  const h = harness(t);
  await h.plan();
  const call = { toolName: 'bash', toolCallId: 'host-call', input: { command: 'make test-all' } };
  assert.equal(await h.emit('tool_call', call), undefined);
  assert.ok(h.notices.some(notice => /no recorded reason/.test(notice)), 'Warn before starting the broad check.');
  const result = await h.emit('tool_result', { ...call, content: [{ type: 'text', text: 'Check completed' }], isError: false });
  assert.ok(result.content.some(item => /no recorded reason/.test(item.text)));
  await h.emit('agent_end');
  const report = JSON.parse(fs.readFileSync(path.join(h.root, '.pi/verification/agent-one/report.json'), 'utf8'));
  assert.equal(report.checks.length, 1);
  assert.equal(report.checks[0].status, 'completed');
  assert.equal(report.checks[0].reusable, false);
});

test('model-facing runner records real exit status without any approval input', async t => {
  const h = harness(t);
  await h.plan();
  const tool = h.tools.get('verification_run');
  assert.equal(tool.parameters.additionalProperties, false);
  assert.equal(tool.parameters.properties.approved, undefined);
  const call = { toolName: 'verification_run', toolCallId: 'run-call', input: { command: 'node -e "process.exit(9)"' } };
  assert.equal(await h.emit('tool_call', call), undefined);
  const result = await tool.execute(call.toolCallId, call.input, undefined, undefined, h.ctx);
  assert.equal(result.isError, true);
  assert.equal(result.details.exitCode, 9);
});

test('completion records a blocked opt-in surface even if the agent omits its manual gap', async t => {
  const h = harness(t);
  await h.plan();
  await h.emit('tool_call', { toolName: 'mcp__argent__list_devices', toolCallId: 'blocked-call', input: {} });
  await h.emit('agent_end');
  const report = JSON.parse(fs.readFileSync(path.join(h.root, '.pi/verification/agent-one/report.json'), 'utf8'));
  assert.ok(report.notRun.some(gap => /Argent/.test(gap.surface) && /blocked|not executed/.test(gap.reason)));
});
