import { afterEach, expect, it } from "vitest";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createProfileSqlCandidate } from "../src/profile-sync-v1-sql";
import { createProfileSyncV1ReadView } from "../src/profile-sync-v1-read-view";
import { parseProfileSyncV1Page, parseProfileSyncV1Error } from "../src/profile-sync-v1-contract";
import { sqlHarness, encode, owners, type HostProfileSql } from "./support/profile-sync-sql";
const corpus = JSON.parse(readFileSync(new URL("../../../packages/contracts/profile-sync/v1/fixtures/parser-cases.json", import.meta.url), "utf8"));
const raw = JSON.parse(corpus.cases.find((c: {id:string}) => c.id === "valid-publish").raw);
const stores: HostProfileSql[] = [], roots: string[] = [];
afterEach(() => { for (const store of stores.splice(0)) store.db.close(); for (const root of roots.splice(0)) rmSync(root, { recursive: true }); });
async function fixture() {
  const root = mkdtempSync(join(tmpdir(), "as06-snapshot-")); roots.push(root);
  const h = await sqlHarness(join(root, "synthetic.sqlite")); stores.push(h.store);
  const a = await h.issue(owners[0]), b = await h.issue(owners[1]);
  let sequence = 200;
  const mutate = async (operation: string, fields: object = {}) => {
    const bytes = encode({ schema: "healthmd.profile_sync", schema_version: 1, operation,
      mutation_id: "psm_" + (++sequence).toString(16).padStart(32, "0"), base_revision: 0,
      ...(operation === "create" ? { content_json: raw.content_json, content_hash: raw.content_hash } : {}), ...fields });
    expect(await h.service.select(h.request(a), bytes)).toEqual({ok:true});
    const result = await h.service.mutate(h.request(a), bytes); expect(result).toHaveProperty("ok", true);
    if (!("ok" in result)) throw Error("Fixture mutation failed"); return result.record;
  };
  await h.service.optIn(h.request(a)); await h.service.optIn(h.request(b));
  const records = [await mutate("create"), await mutate("create"), await mutate("create")];
  const context = { issuer:a.issuer, environment:a.environment, account:a.account_id, generation:0 };
  const read = (cursor: string | null = null, mode = "snapshot", limit = 1) => encode({schema:"healthmd.profile_sync",schema_version:1,mode,cursor,limit});
  const request = h.request(a, "/api/profile-sync/v1/read");
  return {...h,a,b,records,context,read,pageRequest:request,mutate};
}
it("freezes actual SQL membership/order/watermark through interleaved reorder/delete/create and feeds actual read-view", async () => {
  const h = await fixture(), collector = createProfileSyncV1ReadView({sentinel:"healthmd.profile-sync.v1.read-view.synthetic-only",context:h.context});
  const firstRequest = h.read(); expect(collector.select(h.context,firstRequest).result).toBe("pending");
  const firstBytes = await h.service.readPage(h.pageRequest, firstRequest), first = await parseProfileSyncV1Page(firstBytes);
  expect(first.highWatermark).toBe(3); expect(first.items[0]!.content!.contentJson).toBe(raw.content_json);
  expect((await collector.receive(h.context,firstRequest,firstBytes)).result).toBe("pending");
  expect(collector.view().committed).toBeNull();
  await h.mutate("reorder", {profile_id:h.records[2]!.profileId,base_revision:1,order_key:0});
  await h.mutate("delete", {profile_id:h.records[1]!.profileId,base_revision:1});
  await h.mutate("create");
  h.store.reopen();
  let cursor = first.nextCursor;
  while (cursor) {
    const request = h.read(cursor); expect(collector.select(h.context,request).result).toBe("pending");
    const reply = await h.service.readPage(h.pageRequest,request), page = await parseProfileSyncV1Page(reply);
    expect(page.snapshotId).toBe(first.snapshotId); expect(page.highWatermark).toBe(3);
    expect((await collector.receive(h.context,request,reply)).result).toBe(page.nextCursor === null ? "complete" : "pending"); cursor=page.nextCursor;
  }
  expect(collector.view().committed!.items.map(r=>r.profileId)).toEqual(h.records.map(r=>r.profileId));
  expect(collector.view().committed!.items.every(r=>!r.deleted)).toBe(true);
});
it("replays exact continuation bytes after reopen and lost acknowledgement without advancing a checkpoint", async () => {
  const h = await fixture(); h.store.fault="lost";
  const first = await parseProfileSyncV1Page(await h.service.readPage(h.pageRequest,h.read()));
  const bytes = h.read(first.nextCursor); const reply = await h.service.readPage(h.pageRequest,bytes);
  h.store.reopen(); expect(await h.service.readPage(h.pageRequest,bytes)).toEqual(reply);
  expect(h.store.db.prepare("SELECT count(*) AS n FROM ps_view").get()).toMatchObject({n:1});
});
it.each(["noop","rollback","crash"] as const)("%s snapshot publication never invents a cursor or success", async fault => {
  const h = await fixture(); h.store.fault=fault;
  expect(parseProfileSyncV1Error(await h.service.readPage(h.pageRequest,h.read())).result).toBe("unavailable");
  h.store.reopen(); expect(h.store.db.prepare("SELECT count(*) AS n FROM ps_view").get()).toMatchObject({n:0});
  expect(h.store.db.prepare("SELECT count(*) AS n FROM ps_cursor").get()).toMatchObject({n:0});
});
it.each(["owner","mode","position","tamper","expiry","withdraw","revoke"])("rejects %s cursor reuse and preserves prior committed consumer state", async failure => {
  const h = await fixture(); const first = await parseProfileSyncV1Page(await h.service.readPage(h.pageRequest,h.read()));
  const collector = createProfileSyncV1ReadView({sentinel:"healthmd.profile-sync.v1.read-view.synthetic-only",context:h.context});
  const initial = h.read(null,"snapshot",8); collector.select(h.context,initial);
  expect((await collector.receive(h.context,initial,await h.service.readPage(h.pageRequest,initial))).result).toBe("complete");
  const prior = collector.view().committed;
  let request = h.pageRequest, bytes = h.read(first.nextCursor), service = h.service;
  if(failure==="owner") request=h.request(h.b,"/api/profile-sync/v1/read");
  if(failure==="mode") bytes=h.read(first.nextCursor,"changes");
  if(failure==="position") h.store.db.prepare("UPDATE ps_cursor SET position=position+1 WHERE token=?").run(first.nextCursor);
  if(failure==="tamper") h.store.db.prepare("UPDATE ps_view SET body=json_set(body,'$.ciphertext','00') WHERE id=?").run(first.snapshotId);
  if(failure==="expiry") service=createProfileSqlCandidate({...h.ports,clock:()=>Math.floor(Date.now()/1000)+901});
  if(failure==="withdraw") await h.service.withdraw(h.request(h.a));
  if(failure==="revoke") await h.authority.revoke({kind:"access",token:h.a.access_token});
  const reply = await service.readPage(request,bytes); expect(()=>parseProfileSyncV1Error(reply)).not.toThrow();
  // A refused unexpected response cannot replace the already complete view.
  await collector.receive(h.context,bytes,reply); expect(collector.view().committed).toEqual(prior);
});
it("keeps unsupported baseline-free changes fail-closed without profile or view effects",async()=>{
  const h=await fixture(); const before=h.store.db.prepare("SELECT * FROM ps_partition ORDER BY owner").all();
  expect(parseProfileSyncV1Error(await h.service.readPage(h.pageRequest,h.read(null,"changes"))).result).toBe("resync_required");
  expect(h.store.db.prepare("SELECT * FROM ps_partition ORDER BY owner").all()).toEqual(before);
});

