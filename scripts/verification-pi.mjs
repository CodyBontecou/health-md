import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { invocationDecision } from './verification-policy.mjs';
import { createPlan, runVerification, beginObservation, finishObservation, verificationReport, toolchainNames, inside } from './verification-workflow.mjs';

const stateType = 'healthmd.verification.plan';
const jsonResult = data => ({ content: [{ type: 'text', text: JSON.stringify(data, null, 2) }], details: data });
const array = items => ({ type: 'array', items });
const text = { type: 'string', minLength: 1 };
const gapSchema = array({ type: 'object', properties: { surface: text, reason: text }, required: ['surface', 'reason'], additionalProperties: false });
function schema(properties, required = []) { return { type: 'object', properties, required, additionalProperties: false }; }
const key = invocation => createHash('sha256').update(JSON.stringify(invocation)).digest('hex');

// Runtime registration has no startup processes/timers. Approvals deliberately
// live only in memory, outside the plan/receipt JSON and session transcript.
export function installVerificationGuard(pi, requestedRoot) {
  const root = fs.realpathSync(requestedRoot);
  let plan;
  const pending = new Map(), grants = new Map(), approvedCalls = new Set(), observations = new Map();
  const active = ctx => {
    const cwd = fs.realpathSync(ctx.cwd);
    return cwd === root || cwd.startsWith(`${root}${path.sep}`);
  };
  const session = ctx => ctx.sessionManager.getSessionId();
  const resetApproval = () => { pending.clear(); grants.clear(); approvedCalls.clear(); };
  const persistPlan = () => pi.appendEntry(stateType, { ...plan, instructions: undefined });
  const reportFor = ctx => verificationReport(root, session(ctx), plan, [
    ...plan.notRun,
    ...[...pending.values()].filter(request => request.planId === plan.id).map(request => ({
      surface: request.surface, reason: 'Proposed opt-in workflow was blocked or not executed; no verification evidence.',
    })),
  ]);
  const restore = (_event, ctx) => {
    resetApproval(); observations.clear(); plan = undefined;
    if (!active(ctx)) return;
    const candidate = ctx.sessionManager.getBranch().filter(entry => entry.type === 'custom' && entry.customType === stateType).at(-1)?.data;
    if (candidate?.version === 1 && candidate.root === root && candidate.session === session(ctx)) plan = candidate;
    if (ctx.hasUI) ctx.ui.setStatus('verification', 'verification guard: active');
  };
  const requestApproval = (invocation, ctx, surface) => {
    const invocationKey = key(invocation);
    const existing = [...pending.values()].find(request => request.key === invocationKey && request.planId === plan.id && request.expires > Date.now());
    if (existing) return existing;
    if (pending.size >= 16) pending.delete(pending.keys().next().value);
    const request = { id: randomUUID(), invocation, key: invocationKey, planId: plan.id, session: session(ctx), expires: Date.now() + 10 * 60 * 1000,
      surface: `${invocation.tool}: ${surface.join(', ')}` };
    pending.set(request.id, request);
    return request;
  };

  pi.registerTool({
    name: 'verification_plan', label: 'Verification plan',
    description: 'Before checks, declare this task, relevant source/dependency/fixture paths, tier, toolchains and configuration. Loads root/owner instructions and the canonical guide. Update scope after relevant changes; a new plan revokes all approvals. Include affected consumers for contract/security/persistence/FFI/platform/uncertain changes.',
    parameters: schema({
      task: text, inputs: array(text), tier: { enum: ['focused', 'affected', 'qualification'], type: 'string' },
      toolchains: array({ enum: toolchainNames, type: 'string' }), configuration: text,
      reason: { type: 'string' }, risk: array({ enum: ['public-contract', 'security', 'persistence', 'ffi', 'platform', 'uncertain'], type: 'string' }), notRun: gapSchema,
    }, ['task', 'inputs', 'tier', 'toolchains', 'configuration']),
    async execute(_id, args, _signal, _onUpdate, ctx) {
      if (!active(ctx)) throw new Error('Verification tools apply only to this worktree.');
      plan = createPlan(root, session(ctx), args);
      resetApproval(); persistPlan();
      return jsonResult(plan);
    },
  });
  pi.registerTool({
    name: 'verification_run', label: 'Scoped verification',
    description: 'Run a check under the current plan. Records input/toolchain/environment fingerprints, configuration, duration and actual exit code. Set reuse=true only after reviewing scope completeness; failures and changed inputs never replay. Reruns of unchanged passes warn unless rerunReason is recorded. cwd is worktree-relative. Device/Argent opt-in cannot be self-granted.',
    parameters: schema({ command: text, cwd: { type: 'string' }, reuse: { type: 'boolean' }, rerunReason: { type: 'string' }, timeoutSeconds: { type: 'number', minimum: 1, maximum: 7200 } }, ['command']),
    async execute(id, args, signal, _onUpdate, ctx) {
      if (!active(ctx) || !plan) throw new Error('Choose a verification plan first.');
      const approved = approvedCalls.delete(id);
      const result = await runVerification(root, session(ctx), plan, args, { approved, signal });
      return { ...jsonResult(result), isError: result.status === 'failed' };
    },
  });
  pi.registerTool({
    name: 'verification_report', label: 'Verification receipt',
    description: 'Before finishing, collect this plan’s receipts and record every relevant unrun/blocked surface with its reason. A source-current receipt is not proof of complete consumer coverage or release qualification.',
    parameters: schema({ notRun: gapSchema }),
    async execute(_id, args, _signal, _onUpdate, ctx) {
      if (!active(ctx) || !plan) throw new Error('Choose a verification plan first.');
      if (args.notRun) { plan.notRun = args.notRun; persistPlan(); }
      return jsonResult(reportFor(ctx));
    },
  });
  pi.registerCommand('verification-allow', {
    description: 'Explicitly approve ONE pending exact workflow for the displayed task; expires in 10 minutes, never persisted.',
    async handler(id, ctx) {
      const request = pending.get(id.trim());
      if (!active(ctx) || !ctx.hasUI || !request || request.planId !== plan?.id || request.session !== session(ctx) || request.expires <= Date.now()) {
        ctx.ui.notify('No current pending request. Re-propose the workflow; authorization is never inferred or restored.', 'warning');
        return;
      }
      if (!(await ctx.ui.confirm(`Authorize one workflow for: ${plan.task}`, JSON.stringify(request.invocation, null, 2)))) return;
      grants.set(request.key, request);
      ctx.ui.notify('One exact request authorized. Ask the agent to continue; changed requests need new approval.', 'info');
    },
  });
  pi.registerCommand('verification-status', {
    description: 'Show guard activation, task and current verification receipt path.',
    async handler(_args, ctx) {
      if (!active(ctx) || !plan) { ctx.ui.notify('Verification guard active; no task plan yet.', 'info'); return; }
      const report = reportFor(ctx);
      ctx.ui.notify(`${plan.task}: ${report.checks.length} receipt(s)\n${report.reportPath}`, 'info');
    },
  });

  pi.on('session_start', restore);
  pi.on('session_tree', restore);
  pi.on('session_before_switch', resetApproval);
  pi.on('session_before_fork', resetApproval);
  pi.on('session_shutdown', () => { resetApproval(); observations.clear(); plan = undefined; });
  pi.on('before_agent_start', (_event, ctx) => {
    if (!active(ctx)) return;
    return { message: { customType: 'healthmd.verification.workflow', display: false,
      content: `Verification guard active. For a new task choose verification_plan before tests/lint; its result loads root/owner instructions and docs/testing-strategy.md. Prefer verification_run for reusable receipts. Keep input scope complete, including dependencies, fixtures and affected consumers; escalate contract/security/persistence/FFI/platform/uncertain impact. Finish with verification_report and report its gaps. Broad qualification needs a reason. Known device/Argent workflows require human /verification-allow for one exact request; never infer approval from implementation requests. Current plan: ${plan?.task ?? 'none'}.` } };
  });
  pi.on('tool_call', (event, ctx) => {
    if (!active(ctx) || ['verification_plan', 'verification_report'].includes(event.toolName)) return;
    const namespace = pi.getAllTools().find(tool => tool.name === event.toolName)?.namespace?.name ?? '';
    const invocation = { tool: event.toolName, input: event.input, namespace };
    const assessed = { ...invocation, tool: event.toolName === 'verification_run' ? 'bash' : event.toolName,
      cwd: event.toolName === 'verification_run' ? inside(root, event.input.cwd ?? '.') : ctx.cwd };
    const grant = grants.get(key(invocation));
    const approved = !!(grant && grant.planId === plan?.id && grant.session === session(ctx) && grant.expires > Date.now());
    const decision = invocationDecision(assessed, plan, { approved });
    if (event.toolName === 'verification_run' && !plan) return { block: true, reason: 'Choose verification_plan before checks.' };
    if (decision.block) {
      if (decision.optIn.length && plan) {
        const request = requestApproval(invocation, ctx, decision.optIn);
        return { block: true, reason: `${decision.block}\nTask: ${plan.task}\nProposed: ${JSON.stringify(invocation)}\nThe user can explicitly approve ONE request with /verification-allow ${request.id}. Otherwise record it as not run. Approval expires after 10 minutes and is revoked on plan/session/branch changes.` };
      }
      return { block: true, reason: `${decision.block} Use verification_plan; then verification_run.` };
    }
    if (decision.warnings.length) pi.sendMessage({ customType: 'healthmd.verification.warning', content: decision.warnings.join('\n'), display: true }, { triggerTurn: false });
    if (approved) {
      grants.delete(grant.key); pending.delete(grant.id);
      if (event.toolName === 'verification_run') approvedCalls.add(event.toolCallId);
    }
    if (decision.verification && event.toolName !== 'verification_run') {
      observations.set(event.toolCallId, { ...beginObservation(root, session(ctx), plan, invocation), warnings: decision.warnings });
    }
  });
  pi.on('tool_result', (event) => {
    approvedCalls.delete(event.toolCallId);
    const observation = observations.get(event.toolCallId);
    if (!observation) return;
    observations.delete(event.toolCallId);
    const receipt = finishObservation(observation, event.isError);
    return { content: [...event.content, { type: 'text', text: `${observation.warnings.join('\n')}\nObserved verification receipt: ${receipt.receiptPath} (${receipt.status}; not automatically reusable).` }],
      ...(event.structuredContent === undefined ? {} : { structuredContent: event.structuredContent }) };
  });
  pi.on('agent_end', (_event, ctx) => {
    // Pending blocked requests remain so a human can approve after the agent
    // asks. Unused grants do not carry into another agent activity.
    grants.clear(); approvedCalls.clear();
    if (!active(ctx) || !plan) return;
    const report = reportFor(ctx);
    if (ctx.hasUI) ctx.ui.notify(`Verification receipt: ${report.reportPath}`, 'info');
  });
}
