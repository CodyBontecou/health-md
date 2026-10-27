import { afterEach, expect, it } from "vitest";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  ADMISSION_LEASE_SECONDS, BURST_DURATION_SECONDS, DEDICATED_SLOW_BODY_ACCOUNTS, MAX_EXPORT_BYTES,
  MAX_REQUESTS_PER_ACCOUNT, PACED_REQUESTS_PER_ACCOUNT, SLOW_BODY_TIMEOUT_MS,
  TWO_X_BURST_UPLOADS_PER_SECOND,
  buildSyntheticEnvelope, fragmentedRequestBody, nextEligibleAccount, parseStagingLoadConfig,
  percentile, readDistinctAccountTokens, recordAccountRequest, requiredDistinctAccounts,
  stalledRequestBody, validRetryAfter,
} from "../scripts/staging-load-lib.mjs";

const roots: string[] = [];
const base = {
  HEALTHMD_LOAD_CONFIRM_SYNTHETIC_ONLY: "SYNTHETIC_ONLY",
  HEALTHMD_LOAD_DISTINCT_ACCOUNTS: "YES",
  HEALTHMD_LOAD_ENDPOINT: "https://api.staging.example.test/api/v1/exports",
  HEALTHMD_LOAD_EXPECTED_REVISION: "a".repeat(40),
};
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

it("defaults to the documented 2x gate and calculates a budget-safe account count", () => {
  const config = parseStagingLoadConfig(base);
  expect(config).toMatchObject({
    concurrency: 500, uploadsPerSecond: 50, durationSeconds: 600,
    burstUploadsPerSecond: 200, burstDurationSeconds: 60, largeConcurrency: 10,
  });
  expect(requiredDistinctAccounts(config)).toBe(895);
  expect({ maximum: MAX_REQUESTS_PER_ACCOUNT, paced: PACED_REQUESTS_PER_ACCOUNT,
    burstRate: TWO_X_BURST_UPLOADS_PER_SECOND, burstDuration: BURST_DURATION_SECONDS,
    dedicatedSlowBodyAccounts: DEDICATED_SLOW_BODY_ACCOUNTS,
    admissionLeaseSeconds: ADMISSION_LEASE_SECONDS, slowBodyTimeoutMs: SLOW_BODY_TIMEOUT_MS })
    .toEqual({ maximum: 50, paced: 47, burstRate: 200, burstDuration: 60,
      dedicatedSlowBodyAccounts: 1, admissionLeaseSeconds: 900, slowBodyTimeoutMs: 1_020_000 });
});

it("accepts only bounded Retry-After delta seconds", () => {
  expect([validRetryAfter("1"), validRetryAfter("2"), validRetryAfter("3600")]).toEqual([true, true, true]);
  for (const value of [null, "", "0", "3601", "1.5", " 2", "2 ", "soon", "00001"]) {
    expect(validRetryAfter(value)).toBe(false);
  }
});

it("constructs bounded fragmented and deliberately stalled request streams", async () => {
  const bytes = new TextEncoder().encode("synthetic-fragmented-body");
  const reader = fragmentedRequestBody(bytes, 7).getReader();
  const chunks: Uint8Array[] = [];
  while (true) {
    const result = await reader.read();
    if (result.done) break;
    chunks.push(result.value);
  }
  expect(chunks.length).toBe(4);
  expect(new TextDecoder().decode(Buffer.concat(chunks))).toBe("synthetic-fragmented-body");
  expect(() => fragmentedRequestBody(bytes, 0)).toThrow("configuration is invalid");

  const stalled = stalledRequestBody().getReader();
  const prefix = await stalled.read();
  expect(prefix.done).toBe(false);
  expect(new TextDecoder().decode(prefix.value)).toContain("synthetic_stalled");
  await stalled.cancel();
});

