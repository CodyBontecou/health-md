import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { invocationDecision } from './verification-policy.mjs';

const sha = data => createHash('sha256').update(data).digest('hex');
// Identify the loaded guard/runner implementation, even when it is not one of
// the product input paths declared by the agent.
const implementationIdentity = sha([import.meta.url, new URL('./verification-policy.mjs', import.meta.url)].map(url => fs.readFileSync(fileURLToPath(url), 'utf8')).join('\n'));
const probes = {
  node: ['node', '--version'], python: ['python3', '--version'],
  rust: ['rustc', '--version', '--verbose'], cargo: ['cargo', '--version'],
  swift: ['swift', '--version'], xcode: ['xcodebuild', '-version'],
  java: ['java', '-version'], make: ['make', '--version'], bash: ['/bin/bash', '--version'],
  actionlint: ['actionlint', '-version'], shellcheck: ['shellcheck', '--version'],
};
export const toolchainNames = Object.keys(probes);
const tiers = ['focused', 'affected', 'qualification'];
const risks = ['public-contract', 'security', 'persistence', 'ffi', 'platform', 'uncertain'];

export function inside(root, relative) {
  root = fs.realpathSync(root);
  const resolved = path.resolve(root, relative);
  if (resolved !== root && !resolved.startsWith(`${root}${path.sep}`)) throw new Error('Paths must stay inside the worktree.');
  // Resolve the closest existing ancestor as well: lexical containment alone
  // permits a symlinked directory to read or execute outside the worktree.
  let ancestor = resolved;
  while (!fs.existsSync(ancestor) && ancestor !== root) ancestor = path.dirname(ancestor);
  const real = fs.realpathSync(ancestor);
  if (real !== root && !real.startsWith(`${root}${path.sep}`)) throw new Error('Symlink target must stay inside the worktree.');
  return resolved;
}

function stateDirectory(root, session) {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(session)) throw new Error('Use a unique, filesystem-safe session ID.');
  return inside(root, `.pi/verification/${session}`);
}
function save(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.${randomUUID()}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, file);
}
function inventory(root, inputs) {
  const files = execFileSync('git', ['-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', ...inputs], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 }).split('\0').filter(Boolean);
  const visited = new Set();
  const walkIgnored = relative => {
    const target = inside(root, relative);
    const real = fs.realpathSync(target);
    if (visited.has(real)) return;
    visited.add(real);
    for (const name of fs.readdirSync(target)) {
      const child = path.join(relative, name);
      const resolved = inside(root, child);
      files.push(child);
      if (fs.statSync(resolved).isDirectory()) walkIgnored(child);
    }
  };
  for (const input of inputs) {
    const target = inside(root, input);
    files.push(input);
    if (fs.existsSync(target) && fs.statSync(target).isDirectory() && spawnSync('git', ['-C', root, 'check-ignore', '-q', '--', input]).status === 0) walkIgnored(input);
  }
  return [...new Set(files)].sort();
}
function instructions(root, inputs) {
  const owners = new Set(['AGENTS.md']);
  for (const input of inputs) {
    let directory = inside(root, input);
    if (!fs.existsSync(directory) || !fs.statSync(directory).isDirectory()) directory = path.dirname(directory);
    while (directory !== root) {
      const owner = path.join(directory, 'AGENTS.md');
      if (fs.existsSync(owner)) owners.add(path.relative(root, owner));
      directory = path.dirname(directory);
    }
  }
  // A scope spanning several owners needs their instructions, not just the
  // ancestor's. The guide is returned too, so the plan tool loads the workflow.
  for (const file of inventory(root, inputs)) if (path.basename(file) === 'AGENTS.md') owners.add(file);
  if (fs.existsSync(path.join(root, 'docs/testing-strategy.md'))) owners.add('docs/testing-strategy.md');
  return [...owners].sort().filter(file => fs.existsSync(inside(root, file)))
    .map(file => ({ path: file, content: fs.readFileSync(inside(root, file), 'utf8') }));
}

