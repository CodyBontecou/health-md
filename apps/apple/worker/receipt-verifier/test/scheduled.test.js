import test from "node:test";
import assert from "node:assert/strict";
import Worker from "../src/index.js";
import { handleScheduled } from "../src/scheduled.js";
import { makeDB, baseEnv, makeCtx } from "./helpers.js";

const USER = "scheduled_user_01";
const BUNDLE = "com.codybontecou.obsidianhealth";
const FIRE = Date.parse("2026-10-07T08:20:00Z") / 1000;
const IOS_TOKEN = "a".repeat(64);
const MAC_TOKEN = "b".repeat(64);
const NEW_TOKEN = "c".repeat(64);
const accepted = () => ({ status: 200, reason: null, apnsId: "synthetic-accepted-id" });

function fixture(t) {
  const db = makeDB();
  t.after(() => db.raw.close());
  return { db, env: baseEnv(db) };
}

function seedDevice(db, platform = "ios", environment = "development", token = IOS_TOKEN) {
  db.raw.prepare(`INSERT INTO devices
    (user_id, platform, apns_token, bundle_id, last_seen,
     apns_environment, registration_revision, apns_blocked_reason)
    VALUES (?, ?, ?, ?, ?, ?, ?, NULL)`)
    .run(USER, platform, token, BUNDLE, FIRE - 300, environment, `${platform}-revision-1`);
}

function seedSchedule(db) {
  db.raw.prepare(`INSERT INTO schedules
    (user_id, is_enabled, frequency, hour, minute, weekday, timezone,
     next_fire_at, updated_at, revision)
    VALUES (?, 1, 'daily', 8, 20, NULL, 'UTC', ?, ?, 1)`)
    .run(USER, FIRE, FIRE - 300);
}

function device(db, platform = "ios") {
  return db.raw.prepare("SELECT * FROM devices WHERE user_id = ? AND platform = ?").get(USER, platform);
}

function schedule(db) {
  return db.raw.prepare("SELECT * FROM schedules WHERE user_id = ?").get(USER);
}

function attempts(db) {
  return db.raw.prepare("SELECT * FROM delivery_attempts ORDER BY platform, fire_at").all();
}

