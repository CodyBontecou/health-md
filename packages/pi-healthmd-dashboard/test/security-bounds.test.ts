import assert from "node:assert/strict";
import { mkdtemp, mkdir, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createController } from "../src/extension.js";
import { canonicalRoot, loadHealthData, requireApprovedPath } from "../src/loader.js";

test("approved realpath roots permit children and reject outside, traversal, and aliases", async () => {
  const base = await mkdtemp(join(tmpdir(), "healthmd-roots-"));
  const root = join(base, "approved"), outside = join(base, "outside");
  await mkdir(root); await mkdir(outside);
  const child = join(root, "child.json"), secret = join(outside, "secret.json");
  await writeFile(child, "{}"); await writeFile(secret, "{}");
  const approved = [await canonicalRoot(root)];
  assert.equal(await requireApprovedPath(child, approved), await canonicalRoot(child));
  await assert.rejects(requireApprovedPath(secret, approved), /outside approved/);
  await assert.rejects(requireApprovedPath(join(root, "..", "outside", "secret.json"), approved), /outside approved/);
  const alias = join(root, "alias.json"); await symlink(secret, alias);
  await assert.rejects(requireApprovedPath(alias, approved), /Symbolic-link/);
  const insideAlias = join(root, "inside-alias.json"); await symlink(child, insideAlias);
  await assert.rejects(requireApprovedPath(insideAlias, approved), /Symbolic-link/);
  await assert.rejects(canonicalRoot(insideAlias), /Symbolic-link/);
  await assert.rejects(loadHealthData([secret], {}, approved), /outside approved/);
  await assert.rejects(requireApprovedPath(child, []), /No approved/);
});

test("model load cannot approve but user command/controller approval can", async () => {
  const base = await mkdtemp(join(tmpdir(), "healthmd-controller-"));
  const file = join(base, "data.json"); await writeFile(file, "{}");
  const controller = createController();
  await assert.rejects(controller.loadApproved([file]), /No approved/);
  await controller.approveAndLoad([base]);
  assert.equal((await controller.loadApproved([file])).documents.length, 1);
  assert.equal(controller.approvedRoots().length, 1);
  controller.reset();
  assert.equal(controller.approvedRoots().length, 0);
  await assert.rejects(controller.loadApproved([file]), /No approved/);
});

test("bounded loader handles empty containers/deep data and rejects depth, nodes, oversize, symlink input", async () => {
  const base = await mkdtemp(join(tmpdir(), "healthmd-bounds2-"));
  const empty = join(base, "empty.json"); await writeFile(empty, '{"a":[],"b":{}}');
  assert.ok((await loadHealthData([empty])).entries.some(entry => entry.kind === "array"));
  const deep = join(base, "deep.json"); await writeFile(deep, `${"[".repeat(30)}0${"]".repeat(30)}`);
  await assert.rejects(loadHealthData([deep], { maxDepth: 10 }), /depth/);
  await assert.rejects(loadHealthData([empty], { maxNodes: 2 }), /node count/);
  await assert.rejects(loadHealthData([empty], { maxFileBytes: 2 }), /per-file/);
  const link = join(base, "link.json"); await symlink(empty, link);
  await assert.rejects(loadHealthData([link]), /symbolic[- ]link|ELOOP/i);
  const crowded = join(base, "crowded"); await mkdir(crowded);
  for (const name of ["a.txt", "b.txt", "c.txt"]) await writeFile(join(crowded, name), "ignored");
  await assert.rejects(loadHealthData([crowded], { maxDirectoryEntries: 2 }), /Directory entry count/);
});