export function createPlan(root, session, options) {
  root = fs.realpathSync(root);
  const { task, inputs, tier, toolchains, configuration, reason = '', notRun = [], risk = [] } = options;
  if (!task?.trim() || !configuration?.trim() || !inputs?.length || !toolchains?.length || !tiers.includes(tier)) throw new Error('Plan requires task, inputs, tier, toolchains, and configuration.');
  if (toolchains.some(name => !probes[name]) || risk.some(name => !risks.includes(name))) throw new Error('Unknown toolchain or risk classification.');
  const normalized = [...new Set(inputs.map(input => path.relative(root, inside(root, input)) || '.'))];
  if (normalized.some(input => input === '.pi' || input.startsWith('.pi/verification'))) throw new Error('Verification state is not a source input.');
  const loaded = instructions(root, normalized);
  const plan = { version: 1, id: randomUUID(), root, session, task: task.trim(), inputs: normalized, tier, toolchains: [...new Set(['node', 'bash', ...toolchains])], configuration, reason, risk, notRun, instructionPaths: loaded.map(item => item.path) };
  save(path.join(stateDirectory(root, session), 'plan.json'), plan);
  return { ...plan, instructions: loaded };
}
export function loadPlan(root, session) {
  root = fs.realpathSync(root);
  const plan = JSON.parse(fs.readFileSync(path.join(stateDirectory(root, session), 'plan.json'), 'utf8'));
  if (plan.version !== 1 || plan.root !== root || plan.session !== session) throw new Error('Plan does not match this worktree/session.');
  return plan;
}

export function fingerprint(root, plan) {
  const files = inventory(root, [...plan.inputs, ...plan.instructionPaths]);
  const entries = files.map(file => {
    const target = inside(root, file);
    try {
      const stat = fs.lstatSync(target);
      return [file, stat.mode & 0o777, stat.isSymbolicLink() ? fs.readlinkSync(target) : null,
        fs.statSync(target).isDirectory() ? 'directory' : sha(fs.readFileSync(target))];
    } catch (error) {
      if (error.code === 'ENOENT') return [file, 'missing'];
      throw error;
    }
  });
  return { digest: sha(JSON.stringify(entries)), files: entries.length };
}
function toolchainIdentity(plan, env) {
  return Object.fromEntries(plan.toolchains.map(name => {
    const [program, ...args] = probes[name];
    const executable = (env.PATH ?? '').split(path.delimiter).map(directory => path.resolve(directory, program)).find(file => {
      try { fs.accessSync(file, fs.constants.X_OK); return fs.statSync(file).isFile(); } catch { return false; }
    });
    if (!executable) throw new Error(`Toolchain probe unavailable: ${program}.`);
    const result = spawnSync(executable, args, { env, encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024 });
    if (result.error || result.status !== 0) throw new Error(`Toolchain probe failed: ${program} ${args.join(' ')}.`);
    const output = `${result.stdout}${result.stderr}`.trim();
    // Java prints inherited option values before its version. They can contain
    // proxy credentials; retain only a digest of those echoes in the identity.
    const version = output.split('\n').filter(line => !/^(?:Picked up|NOTE: Picked up) (?:JAVA_TOOL_OPTIONS|_JAVA_OPTIONS|JDK_JAVA_OPTIONS):/.test(line)).join('\n');
    return [name, { executable: fs.realpathSync(executable), version, outputDigest: sha(output) }];
  }));
}
function receipts(root, session) {
  const directory = path.join(stateDirectory(root, session), 'receipts');
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory).filter(file => file.endsWith('.json')).sort()
    .map(file => JSON.parse(fs.readFileSync(path.join(directory, file), 'utf8')))
    .sort((a, b) => a.completedAt.localeCompare(b.completedAt) || a.startedAt.localeCompare(b.startedAt));
}
function context(root, plan, invocation, cwd, env) {
  const source = fingerprint(root, plan);
  const toolchains = toolchainIdentity(plan, env);
  const environmentDigest = sha(JSON.stringify(Object.entries(env).sort(([a], [b]) => a.localeCompare(b))));
  const key = sha(JSON.stringify({ invocation, cwd, source, toolchains, environmentDigest, implementationIdentity, inputs: plan.inputs, configuration: plan.configuration, tier: plan.tier }));
  return { key, source, toolchains, environmentDigest, implementationIdentity };
}
function persistReceipt(root, session, receipt) {
  receipt.completedAt = new Date().toISOString();
  const file = path.join(stateDirectory(root, session), 'receipts', `${receipt.id}.json`);
  save(file, receipt);
  return { ...receipt, receiptPath: file };
}