function post(path, body) {
  return new Request(`https://synthetic-worker.invalid${path}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body)
  });
}

function registration(token = NEW_TOKEN, apnsEnvironment = "development") {
  return post("/devices/register", { userId: USER, platform: "ios", apnsToken: token,
    bundleId: BUNDLE, apnsEnvironment });
}

async function tick(env, nowSec, sendPush) {
  const ctx = makeCtx();
  await handleScheduled({ scheduledTime: nowSec * 1000, cron: "* * * * *" }, env, ctx,
    { nowSec, sendPush });
  await ctx.drain();
}

function deferred() {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
}

test("each recipient uses its registered APNs environment and stable fire time", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedDevice(db, "macos", "production", MAC_TOKEN);
  seedSchedule(db);
  const sent = [];
  await tick(env, FIRE + 44, async (_credentials, options) => {
    sent.push(options);
    return accepted();
  });
  assert.equal(sent.length, 2);
  assert.equal(sent.find(o => o.apnsToken === IOS_TOKEN).host, "api.sandbox.push.apple.com");
  assert.equal(sent.find(o => o.apnsToken === MAC_TOKEN).host, "api.push.apple.com");
  for (const options of sent) {
    assert.equal(options.bundleId, BUNDLE);
    assert.deepEqual(options.customPayload, {
      type: "scheduled-export", fireAt: new Date(FIRE * 1000).toISOString(), scheduleVersion: 1
    });
    assert.equal(options.expirationSec, FIRE + 3600);
  }
  assert.ok(attempts(db).every(a => a.state === "accepted"));
  assert.ok(schedule(db).next_fire_at > FIRE + 44);
});

test("unresolved legacy registrations retain existing production routing", async t => {
  const { db, env } = fixture(t);
  seedDevice(db, "ios", null);
  seedSchedule(db);
  const sent = [];
  await tick(env, FIRE, async (_credentials, options) => { sent.push(options); return accepted(); });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].host, "api.push.apple.com");
});

test("BadDeviceToken retains and blocks the registration instead of deleting it", async t => {
  const { db, env } = fixture(t);
  seedDevice(db, "ios", "production");
  seedSchedule(db);
  let sends = 0;
  const fail = async () => { sends++; return { status: 400, reason: "BadDeviceToken" }; };
  await tick(env, FIRE, fail);
  assert.equal(sends, 1);
  assert.equal(device(db).apns_token, IOS_TOKEN);
  assert.equal(device(db).apns_blocked_reason, "BadDeviceToken");
  assert.equal(attempts(db)[0].state, "blocked");
  assert.equal(attempts(db)[0].last_status, 400);
  assert.equal(attempts(db)[0].last_reason, "BadDeviceToken");
  await tick(env, FIRE + 60, fail);
  assert.equal(sends, 1);
});

test("fresh explicit registration recovers a blocked recipient on its next due send", async t => {
  const { db, env } = fixture(t);
  seedDevice(db, "ios", "production");
  seedSchedule(db);
  await tick(env, FIRE, async () => ({ status: 400, reason: "BadDeviceToken" }));
  const blockedRevision = device(db).registration_revision;
  const response = await Worker.fetch(registration(), env);
  assert.equal(response.status, 200);
  assert.equal(device(db).apns_blocked_reason, null);
  assert.equal(device(db).apns_environment, "development");
  assert.notEqual(device(db).registration_revision, blockedRevision);
  const sent = [];
  const next = Math.max(FIRE + 60, schedule(db).next_fire_at);
  await tick(env, next, async (_credentials, options) => { sent.push(options); return accepted(); });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].apnsToken, NEW_TOKEN);
  assert.equal(sent[0].host, "api.sandbox.push.apple.com");
  assert.equal(device(db).apns_blocked_reason, null);
});

test("a stale 410 response cannot block or delete a refreshed registration", async t => {
  const { db, env } = fixture(t);
  seedDevice(db, "ios", "production");
  seedSchedule(db);
  const started = deferred();
  const result = deferred();
  const pending = tick(env, FIRE, async () => { started.resolve(); return result.promise; });
  await started.promise;
  const response = await Worker.fetch(registration(), env);
  assert.equal(response.status, 200);
  const refreshed = device(db);
  result.resolve({ status: 410, reason: "Unregistered", timestamp: (FIRE - 60) * 1000 });
  await pending;
  assert.equal(device(db).apns_token, NEW_TOKEN);
  assert.equal(device(db).registration_revision, refreshed.registration_revision);
  assert.equal(device(db).apns_environment, "development");
  assert.equal(device(db).apns_blocked_reason, null);
});

test("mixed accepted and 503 recipients retry only the unsuccessful recipient", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedDevice(db, "macos", "production", MAC_TOKEN);
  seedSchedule(db);
  const sent = [];
  let failures = 1;
  const send = async (_credentials, options) => {
    sent.push(options.apnsToken);
    if (options.apnsToken === MAC_TOKEN && failures-- > 0) return { status: 503, reason: "ServiceUnavailable" };
    return accepted();
  };
  await tick(env, FIRE, send);
  assert.equal(sent.length, 2);
  assert.equal(attempts(db).find(a => a.platform === "ios").state, "accepted");
  const retry = attempts(db).find(a => a.platform === "macos");
  assert.equal(retry.state, "retry");
  assert.equal(retry.next_attempt_at, FIRE + 15 * 60);
  assert.equal(schedule(db).next_fire_at, FIRE);
  // A normal foreground registration must not invalidate the accepted sibling.
  assert.equal((await Worker.fetch(registration(IOS_TOKEN), env)).status, 200);
  await tick(env, FIRE + 60, send);
  assert.equal(sent.length, 2);
  await tick(env, retry.next_attempt_at, send);
  assert.deepEqual(sent.filter(token => token === IOS_TOKEN), [IOS_TOKEN]);
  assert.equal(sent.filter(token => token === MAC_TOKEN).length, 2);
  assert.ok(attempts(db).every(a => a.state === "accepted"));
  assert.ok(schedule(db).next_fire_at > retry.next_attempt_at);
});

test("overlapping cron invocations claim a recipient once while its request is pending", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedSchedule(db);
  const started = deferred();
  const result = deferred();
  let sends = 0;
  const send = async () => { sends++; started.resolve(); return result.promise; };
  const first = tick(env, FIRE, send);
  await started.promise;
  assert.equal(attempts(db)[0].state, "sending");
  assert.ok(attempts(db)[0].lease_until > FIRE);
  await tick(env, FIRE + 1, send);
  assert.equal(sends, 1);
  result.resolve(accepted());
  await first;
  assert.equal(attempts(db)[0].state, "accepted");
});

test("completion of an old request cannot overwrite an edited schedule", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedSchedule(db);
  const started = deferred();
  const result = deferred();
  const pending = tick(env, FIRE, async () => { started.resolve(); return result.promise; });
  await started.promise;
  const response = await Worker.fetch(post("/schedules/upsert", {
    userId: USER, timezone: "UTC", schedule: { isEnabled: true, frequency: "daily", hour: 17, minute: 45 }
  }), env);
  assert.equal(response.status, 200);
  const edited = schedule(db);
  assert.equal(edited.revision, 2);
  result.resolve(accepted());
  await pending;
  assert.equal(schedule(db).revision, edited.revision);
  assert.equal(schedule(db).next_fire_at, edited.next_fire_at);
  assert.equal(schedule(db).hour, 17);
  assert.equal(schedule(db).minute, 45);
});

test("completion of an old request cannot revive a disabled schedule", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedSchedule(db);
  const started = deferred();
  const result = deferred();
  const pending = tick(env, FIRE, async () => { started.resolve(); return result.promise; });
  await started.promise;
  const response = await Worker.fetch(post("/schedules/upsert", {
    userId: USER, timezone: "UTC", schedule: { isEnabled: false }
  }), env);
  assert.equal(response.status, 200);
  const disabled = schedule(db);
  assert.ok(disabled, "disabled schedule is retained to preserve its revision");
  assert.equal(disabled.is_enabled, 0);
  assert.equal(disabled.revision, 2);
  result.resolve(accepted());
  await pending;
  assert.deepEqual(schedule(db), disabled);
});

test("blocked earlier occurrences do not starve another due schedule", async t => {
  const { db, env } = fixture(t);
  const insertDevice = db.raw.prepare(`INSERT INTO devices
    (user_id, platform, apns_token, bundle_id, last_seen, apns_environment,
     registration_revision, apns_blocked_reason)
    VALUES (?, 'ios', ?, ?, ?, 'production', ?, 'BadDeviceToken')`);
  const insertSchedule = db.raw.prepare(`INSERT INTO schedules
    (user_id, is_enabled, frequency, hour, minute, weekday, timezone,
     next_fire_at, updated_at, revision)
    VALUES (?, 1, 'daily', 8, 19, NULL, 'UTC', ?, ?, 1)`);
  for (let i = 0; i < 100; i++) {
    const user = `blocked_schedule_${String(i).padStart(3, "0")}`;
    insertDevice.run(user, MAC_TOKEN, BUNDLE, FIRE - 300, `synthetic-revision-${i}`);
    insertSchedule.run(user, FIRE - 60, FIRE - 300);
  }
  seedDevice(db);
  seedSchedule(db);
  const sent = [];
  await tick(env, FIRE, async (_credentials, options) => { sent.push(options); return accepted(); });
  assert.equal(sent.length, 1, "blocked rows must not consume the complete cron batch");
  assert.equal(sent[0].apnsToken, IOS_TOKEN);
  assert.ok(schedule(db).next_fire_at > FIRE);
});

test("retry attempts are bounded and an expired occurrence sends no additional push", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedSchedule(db);
  let sends = 0;
  const fail = async () => { sends++; return { status: 503, reason: "ServiceUnavailable" }; };
  await tick(env, FIRE, fail);
  await tick(env, FIRE + 900, fail);
  await tick(env, FIRE + 1800, fail);
  assert.equal(sends, 3);
  assert.equal(attempts(db)[0].attempts, 3);
  await tick(env, FIRE + 2700, fail);
  assert.equal(sends, 3);
  await tick(env, FIRE + 3600, fail);
  assert.equal(sends, 3);
  assert.equal(attempts(db)[0].state, "expired");
  assert.ok(schedule(db).next_fire_at > FIRE + 3600);
});

test("deleting and re-registering the same token cannot let an old 410 delete the new row", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedSchedule(db);
  const started = deferred();
  const result = deferred();
  const pending = tick(env, FIRE, async () => { started.resolve(); return result.promise; });
  await started.promise;
  const deletion = await Worker.fetch(new Request(`https://synthetic-worker.invalid/devices/${USER}/ios`, {
    method: "DELETE"
  }), env);
  assert.equal(deletion.status, 200);
  assert.equal(device(db), undefined);
  assert.equal((await Worker.fetch(registration(IOS_TOKEN), env)).status, 200);
  const replacement = device(db);
  assert.notEqual(replacement.registration_revision, "ios-revision-1");
  result.resolve({ status: 410, reason: "Unregistered", timestamp: Date.now() + 60_000 });
  await pending;
  assert.equal(device(db).registration_revision, replacement.registration_revision);
  assert.equal(device(db).apns_token, IOS_TOKEN);
  assert.equal(device(db).apns_blocked_reason, null);
});

