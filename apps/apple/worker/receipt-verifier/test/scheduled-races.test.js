import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/index.js";
import { handleScheduled } from "../src/scheduled.js";
import { baseEnv, makeCtx, makeDB, requestJSON } from "./helpers.js";

const USER_ID = "race_user_0000001";
const BUNDLE_ID = "com.codybontecou.obsidianhealth";
const FIRE = Date.parse("2026-10-07T08:20:00Z") / 1000;
const TOKEN_A = "ab".repeat(32);
const TOKEN_B = "cd".repeat(32);

function fixture(t) {
  const db = makeDB();
  t.after(() => db.raw.close());
  db.raw.prepare(`INSERT INTO devices
    (user_id, platform, apns_token, bundle_id, last_seen, apns_environment, registration_revision)
    VALUES (?, 'ios', ?, ?, ?, 'development', 'original-registration')`)
    .run(USER_ID, TOKEN_A, BUNDLE_ID, FIRE - 30);
  db.raw.prepare(`INSERT INTO schedules
    (user_id, is_enabled, frequency, hour, minute, weekday, timezone, next_fire_at, updated_at, revision)
    VALUES (?, 1, 'daily', 8, 20, NULL, 'UTC', ?, ?, 1)`)
    .run(USER_ID, FIRE, FIRE - 30);
  return { db, env: baseEnv(db) };
}

async function tick(env, sendPush) {
  const ctx = makeCtx();
  await handleScheduled({ scheduledTime: FIRE * 1000 }, env, ctx, { nowSec: FIRE, sendPush });
  await ctx.drain();
}

test("a 410 invalidation older than the current registration cannot block that registration", async (t) => {
  const { db, env } = fixture(t);
  const original = { ...db.raw.prepare("SELECT * FROM devices WHERE user_id = ?").get(USER_ID) };
  // APNs invalidated the token before this registration was received. The
  // current revision need not change merely because the same token refreshed.
  await tick(env, async () => ({
    status: 410,
    reason: "Unregistered",
    timestamp: (FIRE - 60) * 1000,
  }));
  const retained = db.raw.prepare("SELECT * FROM devices WHERE user_id = ?").get(USER_ID);
  assert.ok(retained, "the registration newer than APNs invalidation must remain");
  assert.equal(retained.registration_revision, original.registration_revision);
  assert.equal(retained.apns_token, original.apns_token);
  assert.equal(retained.apns_blocked_reason, null,
    "a stale APNs invalidation must not disable a newer registration");
});

test("schedule advancement atomically checks for registrations arriving after acceptance checks", async (t) => {
  const { db, env } = fixture(t);
  let registeredBeforeAdvance = false;

  function interpose(statement) {
    return {
      ...statement,
      bind(...values) {
        return interpose(statement.bind(...values));
      },
      async run() {
        if (!registeredBeforeAdvance) {
          registeredBeforeAdvance = true;
          const response = await worker.fetch(requestJSON("POST", "/devices/register", {
            userId: USER_ID,
            platform: "ios",
            apnsToken: TOKEN_B,
            bundleId: BUNDLE_ID,
            apnsEnvironment: "development",
          }), baseEnv(db));
          assert.equal(response.status, 200);
        }
        return statement.run();
      },
    };
  }

  env.DB = {
    ...db,
    prepare(sql) {
      const statement = db.prepare(sql);
      // Pause immediately before the schedule's final CAS executes, after
      // any earlier acceptance queries have already observed the old device.
      return /UPDATE\s+schedules\s+SET\s+next_fire_at/i.test(sql)
        ? interpose(statement)
        : statement;
    },
  };

  await tick(env, async () => ({ status: 200 }));
  assert.equal(registeredBeforeAdvance, true, "the registration must arrive before advancement");
  const current = db.raw.prepare("SELECT * FROM devices WHERE user_id = ?").get(USER_ID);
  assert.equal(current.apns_token, TOKEN_B);
  assert.notEqual(current.registration_revision, "original-registration");
  const accepted = db.raw.prepare(`SELECT COUNT(*) AS count FROM delivery_attempts
    WHERE user_id = ? AND registration_revision = ? AND state = 'accepted'`)
    .get(USER_ID, current.registration_revision).count;
  assert.equal(accepted, 0, "the replacement registration has not received this occurrence");
  assert.equal(db.raw.prepare("SELECT next_fire_at FROM schedules WHERE user_id = ?")
    .get(USER_ID).next_fire_at, FIRE,
  "the occurrence must remain due until the current registration receives it");
});