// The only approval argument is supplied by a trusted adapter after a one-shot
// human action. The portable CLI and model-facing schema cannot set it.
export async function runVerification(root, session, plan, request, { approved = false, signal, onOutput } = {}) {
  root = fs.realpathSync(root);
  const { command, cwd: requestedCwd = '.', reuse = false, rerunReason = '' } = request;
  if (!command?.trim()) throw new Error('Provide a verification command.');
  if (signal?.aborted) throw new Error('Verification cancelled before execution.');
  if (!plan || plan.root !== root || plan.session !== session) throw new Error('Choose a verification plan for this worktree/session.');
  const cwd = inside(root, requestedCwd);
  const invocation = { tool: 'bash', input: { command }, cwd };
  const decision = invocationDecision(invocation, plan, { approved });
  if (decision.block) throw new Error(decision.block);
  const env = { ...process.env, PWD: cwd };
  const before = context(root, plan, invocation, cwd, env);
  const latest = receipts(root, session).findLast(receipt => receipt.key === before.key);
  const match = latest?.status === 'passed' && latest.reusable ? latest : undefined;
  if (reuse && match) return persistReceipt(root, session, {
    ...match, id: randomUUID(), planId: plan.id, task: plan.task,
    reused: true, reusedFrom: match.id, warnings: decision.warnings,
  });
  const warnings = [...decision.warnings];
  if (match && !rerunReason.trim()) warnings.push('An unchanged passing receipt exists. Reuse it or record why repetition is needed.');
  for (const warning of warnings) onOutput?.(`[verification warning] ${warning}\n`, 'stderr');
  const startedAt = new Date().toISOString(), start = performance.now();
  let output = '';
  const result = await new Promise(resolve => {
    const child = spawn('/bin/bash', ['-o', 'pipefail', '-c', command], { cwd, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let killTimer;
    const stop = () => {
      try { process.kill(-child.pid, 'SIGTERM'); } catch {}
      killTimer ??= setTimeout(() => { try { process.kill(-child.pid, 'SIGKILL'); } catch {} }, 2000);
    };
    const timeout = setTimeout(stop, (request.timeoutSeconds ?? 600) * 1000);
    signal?.addEventListener('abort', stop, { once: true });
    if (signal?.aborted) stop();
    for (const [stream, channel] of [[child.stdout, 'stdout'], [child.stderr, 'stderr']]) stream.on('data', data => {
      const text = data.toString();
      output = (output + text).slice(-20000);
      onOutput?.(text, channel);
    });
    child.on('error', error => { output += error.message; });
    child.on('close', (code, killedBy) => {
      clearTimeout(timeout); clearTimeout(killTimer); signal?.removeEventListener('abort', stop);
      resolve({ exitCode: code, signal: killedBy });
    });
  });
  let after, validationError;
  try { after = context(root, plan, invocation, cwd, env); } catch (error) {
    validationError = error.message;
    let source;
    try { source = fingerprint(root, plan); } catch { source = { digest: 'unavailable', files: 0 }; }
    after = { source, key: null };
    warnings.push(`Post-check validation unavailable: ${validationError}. Receipt is not reusable.`);
  }
  const receipt = persistReceipt(root, session, {
    version: 1, id: randomUUID(), planId: plan.id, task: plan.task, tier: plan.tier,
    command, cwd: path.relative(root, cwd) || '.', inputs: plan.inputs, configuration: plan.configuration,
    ...before, after: after.source, startedAt, durationMs: Math.round(performance.now() - start), ...result,
    status: result.exitCode === 0 ? 'passed' : 'failed', reusable: result.exitCode === 0 && before.key === after.key,
    validationError, rerunReason, warnings, optIn: decision.optIn, authorization: decision.optIn.length ? 'one-shot human approval' : 'not required',
  });
  return { ...receipt, output, reused: false };
}

// Raw tool observation is useful evidence, but without runner-owned exit and
// shell semantics it is not eligible for automatic reuse.
export function beginObservation(root, session, plan, invocation) {
  return { root, session, plan, invocation, source: fingerprint(root, plan), startedAt: new Date().toISOString(), start: performance.now() };
}
export function finishObservation(observation, isError) {
  const { root, session, plan, invocation, source, startedAt, start } = observation;
  return persistReceipt(root, session, {
    version: 1, id: randomUUID(), planId: plan.id, task: plan.task, tier: plan.tier,
    command: /(?:^|[._/])(?:bash|powershell|exec_command)$/.test(invocation.tool) ? invocation.input.command : invocation.tool,
    argumentDigest: sha(JSON.stringify(invocation.input)), inputs: plan.inputs,
    source, after: fingerprint(root, plan), configuration: plan.configuration,
    startedAt, durationMs: Math.round(performance.now() - start), status: isError ? 'failed' : 'completed', reusable: false,
    note: 'Observed tool result; use verification_run for exit-code/toolchain-checked reusable evidence.',
  });
}
export function verificationReport(root, session, plan, notRun = plan.notRun) {
  const source = fingerprint(root, plan);
  const checks = receipts(root, session).filter(receipt => receipt.planId === plan.id).map(receipt => ({
    ...receipt, sourceCurrent: receipt.after.digest === source.digest && receipt.source.digest === source.digest,
  }));
  const report = { version: 1, task: plan.task, planId: plan.id, tier: plan.tier, risk: plan.risk, inputs: plan.inputs, source, checks, notRun,
    caveat: 'Declared scope must include all affected inputs/consumers. Source-current is not full toolchain/config validation or release qualification.' };
  const reportPath = path.join(stateDirectory(root, session), 'report.json');
  save(reportPath, report);
  return { ...report, reportPath };
}