test("a later recipient's lease starts at its actual claim time", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedDevice(db, "macos", "production", MAC_TOKEN);
  seedSchedule(db);
  let now = FIRE;
  let sends = 0;
  const ctx = makeCtx();
  await handleScheduled({ scheduledTime: FIRE * 1000 }, env, ctx, {
    clock: () => now,
    sendPush: async (_credentials, options) => {
      sends++;
      if (options.apnsToken === IOS_TOKEN) now += 130;
      else {
        const currentClaim = attempts(db).find(a => a.platform === "macos");
        assert.ok(currentClaim.lease_until > now, "the lease must not expire during a prior recipient's work");
      }
      return accepted();
    }
  });
  await ctx.drain();
  assert.equal(sends, 2);
  assert.equal(attempts(db).find(a => a.platform === "macos").accepted_at, now);
});

test("a recipient is not sent after its occurrence expires during earlier work", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedDevice(db, "macos", "production", MAC_TOKEN);
  seedSchedule(db);
  let now = FIRE + 3599;
  const sent = [];
  const ctx = makeCtx();
  await handleScheduled({ scheduledTime: now * 1000 }, env, ctx, {
    clock: () => now,
    sendPush: async (_credentials, options) => {
      sent.push(options.apnsToken);
      now = FIRE + 3601;
      return accepted();
    }
  });
  await ctx.drain();
  assert.deepEqual(sent, [IOS_TOKEN]);
  assert.equal(attempts(db).some(a => a.platform === "macos"), false);
  await tick(env, now, async () => { assert.fail("an expired occurrence must not send"); });
  assert.ok(schedule(db).next_fire_at > now);
});