it("enforces cumulative and active per-account scheduler limits", () => {
  expect(nextEligibleAccount([2, 0, 1], [1, 47, 46], 0)).toBe(2);
  expect(nextEligibleAccount([2, 0, 2], [1, 47, 46], 0)).toBe(-1);
  expect(() => nextEligibleAccount([0], [], 0)).toThrow("scheduler state is invalid");

  const launched = Array(894).fill(0) as number[];
  const active = Array(894).fill(0) as number[];
  const total = Array(894).fill(0) as number[];
  for (let request = 0; request < 500; request += 1) {
    recordAccountRequest(total, Math.floor(request / 2));
  }
  let cursor = 0;
  for (let request = 0; request < 42_000; request += 1) {
    const account = nextEligibleAccount(active, launched, cursor);
    if (account < 0) throw new Error("scheduler exhausted unexpectedly");
    launched[account] = (launched[account] ?? 0) + 1;
    recordAccountRequest(total, account);
    cursor = (account + 1) % launched.length;
  }
  for (let account = 0; account < 10; account += 1) recordAccountRequest(total, account);
  expect(Math.max(...launched)).toBe(47);
  expect(Math.min(...launched)).toBe(46);
  expect(Math.max(...total)).toBe(50);
  expect(Math.min(...total)).toBe(46);
  expect(() => recordAccountRequest(total, 0)).toThrow("request budget is exhausted");
  expect(() => recordAccountRequest(total, -1)).toThrow("ledger is invalid");
});

it.each([
  [{ ...base, HEALTHMD_LOAD_ENDPOINT: "https://api.healthmd.app/api/v1/exports" }],
  [{ ...base, HEALTHMD_LOAD_ENDPOINT: "https://api.staging.example.test/api/v1/exports?token=secret" }],
  [{ ...base, HEALTHMD_LOAD_ENDPOINT: "http://api.staging.example.test/api/v1/exports" }],
  [{ ...base, HEALTHMD_LOAD_ENDPOINT: "https://api.example.test/api/v1/exports" }],
  [{ ...base, HEALTHMD_LOAD_EXPECTED_REVISION: "short" }],
  [{ ...base, HEALTHMD_LOAD_CONFIRM_SYNTHETIC_ONLY: "no" }],
  [{ ...base, HEALTHMD_LOAD_DISTINCT_ACCOUNTS: "no" }],
  [{ ...base, HEALTHMD_LOAD_BURST_UPLOADS_PER_SECOND: "201" }],
  [{ ...base, HEALTHMD_LOAD_BURST_DURATION_SECONDS: "61" }],
])("rejects live, ambiguous, credential-bearing or unattested targets", (environment) => {
  expect(() => parseStagingLoadConfig(environment)).toThrow();
});

it("creates exact-size obviously synthetic compatibility envelopes", () => {
  for (const size of [1_024, MAX_EXPORT_BYTES]) {
    const bytes = buildSyntheticEnvelope(size, "unit-test");
    expect(bytes.byteLength).toBe(size);
    const value = JSON.parse(new TextDecoder().decode(bytes));
    expect(value.schema).toBe("healthmd.api_export");
    expect(value.records[0]).toMatchObject({
      date: "2020-01-01", synthetic_load_fixture: true, synthetic_marker: "unit-test",
    });
  }
});

it("accepts only unique owner-only token files with enough distinct accounts", () => {
  const root = mkdtempSync(join(tmpdir(), "healthmd-staging-load-")); roots.push(root);
  const path = join(root, "tokens");
  const tokens = ["hmd_ing_" + "a".repeat(24), "hmd_ing_" + "b".repeat(24)];
  writeFileSync(path, `${tokens.join("\n")}\n`, { mode: 0o600 });
  expect(readDistinctAccountTokens(path, 2)).toEqual(tokens);
  expect(() => readDistinctAccountTokens(path, 3)).toThrow("At least 3 distinct synthetic accounts");
  writeFileSync(path, `${tokens[0]}\n${tokens[0]}\n`, { mode: 0o600 });
  expect(() => readDistinctAccountTokens(path, 2)).toThrow("duplicates");
  chmodSync(path, 0o644);
  expect(() => readDistinctAccountTokens(path, 1)).toThrow("owner-only");
});

it("reports deterministic nearest-rank latency percentiles", () => {
  expect(percentile([], 0.95)).toBeNull();
  expect(percentile([40, 10, 30, 20], 0.5)).toBe(20);
  expect(percentile([40, 10, 30, 20], 0.95)).toBe(40);
});