it("honors the eight-item bound and finite stored-view cap without evicting live cursors", async()=>{
  const h=await fixture(); for(let i=0;i<6;i++) await h.mutate("create");
  const first=await parseProfileSyncV1Page(await h.service.readPage(h.pageRequest,h.read(null,"snapshot",8)));
  expect(first.items).toHaveLength(8); expect(first.nextCursor).not.toBeNull();
  const last=await parseProfileSyncV1Page(await h.service.readPage(h.pageRequest,h.read(first.nextCursor,"snapshot",8)));
  expect(last.items).toHaveLength(1); expect(last.nextCursor).toBeNull();
  for(let i=0;i<7;i++) await parseProfileSyncV1Page(await h.service.readPage(h.pageRequest,h.read()));
  expect(parseProfileSyncV1Error(await h.service.readPage(h.pageRequest,h.read())).result).toBe("quota_exceeded");
  const retained=await parseProfileSyncV1Page(await h.service.readPage(h.pageRequest,h.read(first.nextCursor,"snapshot",8)));
  expect(retained.snapshotId).toBe(first.snapshotId); expect(retained.items.map(r=>r.profileId)).toEqual(last.items.map(r=>r.profileId));
});
it.each(["withdraw","selection","revoke"])("fences %s during snapshot encryption before publishing view rows",async action=>{
  const h=await fixture(); let once=false;
  const service=createProfileSqlCandidate({...h.ports,afterCrypto:async()=>{
    if(once)return;once=true;
    if(action==="withdraw") await h.service.withdraw(h.request(h.a));
    if(action==="revoke") await h.authority.revoke({kind:"access",token:h.a.access_token});
    if(action==="selection") await h.service.select(h.request(h.a),encode({...raw,mutation_id:"psm_"+"f".repeat(32)}));
  }});
  parseProfileSyncV1Error(await service.readPage(h.pageRequest,h.read()));
  expect(h.store.db.prepare("SELECT count(*) AS n FROM ps_view").get()).toMatchObject({n:0});
});
