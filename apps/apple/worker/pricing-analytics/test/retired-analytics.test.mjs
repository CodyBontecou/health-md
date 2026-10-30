import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/index.ts";

test("legacy uploads are discarded without reading body, storage, or outbound services", async () => {
  const request = new Request("https://retired.invalid/v1/events", { method: "POST", body: "private legacy payload" });
  for (const method of ["text", "json", "arrayBuffer"]) request[method] = () => { throw new Error("body accessed"); };
  const env = new Proxy({}, { get() { throw new Error("binding accessed"); } });
  const response = await worker.fetch(request, env);
  assert.equal(response.status, 204);
  assert.equal(request.bodyUsed, false);
  assert.equal(await response.text(), "");
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});
test("health explicitly reports retired collection and unsupported paths are gone", async () => {
  const response = await worker.fetch(new Request("https://retired.invalid/health"));
  assert.deepEqual(await response.json(), { status: "retired", collection: false });
  for (const path of ["/v2/privacy/register", "/v2/privacy/delete", "/", "/v1/events"]) {
    assert.equal((await worker.fetch(new Request("https://retired.invalid" + path))).status, 410);
  }
});
test("preflight and malformed legacy bodies require no analytics configuration", async () => {
  assert.equal((await worker.fetch(new Request("https://retired.invalid/v1/events", { method: "OPTIONS" }))).status, 204);
  assert.equal((await worker.fetch(new Request("https://retired.invalid/v1/events/", { method: "POST", body: "not json" }))).status, 204);
});
