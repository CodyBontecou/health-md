import assert from "node:assert/strict";
import { test } from "node:test";
import { createRequire } from "node:module";
import { realpath, readFile } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Result from "effect/Result";
import * as Catalog from "@healthmd/core-ts/candidate/catalog";
import * as Normalize from "@healthmd/core-ts/candidate/normalize";
import * as Query from "@healthmd/core-ts/candidate/query";
import * as Registry from "@healthmd/core-ts/candidate/registry";
import type { CatalogTool, StaticCatalog, SurfaceProfile, CatalogResult } from "@healthmd/core-ts/candidate/catalog";
import type { QueryInvocation } from "@healthmd/core-ts/candidate/normalize";
import type { AttributedPage, QueryBinding, QueryFailure, QueryResource, QueryScope, TraversalRequest, TraversalReceipt } from "@healthmd/core-ts/candidate/query";
import type { RegistryReader, RegistrySnapshot, RegistryResult } from "@healthmd/core-ts/candidate/registry";
import { candidateExportVectors, excludedSubpaths, expectedBounds, expectedAuthority, normalizationVector, traversalVector } from "./candidate-api-vectors.js";
const modules = [Catalog, Normalize, Query, Registry];
// These assignments typecheck packed declaration imports, not hidden source paths.
const catalogFactory: (tools: readonly CatalogTool[]) => CatalogResult<StaticCatalog> = Catalog.createStaticCatalog;
const normalize: (input: unknown) => CatalogResult<QueryInvocation> = Normalize.normalizeMetricChart;
const registryReader: (text: unknown, version?: number) => RegistryResult<RegistryReader> = Registry.readReviewedRegistry;
const operation: (request: TraversalRequest) => Effect.Effect<Query.QueryBody | TraversalReceipt, QueryFailure, Query.QuerySource> = Query.traverseQuery;
const scopedOwner: (allocation: Effect.Effect<QueryResource, QueryFailure>) => Effect.Effect<QueryResource, QueryFailure, QueryScope> = Query.ownQueryResource;
const profile: SurfaceProfile = "local_read_only";
const acceptsSnapshot = (snapshot: RegistrySnapshot): number => snapshot.registry_version;
void catalogFactory; void registryReader; void acceptsSnapshot;

for (const [index, vector] of candidateExportVectors.entries()) test(`private packed API symbols and physical Effect identity: ${vector.subpath}`, async () => {
  assert.deepEqual(Object.keys(modules[index]!).sort(), [...vector.symbols].sort());
  const url = import.meta.resolve(vector.subpath);
  assert.ok(url.endsWith(`/dist/core/${vector.stem}.js`));
  const physicalEffect = await realpath(fileURLToPath(import.meta.resolve("effect/Effect")));
  assert.equal(await realpath(createRequire(url).resolve("effect/Effect")), physicalEffect);
  const namespace: typeof Effect = await import(pathToFileURL(physicalEffect).href);
  assert.equal(namespace, Effect);
  const packedManifest = JSON.parse(await readFile(new URL("../../package.json", import.meta.resolve("@healthmd/core-ts")), "utf8"));
  const entry = packedManifest.exports[vector.subpath.replace("@healthmd/core-ts", ".")];
  assert.deepEqual(entry, { types: `./dist/core/${vector.stem}.d.ts`, import: `./dist/core/${vector.stem}.js` });
});
test("hidden files and unreviewed candidate internals remain unavailable", async () => {
  for (const subpath of excludedSubpaths) {
    await assert.rejects(import(subpath), { code: "ERR_PACKAGE_PATH_NOT_EXPORTED" });
  }
});
test("packed candidate pins and bounds preserve accepted source authority", () => {
  assert.deepEqual(Query.traversalBounds, expectedBounds);
  assert.equal(Query.QuerySource.key, expectedAuthority.querySourceKey);
  assert.equal(Catalog.catalogMirrorSha256, expectedAuthority.catalog);
  assert.equal(Registry.registryExpectedSha256, expectedAuthority.registry);
  assert.equal(Catalog.fullOperationIds.length, expectedAuthority.fullCatalogCount);
  assert.equal(Catalog.readOnlyOperationIds.length, expectedAuthority.readOnlyCatalogCount);
});
test("dynamic packed normalizer preserves literal source expectation and rejects envelope IDs", async () => {
  const dynamic: typeof Normalize = await import("@healthmd/core-ts/candidate/normalize");
  assert.equal(dynamic.normalizeMetricChart, normalize);
  const result = dynamic.normalizeMetricChart(normalizationVector.input);
  assert.ok(Result.isSuccess(result)); assert.deepEqual(result.success, normalizationVector.expected);
  const invalid = dynamic.normalizeMetricChart(normalizationVector.rejected);
  assert.ok(Result.isFailure(invalid)); assert.deepEqual(invalid.failure, normalizationVector.failure);
});
test("packed QuerySource constructor resolves the same typed Layer and scoped traversal owner", async () => {
  const dynamic: typeof Query = await import("@healthmd/core-ts/candidate/query");
  assert.equal(dynamic.QuerySource, Query.QuerySource); assert.equal(dynamic.traverseQuery, operation);
  assert.equal(dynamic.ownQueryResource, scopedOwner);
  const invocation = normalize(normalizationVector.input); assert.ok(Result.isSuccess(invocation));
  const binding: QueryBinding = { ...traversalVector.binding, profile };
  const request: TraversalRequest = { invocation: invocation.success, binding, grants: ["healthmd:read"], deadlineMilliseconds: 1000 };
  const counts = { opened: 0, read: 0, released: 0 };
  const source = Layer.succeed(dynamic.QuerySource)({ open: () => {
    counts.opened++;
    const resource: QueryResource = { binding,
      read: (cursor) => Effect.sync((): AttributedPage => { counts.read++; return { body: traversalVector.body, encodedBytes: traversalVector.encodedBytes, binding, requestedCursor: cursor }; }),
      release: Effect.sync(() => { counts.released++; }),
    };
    return scopedOwner(Effect.succeed(resource));
  } });
  const result = await Effect.runPromise(operation(request).pipe(Effect.provide(source)));
  assert.deepEqual(result, traversalVector.expected); assert.deepEqual(counts, traversalVector.resourceCounts);
  // Synthetic trusted accounting/attribution only; transport completion preserves partial coverage.
});
