#!/usr/bin/env node
import {
  ADMISSION_LEASE_SECONDS, DEDICATED_SLOW_BODY_ACCOUNTS, MAX_EXPORT_BYTES,
  MAX_REQUESTS_PER_ACCOUNT, SLOW_BODY_TIMEOUT_MS, SUSTAINED_REQUESTS_PER_ACCOUNT,
  buildSyntheticEnvelope, fragmentedRequestBody, nextEligibleAccount, parseStagingLoadConfig,
  percentile, readDistinctAccountTokens, requiredDistinctAccounts, stalledRequestBody, validRetryAfter,
} from "./staging-load-lib.mjs";

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

function fixed(value) { return Math.round(value * 10) / 10; }
function outcomeSummary(results) {
  const statusClasses = {};
  for (const result of results) statusClasses[result.outcome] = (statusClasses[result.outcome] ?? 0) + 1;
  const latencies = results.map((result) => result.durationMs);
  return {
    requests: results.length,
    statusClasses,
    latencyMs: {
      p50: percentile(latencies, 0.5), p95: percentile(latencies, 0.95),
      p99: percentile(latencies, 0.99), max: latencies.length ? Math.max(...latencies) : null,
    },
  };
}
function summary(results) {
  const accepted = results.filter((result) => result.accepted).length;
  return { ...outcomeSummary(results), accepted, failed: results.length - accepted };
}

async function upload(endpoint, token, body, { streamed = false, timeoutMs = 120_000 } = {}) {
  const started = performance.now();
  try {
    const request = {
      method: "POST",
      headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
      body,
      redirect: "error",
      signal: AbortSignal.timeout(timeoutMs),
      ...(streamed ? { duplex: "half" } : {}),
    };
    const response = await fetch(endpoint, request);
    let accepted = false;
    try {
      const value = await response.json();
      accepted = (response.status === 200 || response.status === 201) && value?.accepted === true;
    } catch { /* response bodies are deliberately never reported */ }
    return { accepted, outcome: `http_${response.status}`,
      retryAfterValid: validRetryAfter(response.headers.get("Retry-After")),
      durationMs: Math.round(performance.now() - started) };
  } catch (error) {
    return {
      accepted: false,
      outcome: error?.name === "TimeoutError" ? "timeout" : "transport_error",
      retryAfterValid: false,
      durationMs: Math.round(performance.now() - started),
    };
  }
}

async function verifyRevision(endpoint, expectedRevision) {
  const health = new URL("/health", endpoint);
  const response = await fetch(health, { redirect: "error", signal: AbortSignal.timeout(15_000) });
  let value = null;
  try { value = await response.json(); } catch { /* fixed failure below */ }
  if (!response.ok || value?.status !== "ok" || value?.revision !== expectedRevision.slice(0, 12)) {
    throw new Error("Staging health revision does not match the reviewed revision");
  }
}

async function runWave(config, tokens) {
  return Promise.all(Array.from({ length: config.concurrency }, (_, index) => upload(
    config.endpoint, tokens[Math.floor(index / 2)],
    buildSyntheticEnvelope(1_024, `synthetic-wave-${index}`),
  )));
}

async function runLarge(config, tokens) {
  return Promise.all(Array.from({ length: config.largeConcurrency }, (_, index) => {
    const body = buildSyntheticEnvelope(MAX_EXPORT_BYTES, `synthetic-large-${index}`);
    const streamed = index % 2 === 1;
    return upload(config.endpoint, tokens[index], streamed ? fragmentedRequestBody(body) : body, { streamed });
  }));
}

async function runSlowBodyAdmission(config, token) {
  const first = upload(config.endpoint, token, stalledRequestBody(),
    { streamed: true, timeoutMs: SLOW_BODY_TIMEOUT_MS });
  await sleep(1_000);
  const second = upload(config.endpoint, token, stalledRequestBody(),
    { streamed: true, timeoutMs: SLOW_BODY_TIMEOUT_MS });
  // Give both authenticated partial streams time to acquire their durable slots.
  await sleep(5_000);
  const backpressure = await upload(config.endpoint, token,
    buildSyntheticEnvelope(1_024, "synthetic-slow-body-backpressure"));
  const stalled = await Promise.all([first, second]);
  const recovery = await upload(config.endpoint, token,
    buildSyntheticEnvelope(1_024, "synthetic-slow-body-recovery"));
  const passed = stalled.every((result) => result.outcome === "http_408" && result.retryAfterValid) &&
    backpressure.outcome === "http_429" && backpressure.retryAfterValid && recovery.accepted;
  return { stalled, backpressure, recovery, passed };
}

