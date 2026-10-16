import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/index.js";
import { baseEnv, makeCtx, makeDB, requestJSON } from "./helpers.js";

const USER_ID = "synthetic_user_0001";
const BUNDLE_ID = "com.codybontecou.obsidianhealth";
const TOKEN_A = "ab".repeat(32);
const TOKEN_B = "cd".repeat(32);

function fixture(t) {
  const db = makeDB();
  t.after(() => db.raw.close());
  const env = baseEnv(db);
  const ctx = makeCtx();
  return {
    db,
    async register(fields = {}) {
      const response = await worker.fetch(requestJSON("POST", "/devices/register", {
        userId: USER_ID,
        platform: "ios",
        apnsToken: TOKEN_A,
        bundleId: BUNDLE_ID,
        ...fields,
      }), env, ctx);
      await ctx.drain();
      return response;
    },
    device(platform = "ios") {
      const row = db.raw.prepare("SELECT * FROM devices WHERE user_id = ? AND platform = ?")
        .get(USER_ID, platform);
      return row === undefined ? null : { ...row };
    },
    async upsert(fields = {}) {
      const response = await worker.fetch(requestJSON("POST", "/schedules/upsert", {
        userId: USER_ID,
        timezone: "UTC",
        schedule: { isEnabled: true, frequency: "daily", hour: 9, minute: 15 },
        ...fields,
      }), env, ctx);
      await ctx.drain();
      return response;
    },
  };
}

function assertOK(response) {
  assert.ok(response.status >= 200 && response.status < 300, `Unexpected response status ${response.status}`);
}

for (const [platform, environment] of [["ios", "development"], ["macos", "production"]]) {
  test(`registration persists ${environment} for ${platform}`, async (t) => {
    const f = fixture(t);
    assertOK(await f.register({ platform, apnsEnvironment: environment }));
    const row = f.device(platform);
    assert.equal(row.apns_environment, environment);
    assert.equal(row.apns_token, TOKEN_A);
    assert.equal(row.bundle_id, BUNDLE_ID);
    assert.ok(row.registration_revision);
    assert.equal(row.apns_blocked_reason, null);
  });
}

test("healthy repeated registration preserves its revision", async (t) => {
  const f = fixture(t);
  assertOK(await f.register({ apnsEnvironment: "development" }));
  const original = f.device();
  assertOK(await f.register({ apnsEnvironment: "development" }));
  const repeated = f.device();
  assert.equal(repeated.apns_environment, original.apns_environment);
  assert.equal(repeated.registration_revision, original.registration_revision);
});

for (const environment of ["development", "production"]) {
  test(`legacy same-token registration retains known ${environment} environment and revision`, async (t) => {
    const f = fixture(t);
    assertOK(await f.register({ apnsEnvironment: environment }));
    const original = f.device();
    assertOK(await f.register());
    const legacy = f.device();
    assert.equal(legacy.apns_environment, environment);
    assert.equal(legacy.registration_revision, original.registration_revision);
  });
}

test("legacy new-token registration resets the unknown environment and replaces revision", async (t) => {
  const f = fixture(t);
  assertOK(await f.register({ apnsEnvironment: "development" }));
  const original = f.device();
  assertOK(await f.register({ apnsToken: TOKEN_B }));
  const replacement = f.device();
  assert.equal(replacement.apns_token, TOKEN_B);
  assert.equal(replacement.apns_environment, null);
  assert.notEqual(replacement.registration_revision, original.registration_revision);
  assert.equal(replacement.apns_blocked_reason, null);
});

test("explicit environment change replaces revision even when the token is unchanged", async (t) => {
  const f = fixture(t);
  assertOK(await f.register({ apnsEnvironment: "development" }));
  const original = f.device();
  assertOK(await f.register({ apnsEnvironment: "production" }));
  const replacement = f.device();
  assert.equal(replacement.apns_environment, "production");
  assert.equal(replacement.apns_token, TOKEN_A);
  assert.notEqual(replacement.registration_revision, original.registration_revision);
});

test("initial legacy registration has unresolved environment", async (t) => {
  const f = fixture(t);
  assertOK(await f.register());
  assert.equal(f.device().apns_environment, null);
  assert.ok(f.device().registration_revision);
});

for (const fields of [
  { apnsEnvironment: "sandbox", apnsToken: TOKEN_B },
  { apnsEnvironment: null, apnsToken: TOKEN_B },
  { apnsEnvironment: "Development", apnsToken: TOKEN_B },
  { apnsToken: "" },
  { apnsToken: "not-a-hex-token" },
  { apnsToken: "a".repeat(31) },
  { apnsToken: "a".repeat(201) },
]) {
  const label = "apnsEnvironment" in fields ? `environment ${JSON.stringify(fields.apnsEnvironment)}` : `token length ${fields.apnsToken.length}`;
  test(`invalid ${label} is rejected without changing a registration`, async (t) => {
    const f = fixture(t);
    assertOK(await f.register({ apnsEnvironment: "production" }));
    f.db.raw.prepare("UPDATE devices SET apns_blocked_reason = ? WHERE user_id = ? AND platform = ?")
      .run("Unregistered", USER_ID, "ios");
    const original = f.device();
    assert.equal((await f.register(fields)).status, 400);
    assert.deepEqual(f.device(), original);
    assert.equal(f.db.raw.prepare("SELECT COUNT(*) AS count FROM devices").get().count, 1);
  });
}

for (const fields of [{ apnsEnvironment: "production" }, {}]) {
  test(`fresh ${"apnsEnvironment" in fields ? "explicit" : "legacy same-token"} registration recovers a blocked device`, async (t) => {
    const f = fixture(t);
    assertOK(await f.register({ apnsEnvironment: "production" }));
    f.db.raw.prepare("UPDATE devices SET apns_blocked_reason = ? WHERE user_id = ? AND platform = ?")
      .run("Unregistered", USER_ID, "ios");
    const blocked = f.device();
    assertOK(await f.register(fields));
    const recovered = f.device();
    assert.equal(recovered.apns_blocked_reason, null);
    assert.equal(recovered.apns_environment, "production");
    assert.notEqual(recovered.registration_revision, blocked.registration_revision);
  });
}

for (const invalidFields of [
  { timezone: "Invalid/Timezone" },
  { schedule: { isEnabled: true, frequency: "daily", hour: 24, minute: 15 } },
  { schedule: { isEnabled: true, frequency: "daily", hour: 9, minute: -1 } },
  { schedule: { isEnabled: true, frequency: "weekly", hour: 9, minute: 15, weekday: 0 } },
]) {
  test(`invalid schedule ${JSON.stringify(invalidFields)} leaves an existing schedule intact`, async (t) => {
    const f = fixture(t);
    assertOK(await f.upsert());
    const original = { ...f.db.raw.prepare("SELECT * FROM schedules WHERE user_id = ?").get(USER_ID) };
    assert.equal((await f.upsert(invalidFields)).status, 400);
    assert.deepEqual({ ...f.db.raw.prepare("SELECT * FROM schedules WHERE user_id = ?").get(USER_ID) }, original);
  });
}