test("exhausted crashed claims do not starve a healthy due recipient", async t => {
  const { db, env } = fixture(t);
  const insertDevice = db.raw.prepare(`INSERT INTO devices
    (user_id, platform, apns_token, bundle_id, last_seen, apns_environment, registration_revision)
    VALUES (?, 'ios', ?, ?, ?, 'production', ?)`);
  const insertSchedule = db.raw.prepare(`INSERT INTO schedules
    (user_id, is_enabled, frequency, hour, minute, weekday, timezone, next_fire_at, updated_at, revision)
    VALUES (?, 1, 'daily', 8, 19, NULL, 'UTC', ?, ?, 1)`);
  const insertAttempt = db.raw.prepare(`INSERT INTO delivery_attempts
    (user_id, platform, fire_at, schedule_revision, registration_revision, state,
     attempts, next_attempt_at, lease_until, claim_id)
    VALUES (?, 'ios', ?, 1, ?, 'sending', 3, 0, ?, 'crashed-third-claim')`);
  for (let i = 0; i < 100; i++) {
    const user = `crashed_schedule_${String(i).padStart(3, "0")}`;
    const revision = `synthetic-crash-revision-${i}`;
    insertDevice.run(user, MAC_TOKEN, BUNDLE, FIRE - 300, revision);
    insertSchedule.run(user, FIRE - 60, FIRE - 300);
    insertAttempt.run(user, FIRE - 60, revision, FIRE - 1);
  }
  seedDevice(db);
  seedSchedule(db);
  const sent = [];
  await tick(env, FIRE, async (_credentials, options) => { sent.push(options); return accepted(); });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].apnsToken, IOS_TOKEN);
  assert.ok(schedule(db).next_fire_at > FIRE);
});

test("a same-second refresh survives a 410 timestamp from earlier in that second", async t => {
  const { db, env } = fixture(t);
  seedDevice(db);
  seedSchedule(db);
  db.raw.prepare("UPDATE devices SET last_seen = ? WHERE user_id = ?").run(FIRE, USER);
  t.mock.method(Date, "now", () => FIRE * 1000 + 900);
  await tick(env, FIRE, async () => {
    assert.equal((await Worker.fetch(registration(IOS_TOKEN), env)).status, 200);
    return { status: 410, reason: "Unregistered", timestamp: FIRE * 1000 + 500 };
  });
  assert.ok(device(db), "seconds-only registration time cannot prove ordering within this second");
  assert.equal(device(db).apns_blocked_reason, null);
});