async function runSustained(config, tokens) {
  const total = config.uploadsPerSecond * config.durationSeconds;
  const active = new Set();
  const activePerToken = Array(tokens.length).fill(0);
  const launchedPerToken = Array(tokens.length).fill(0);
  const results = [];
  let cursor = 0;
  const started = performance.now();
  for (let index = 0; index < total; index += 1) {
    const due = started + index * (1_000 / config.uploadsPerSecond);
    const delay = due - performance.now();
    if (delay > 0) await sleep(delay);
    while (active.size >= config.concurrency) await Promise.race(active);
    let tokenIndex = nextEligibleAccount(activePerToken, launchedPerToken, cursor);
    while (tokenIndex < 0) {
      if (active.size === 0) throw new Error("Synthetic scheduler exhausted account request budgets");
      await Promise.race(active);
      tokenIndex = nextEligibleAccount(activePerToken, launchedPerToken, cursor);
    }
    cursor = (tokenIndex + 1) % tokens.length;
    activePerToken[tokenIndex] += 1;
    launchedPerToken[tokenIndex] += 1;
    const operation = upload(config.endpoint, tokens[tokenIndex],
      buildSyntheticEnvelope(1_024, `synthetic-sustained-${index}`))
      .then((result) => { results.push(result); })
      .finally(() => { activePerToken[tokenIndex] -= 1; active.delete(operation); });
    active.add(operation);
  }
  const lastLaunchElapsedMs = performance.now() - started;
  await Promise.all(active);
  return {
    results,
    lastLaunchElapsedMs,
    maximumRequestsPerAccount: Math.max(...launchedPerToken),
  };
}

async function main() {
  const config = parseStagingLoadConfig();
  const needed = requiredDistinctAccounts(config);
  const tokens = readDistinctAccountTokens(process.env.HEALTHMD_LOAD_TOKEN_FILE, needed);
  const slowBodyToken = tokens.at(-1);
  if (!slowBodyToken) throw new Error("Dedicated slow-body account is unavailable");
  const workloadTokens = tokens.slice(0, -DEDICATED_SLOW_BODY_ACCOUNTS);
  await verifyRevision(config.endpoint, config.expectedRevision);
  const wave = await runWave(config, workloadTokens);
  const sustained = await runSustained(config, workloadTokens);
  const large = await runLarge(config, workloadTokens);
  const slowBody = await runSlowBodyAdmission(config, slowBodyToken);
  const achievedLaunchRate = sustained.results.length / (sustained.lastLaunchElapsedMs / 1_000);
  const report = {
    syntheticOnly: true,
    deployedRevision: config.expectedRevision.slice(0, 12),
    distinctAccounts: tokens.length,
    planned: {
      concurrency: config.concurrency,
      uploadsPerSecond: config.uploadsPerSecond,
      durationSeconds: config.durationSeconds,
      largeConcurrency: config.largeConcurrency,
      largePayloadBytes: MAX_EXPORT_BYTES,
      maximumRequestsPerAccount: MAX_REQUESTS_PER_ACCOUNT,
      maximumSustainedRequestsPerAccount: SUSTAINED_REQUESTS_PER_ACCOUNT,
      dedicatedSlowBodyAccounts: DEDICATED_SLOW_BODY_ACCOUNTS,
      admissionLeaseSeconds: ADMISSION_LEASE_SECONDS,
      largeRequestProfiles: { declaredLength: Math.ceil(config.largeConcurrency / 2),
        transferFragmented: Math.floor(config.largeConcurrency / 2) },
    },
    wave: summary(wave),
    sustained: { ...summary(sustained.results), achievedLaunchesPerSecond: fixed(achievedLaunchRate),
      maximumRequestsPerAccount: sustained.maximumRequestsPerAccount },
    worstCasePayload: summary(large),
    slowBodyAdmission: {
      expectedLeaseExpiries: outcomeSummary(slowBody.stalled),
      leaseExpiryRetryAfterValid: slowBody.stalled.every((result) => result.retryAfterValid),
      backpressureOutcome: slowBody.backpressure.outcome,
      backpressureRetryAfterValid: slowBody.backpressure.retryAfterValid,
      recoveryOutcome: slowBody.recovery.outcome,
      passed: slowBody.passed,
    },
  };
  report.pass = report.wave.failed === 0 && report.sustained.failed === 0 &&
    report.worstCasePayload.failed === 0 && report.slowBodyAdmission.passed &&
    achievedLaunchRate >= config.uploadsPerSecond * 0.98 &&
    sustained.maximumRequestsPerAccount <= SUSTAINED_REQUESTS_PER_ACCOUNT;
  console.log(JSON.stringify(report, null, 2));
  if (!report.pass) process.exitCode = 1;
}

main().catch(() => {
  console.error(JSON.stringify({ pass: false, syntheticOnly: true, error: "qualification_setup_failed" }));
  process.exitCode = 1;
});
