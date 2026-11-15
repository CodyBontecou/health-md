#!/usr/bin/env node
// Harness-independent POSIX workflow. It intentionally has no authorization
// flag/environment bypass; approved opt-in work needs a trusted harness adapter.
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { parseArgs } from 'node:util';
import { createPlan, loadPlan, runVerification, verificationReport, inside } from './verification-workflow.mjs';
import { invocationDecision } from './verification-policy.mjs';

const help = `Task-scoped verification (Node 24+, Git, POSIX shell)
  plan --session ID --task TEXT --input PATH [--input PATH ...]
       --tier focused|affected|qualification --toolchain NAME [--toolchain NAME ...]
       --configuration TEXT [--reason TEXT] [--risk CLASS ...]
  run --session ID --command COMMAND [--cwd WORKTREE_RELATIVE_PATH]
      [--reuse] [--rerun-reason TEXT] [--timeout SECONDS]
  report --session ID [--not-run '[{"surface":"...","reason":"..."}]']
  check --session ID --command COMMAND [--tool bash]

PI_SESSION_ID is the session default. Inputs are files/directories, not globs;
include relevant dependencies, fixtures, tools/configuration and consumers.
check prints a JSON decision and exits 2 if blocked. This CLI never authorizes
simulator/emulator/device/Argent workflows. See docs/testing-strategy.md.
`;

try {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: {
    help: { type: 'boolean', short: 'h' }, session: { type: 'string' }, task: { type: 'string' },
    input: { type: 'string', multiple: true }, tier: { type: 'string' }, toolchain: { type: 'string', multiple: true },
    configuration: { type: 'string' }, reason: { type: 'string' }, risk: { type: 'string', multiple: true },
    command: { type: 'string' }, cwd: { type: 'string' }, tool: { type: 'string' }, reuse: { type: 'boolean' },
    'rerun-reason': { type: 'string' }, timeout: { type: 'string' }, 'not-run': { type: 'string' },
  } });
  const [action] = positionals;
  if (values.help || !action) {
    console.log(help);
  } else {
    if (positionals.length !== 1 || !['plan', 'run', 'check', 'report'].includes(action)) throw new Error('Choose plan, run, check or report; see --help.');
    const root = fs.realpathSync(execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim());
    const session = values.session ?? process.env.PI_SESSION_ID;
    if (!session) throw new Error('Choose a unique --session ID for this agent/task.');
    const notRun = values['not-run'] ? JSON.parse(values['not-run']) : undefined;
    if (notRun && (!Array.isArray(notRun) || notRun.some(gap => !gap.surface?.trim() || !gap.reason?.trim()))) throw new Error('Each unrun surface needs a surface and reason.');
    if (action === 'plan') {
      console.log(JSON.stringify(createPlan(root, session, { task: values.task, inputs: values.input, tier: values.tier, toolchains: values.toolchain, configuration: values.configuration, reason: values.reason, risk: values.risk, notRun }), null, 2));
    } else if (action === 'check') {
      let plan;
      try { plan = loadPlan(root, session); } catch (error) { if (error.code !== 'ENOENT') throw error; }
      if (!values.command?.trim()) throw new Error('check requires --command.');
      const decision = invocationDecision({ tool: values.tool ?? 'bash', input: { command: values.command }, cwd: inside(root, values.cwd ?? '.') }, plan);
      console.log(JSON.stringify(decision, null, 2));
      if (decision.block) process.exitCode = 2;
    } else {
      const plan = loadPlan(root, session);
      if (action === 'report') {
        console.log(JSON.stringify(verificationReport(root, session, plan, notRun), null, 2));
      } else {
        const timeoutSeconds = values.timeout === undefined ? 600 : Number(values.timeout);
        if (!Number.isFinite(timeoutSeconds) || timeoutSeconds < 1 || timeoutSeconds > 7200) throw new Error('Timeout must be 1–7200 seconds.');
        const result = await runVerification(root, session, plan, { command: values.command, cwd: values.cwd, reuse: values.reuse, rerunReason: values['rerun-reason'], timeoutSeconds }, { onOutput: (text, channel) => process[channel].write(text) });
        const { output: _output, ...receipt } = result;
        console.log(JSON.stringify(receipt, null, 2));
        if (result.status !== 'passed') process.exitCode = result.exitCode || 1;
      }
    }
  }
} catch (error) {
  console.error(`Verification blocked: ${error.message}`);
  process.exitCode = 2;
}
