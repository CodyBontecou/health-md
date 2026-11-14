import { afterEach, expect, it } from "vitest";
import { chownSync, chmodSync, mkdirSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { VmDatabase, VmObjectStore, assertPrivateDirectory, vmReaderGroupId } from "../vm/storage";

const roots: string[] = [];
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });

it("permits only an explicit, separate reader group with read/search access", async () => {
  const groupId = (process.getgroups() as number[]).find((gid: number) => gid !== process.getgid());
  if (!groupId) throw new Error("Reader-group test requires a separate supplementary test group");
  const root = mkdtempSync(join(tmpdir(), "healthmd-private-group-test-"));
  roots.push(root);
  const previousGroup = process.env.HEALTHMD_VM_READER_GID;
  const oldUmask = process.umask(0o077);
  try {
    const initial = new VmDatabase(root, resolve(import.meta.dirname, "../migrations"));
    initial.close();
    const dataPath = join(root, "cloud.sqlite");
    // A setgid directory gives new encrypted objects only the dedicated group,
    // never the writer's own primary group or unrelated system users.
    chownSync(root, process.getuid(), groupId);
    chmodSync(root, 0o2750);
    mkdirSync(join(root, "objects"), { mode: 0o750 });
    mkdirSync(join(root, "objects", "v1"), { mode: 0o750 });
    for (const dir of ["objects", "objects/v1"]) {
      chownSync(join(root, dir), process.getuid(), groupId);
      chmodSync(join(root, dir), 0o2750);
    }
    chownSync(dataPath, process.getuid(), groupId);
    chmodSync(dataPath, 0o640);
    process.env.HEALTHMD_VM_READER_GID = String(groupId);
    process.umask(0o027);
    expect(vmReaderGroupId()).toBe(groupId);
    expect(assertPrivateDirectory(root)).toBe(root);
    const db = new VmDatabase(root, resolve(import.meta.dirname, "../migrations"));
    try {
      const objects = new VmObjectStore(root);
      const key = "v1/11111111-1111-4111-8111-111111111111";
      await objects.put(key, new Uint8Array([1, 2, 3]));
      const object = statSync(join(root, "objects", key));
      expect(object.mode & 0o777).toBe(0o640);
      expect(object.gid).toBe(groupId);
      expect((await objects.get(key))?.arrayBuffer).toBeTypeOf("function");
    } finally { db.close(); }
    chmodSync(dataPath, 0o660);
    expect(() => new VmDatabase(root, resolve(import.meta.dirname, "../migrations")))
      .toThrow(/unsafe/u);
    chmodSync(dataPath, 0o640);
    chmodSync(root, 0o2755);
    expect(() => assertPrivateDirectory(root)).toThrow(/read group/u);
    chmodSync(root, 0o2750);
    process.env.HEALTHMD_VM_READER_GID = String(process.getgid());
    expect(() => vmReaderGroupId()).toThrow(/non-dedicated/u);
    delete process.env.HEALTHMD_VM_READER_GID;
    expect(() => assertPrivateDirectory(root)).toThrow(/read group/u);
  } finally {
    if (previousGroup === undefined) delete process.env.HEALTHMD_VM_READER_GID;
    else process.env.HEALTHMD_VM_READER_GID = previousGroup;
    process.umask(oldUmask);
  }
});
