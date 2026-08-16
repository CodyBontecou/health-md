import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, stat, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { configuredCacheDirectory, loadCachedEvidence, persistFetchedEvidence, rememberCacheDirectory } from "../src/cache.js";
import { loadHealthDataText } from "../src/loader.js";

const fixture = resolve(import.meta.dirname, "../../../apps/apple/docs/reference/generated/automation/agent-query-response.json");

test("content-addressed cache remembers, verifies, and restores exact fetched evidence", async () => {
  const root = await mkdtemp(join(tmpdir(), "healthmd-cache-"));
  const cache = join(root, "evidence"), config = join(root, "config");
  const previous = process.env.XDG_CONFIG_HOME;
  process.env.XDG_CONFIG_HOME = config;
  try {
    const directory = await rememberCacheDirectory(cache);
    assert.equal(await configuredCacheDirectory(), directory);
    const text = await readFile(fixture, "utf8");
    const receipt = await persistFetchedEvidence(directory, { text, origin: "healthmd-mcp", operation: "healthmd_metric_chart" });
    assert.equal(receipt.entries, 1);
    assert.equal((await stat(receipt.file)).mode & 0o777, 0o600);
    await chmod(receipt.file, 0o644);
    await persistFetchedEvidence(directory, { text, origin: "healthmd-mcp", operation: "healthmd_metric_chart" });
    assert.equal((await stat(receipt.file)).mode & 0o777, 0o600);
    const secondText = `${text}\n`;
    await Promise.all([
      persistFetchedEvidence(directory, { text, origin: "healthmd-mcp", operation: "healthmd_metric_chart" }),
      persistFetchedEvidence(directory, { text: secondText, origin: "healthmd-cli", operation: "healthmd_training_evidence" }),
    ]);
    const inputs = await loadCachedEvidence(directory);
    assert.equal(inputs.length, 2);
    assert.ok(inputs.some(input => input.text === text && input.origin === "healthmd-mcp" && input.operation === "healthmd_metric_chart"));
    assert.ok(inputs.some(input => input.text === secondText && input.origin === "healthmd-cli" && input.operation === "healthmd_training_evidence"));
    const store = loadHealthDataText(inputs);
    assert.ok(store.documents.every(document => document.contractKind === "query_response"));
    assert.ok(store.documents.some(document => document.operation === "healthmd_metric_chart"));
    await writeFile(receipt.file, `${text} `);
    await chmod(receipt.file, 0o600);
    await assert.rejects(loadCachedEvidence(directory), /size mismatch|digest mismatch/);
  } finally {
    if (previous === undefined) delete process.env.XDG_CONFIG_HOME; else process.env.XDG_CONFIG_HOME = previous;
  }
});

test("cache rejects a symlinked objects directory", async () => {
  const root = await mkdtemp(join(tmpdir(), "healthmd-cache-symlink-"));
  const cache = join(root, "cache"), outside = join(root, "outside");
  await mkdir(cache, { mode: 0o700 });
  await mkdir(outside, { mode: 0o700 });
  await symlink(outside, join(cache, "objects"));
  await assert.rejects(rememberCacheDirectory(cache), /objects path escapes/);
});
