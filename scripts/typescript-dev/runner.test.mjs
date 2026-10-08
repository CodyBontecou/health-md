import test from "node:test";
import assert from "node:assert/strict";
import { readFile, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import getExePath from "@effect/tsgo/lib/getExePath";
import { effectErrors, effectPlugin, selectAffected } from "./policy.mjs";

const toolRoot = fileURLToPath(new URL("./", import.meta.url));
process.chdir(toolRoot);
const repo = path.resolve(toolRoot, "../..");
const schema = JSON.parse(await readFile(new URL("./node_modules/@effect/tsgo/schema.json", import.meta.url)));
const entries = ["tests/one.test.ts", "tests/two.test.ts"];
const graph = { outputs: {
  one: { entryPoint: entries[0], inputs: { [entries[0]]: {}, "tests/shared.ts": {}, "src/one.ts": {} } },
  two: { entryPoint: entries[1], inputs: { [entries[1]]: {}, "tests/shared.ts": {}, "src/two.ts": {} } },
} };
test("dependency closure selects a single affected test", () => {
  assert.deepEqual(selectAffected(entries, graph, ["packages/healthmd-core-ts/src/one.ts"], "packages/healthmd-core-ts"), [entries[0]]);
});
test("shared helper selects every dependent test", () => {
  assert.deepEqual(selectAffected(entries, graph, ["packages/healthmd-core-ts/tests/shared.ts"], "packages/healthmd-core-ts"), entries);
});
test("unresolved, deleted and metadata paths conservatively select full coverage", () => {
  for (const file of ["src/deleted.ts", "tests/new.test.ts", "tsconfig.json", "package-lock.json"]) {
    assert.deepEqual(selectAffected(entries, graph, [`packages/healthmd-core-ts/${file}`], "packages/healthmd-core-ts"), entries);
  }
});
test("core changes fan out to CLI tests", () => {
  assert.deepEqual(selectAffected(entries, graph, ["packages/healthmd-core-ts/src/one.ts"], "apps/cli"), entries);
});
test("shared contracts and runner changes select full coverage", () => {
  for (const file of ["packages/contracts/product-capabilities.json", "scripts/typescript-dev/policy.mjs"]) {
    for (const component of ["packages/healthmd-core-ts", "apps/cli"]) {
      assert.deepEqual(selectAffected(entries, graph, [file], component), entries);
    }
  }
});
test("unrelated component changes select no core runtime tests", () => {
  assert.deepEqual(selectAffected(entries, graph, ["apps/android/app/build.gradle.kts"], "packages/healthmd-core-ts"), []);
});
test("an incomplete entry graph cannot silently skip a test", () => {
  assert.throws(() => selectAffected([...entries, "tests/missing.test.ts"], graph, ["packages/healthmd-core-ts/src/one.ts"], "packages/healthmd-core-ts"), /Missing test dependency graph/);
});
test("Effect correctness errors are blocking and style suggestions are disabled", () => {
  const plugin = effectPlugin(schema);
  for (const rule of effectErrors) assert.equal(plugin.diagnosticSeverity[rule], "error");
  assert.equal(plugin.diagnosticSeverity.effectFnOpportunity, "off");
  assert.equal(plugin.ignoreEffectErrorsInTscExitCode, false);
  assert.throws(() => effectPlugin({ definitions: {} }), /schema changed/);
});
test("real compiler rejects floating Effects, missing yield star and unsafe channel narrowing", async () => {
  // Keep probe modules near the component's existing Effect installation. They are never
  // production source or frozen test inputs and are removed even after failed assertions.
  const cache = path.join(repo, "packages/healthmd-core-ts/node_modules/.cache/healthmd-dev");
  await mkdir(cache, { recursive: true });
  const owned = await mkdtemp(path.join(cache, "diagnostic-probe-"));
  const compiler = getExePath();
  const config = path.join(owned, "tsconfig.json");
  const source = path.join(owned, "probe.ts");
  try {
    await writeFile(config, JSON.stringify({
      extends: path.join(repo, "packages/healthmd-core-ts/tsconfig.json"),
      compilerOptions: { plugins: [effectPlugin(schema)] }, include: [source],
    }));
    const probes = [
      { source: 'import * as Effect from "effect/Effect"; export const value = Effect.succeed(1);', success: true },
      { source: 'import * as Effect from "effect/Effect"; Effect.succeed(1);', diagnostic: "floatingEffect" },
      { source: 'import * as Effect from "effect/Effect"; export const value = Effect.gen(function* () { yield Effect.succeed(1); });', diagnostic: "missingStarInYieldEffectGen" },
      { source: 'import * as Effect from "effect/Effect"; const failure = Effect.fail("failed"); export const value = failure as Effect.Effect<never>;', diagnostic: "unsafeEffectTypeAssertion" },
    ];
    for (const probe of probes) {
      await writeFile(source, probe.source);
      const result = spawnSync(compiler, ["--project", config, "--pretty", "false"], { cwd: toolRoot, encoding: "utf8", timeout: 15000 });
      assert.ifError(result.error);
      if (probe.success) assert.equal(result.status, 0, result.stdout + result.stderr);
      else {
        assert.notEqual(result.status, 0, `Compiler accepted ${probe.diagnostic}`);
        assert.ok(result.stdout.includes(`effect(${probe.diagnostic})`), result.stdout + result.stderr);
      }
    }
  } finally {
    await rm(owned, { recursive: true, force: true });
  }
});
