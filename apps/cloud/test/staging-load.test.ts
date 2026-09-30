import { afterEach, expect, it } from "vitest";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  MAX_EXPORT_BYTES, buildSyntheticEnvelope, parseStagingLoadConfig, percentile,
  readDistinctAccountTokens, requiredDistinctAccounts,
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
    concurrency: 500, uploadsPerSecond: 50, durationSeconds: 600, largeConcurrency: 10,
  });
  expect(requiredDistinctAccounts(config)).toBe(639);
});

it.each([
  [{ ...base, HEALTHMD_LOAD_ENDPOINT: "https://api.healthmd.app/api/v1/exports" }],
  [{ ...base, HEALTHMD_LOAD_ENDPOINT: "https://api.staging.example.test/api/v1/exports?token=secret" }],
  [{ ...base, HEALTHMD_LOAD_ENDPOINT: "http://api.staging.example.test/api/v1/exports" }],
  [{ ...base, HEALTHMD_LOAD_ENDPOINT: "https://api.example.test/api/v1/exports" }],
  [{ ...base, HEALTHMD_LOAD_EXPECTED_REVISION: "short" }],
  [{ ...base, HEALTHMD_LOAD_CONFIRM_SYNTHETIC_ONLY: "no" }],
  [{ ...base, HEALTHMD_LOAD_DISTINCT_ACCOUNTS: "no" }],
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
