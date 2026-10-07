import { apnsHost, sendSilentPush } from "./apns.js";
import { computeNextFire } from "./scheduling.js";

const DELIVERY_WINDOW_SEC = 3600;
const RETRY_DELAY_SEC = 15 * 60;
const MAX_ATTEMPTS = 3;
const LEASE_SEC = 120;
const TOKEN_ERRORS = new Set(["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered", "ExpiredToken"]);

function key(row) {
  return [row.user_id, row.platform, row.next_fire_at, row.revision, row.registration_revision];
}

async function deliver(row, env, clock, sendPush) {
  const now = clock();
  if (now >= row.next_fire_at + DELIVERY_WINDOW_SEC) return;
  const db = env.DB;
  const claim = crypto.randomUUID();
  // D1 serializes this statement. A second cron tick cannot acquire an active
  // lease, accepted recipient, permanent rejection, or exhausted retry.
  const claimed = await db.prepare(`
    INSERT INTO delivery_attempts
      (user_id, platform, fire_at, schedule_revision, registration_revision,
       state, attempts, next_attempt_at, lease_until, claim_id)
    SELECT ?, ?, ?, ?, ?, 'sending', 1, 0, ?, ?
      WHERE EXISTS (SELECT 1 FROM schedules WHERE user_id = ? AND is_enabled = 1
        AND next_fire_at = ? AND revision = ?)
      AND EXISTS (SELECT 1 FROM devices WHERE user_id = ? AND platform = ?
        AND registration_revision = ? AND apns_blocked_reason IS NULL)
    ON CONFLICT(user_id, platform, fire_at, schedule_revision, registration_revision)
    DO UPDATE SET state = 'sending', attempts = delivery_attempts.attempts + 1,
      lease_until = excluded.lease_until, claim_id = excluded.claim_id
    WHERE (delivery_attempts.state = 'retry' AND delivery_attempts.next_attempt_at <= ?
       OR delivery_attempts.state = 'sending' AND delivery_attempts.lease_until <= ?)
      AND delivery_attempts.attempts < ?
    RETURNING attempts
  `).bind(...key(row), now + LEASE_SEC, claim, row.user_id, row.next_fire_at,
    row.revision, row.user_id, row.platform, row.registration_revision, now, now, MAX_ATTEMPTS).first();
  if (!claimed) return;
  let result;
  try {
    result = await sendPush({ authKey: env.APNS_AUTH_KEY, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID }, {
      host: apnsHost(row.apns_environment), apnsToken: row.apns_token, bundleId: row.bundle_id,
      customPayload: { type: "scheduled-export", fireAt: new Date(row.next_fire_at * 1000).toISOString(), scheduleVersion: 1 },
      expirationSec: row.next_fire_at + DELIVERY_WINDOW_SEC
    });
  } catch {
    // Do not log transport errors: they can contain token-bearing URLs.
    result = { status: 0, reason: "TransportError" };
  }
  const accepted = result.status === 200;
  const completedAt = clock();
  const transient = result.status === 0 || result.status === 429 || result.status >= 500;
  const state = accepted ? "accepted" : transient && claimed.attempts < MAX_ATTEMPTS ? "retry" : "blocked";
  await db.prepare(`UPDATE delivery_attempts SET state = ?, next_attempt_at = ?, lease_until = 0,
    last_status = ?, last_reason = ?, accepted_at = ?
    WHERE user_id = ? AND platform = ? AND fire_at = ? AND schedule_revision = ?
      AND registration_revision = ? AND claim_id = ?`)
    .bind(state, transient ? completedAt + RETRY_DELAY_SEC : 0, result.status, result.reason ?? null,
      accepted ? completedAt : null, ...key(row), claim).run();

  if (result.status === 410 && Number.isFinite(result.timestamp)) {
    // APNs timestamps are milliseconds. A response for an old token must never
    // delete a registration refreshed while the network request was in flight.
    await db.prepare(`DELETE FROM devices WHERE user_id = ? AND platform = ?
      AND registration_revision = ? AND apns_token = ? AND apns_environment IS ?
      AND (last_seen + 1) * 1000 <= ?`)
      .bind(row.user_id, row.platform, row.registration_revision, row.apns_token,
        row.apns_environment, result.timestamp).run();
  }
  if (result.status === 410 && Number.isFinite(result.timestamp)) {
    await db.prepare(`UPDATE devices SET apns_blocked_reason = ?
      WHERE user_id = ? AND platform = ? AND registration_revision = ? AND (last_seen + 1) * 1000 <= ?`)
      .bind(result.reason ?? "Unregistered", row.user_id, row.platform, row.registration_revision,
        result.timestamp).run();
  } else if (result.status !== 410 && TOKEN_ERRORS.has(result.reason)) {
    // BadDeviceToken can mean an environment mismatch, not a dead installation.
    // Retain it for explicit environment registration; never probe another host.
    await db.prepare(`UPDATE devices SET apns_blocked_reason = ?
      WHERE user_id = ? AND platform = ? AND registration_revision = ? AND last_seen <= ?`)
      .bind(result.reason ?? "Unregistered", row.user_id, row.platform, row.registration_revision,
        row.last_seen).run();
  }
  console.log(JSON.stringify({ route: "scheduled", platform: row.platform,
    environment: row.apns_environment ?? "legacy-production", status: result.status,
    reason: result.reason ?? null, apnsId: result.apnsId ?? null,
    fireAt: new Date(row.next_fire_at * 1000).toISOString(), deliveryState: state }));
}

async function processOccurrence(schedule, env, clock, sendPush) {
  const db = env.DB;
  let now = clock();
  if (now >= schedule.next_fire_at + DELIVERY_WINDOW_SEC) {
    await db.prepare(`UPDATE delivery_attempts SET state = 'expired', lease_until = 0
      WHERE user_id = ? AND fire_at = ? AND schedule_revision = ? AND state != 'accepted'`)
      .bind(schedule.user_id, schedule.next_fire_at, schedule.revision).run();
    console.warn(JSON.stringify({ route: "scheduled", deliveryState: "expired",
      fireAt: new Date(schedule.next_fire_at * 1000).toISOString() }));
  } else {
    const { results: devices } = await db.prepare("SELECT * FROM devices WHERE user_id = ?")
      .bind(schedule.user_id).all();
    if (!devices?.length) return;
    // Serial within one occurrence limits APNs load and keeps mixed-platform
    // acceptance independently durable; claims also protect overlapping ticks.
    for (const device of devices) {
      if (!device.apns_blocked_reason) await deliver({ ...schedule, ...device }, env, clock, sendPush);
    }
    // Compare current registrations rather than the initial snapshot, so a new
    // token registered during a send is not counted as accepted by an old token.
    const pending = await db.prepare(`SELECT COUNT(*) AS count FROM devices d
      WHERE d.user_id = ? AND NOT EXISTS (SELECT 1 FROM delivery_attempts a
        WHERE a.user_id = d.user_id AND a.platform = d.platform AND a.fire_at = ?
          AND a.schedule_revision = ? AND a.registration_revision = d.registration_revision
          AND a.state = 'accepted')`)
      .bind(schedule.user_id, schedule.next_fire_at, schedule.revision).first();
    const accepted = await db.prepare(`SELECT COUNT(*) AS count FROM delivery_attempts
      WHERE user_id = ? AND fire_at = ? AND schedule_revision = ? AND state = 'accepted'`)
      .bind(schedule.user_id, schedule.next_fire_at, schedule.revision).first();
    if (pending.count !== 0 || accepted.count === 0) return;
  }
  now = clock();
  const next = computeNextFire({ frequency: schedule.frequency, hour: schedule.hour,
    minute: schedule.minute, ...(schedule.weekday !== null ? { weekday: schedule.weekday } : {}) }, schedule.timezone, now);
  await db.prepare(`UPDATE schedules SET next_fire_at = ?, updated_at = ?
    WHERE user_id = ? AND is_enabled = 1 AND next_fire_at = ? AND revision = ?
      AND (? >= next_fire_at + ? OR (
        NOT EXISTS (SELECT 1 FROM devices d WHERE d.user_id = schedules.user_id
          AND NOT EXISTS (SELECT 1 FROM delivery_attempts a WHERE a.user_id = d.user_id
            AND a.platform = d.platform AND a.fire_at = schedules.next_fire_at
            AND a.schedule_revision = schedules.revision
            AND a.registration_revision = d.registration_revision AND a.state = 'accepted'))
        AND EXISTS (SELECT 1 FROM delivery_attempts a WHERE a.user_id = schedules.user_id
          AND a.fire_at = schedules.next_fire_at AND a.schedule_revision = schedules.revision
          AND a.state = 'accepted'))) `)
    .bind(next, now, schedule.user_id, schedule.next_fire_at, schedule.revision, now, DELIVERY_WINDOW_SEC).run();
}

export async function handleScheduled(event, env, ctx, dependencies = {}) {
  if (!env.DB || !env.APNS_AUTH_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) {
    console.error("APNs credentials or D1 binding not configured; skipping scheduled tick");
    return;
  }
  // Invocation time can lag scheduledTime; never hand APNs an expired push.
  const clock = dependencies.clock ?? (() => dependencies.nowSec ?? Math.floor(Date.now() / 1000));
  const now = clock();
  const sendPush = dependencies.sendPush ?? sendSilentPush;
  const work = (async () => {
    // Skip blocked/backing-off occurrences when choosing this tick's batch;
    // otherwise older failures can starve healthy due schedules behind LIMIT.
    const { results } = await env.DB.prepare(`SELECT s.* FROM schedules s
      WHERE s.is_enabled = 1 AND s.next_fire_at <= ? AND (
        s.next_fire_at + ? <= ? OR EXISTS (
          SELECT 1 FROM devices d WHERE d.user_id = s.user_id AND d.apns_blocked_reason IS NULL
            AND NOT EXISTS (SELECT 1 FROM delivery_attempts a WHERE a.user_id = d.user_id
              AND a.platform = d.platform AND a.fire_at = s.next_fire_at
              AND a.schedule_revision = s.revision AND a.registration_revision = d.registration_revision
              AND (a.state IN ('accepted', 'blocked', 'expired')
                OR a.attempts >= ?
                OR a.state = 'retry' AND a.next_attempt_at > ?
                OR a.state = 'sending' AND a.lease_until > ?)))
        OR (NOT EXISTS (SELECT 1 FROM devices d WHERE d.user_id = s.user_id
          AND NOT EXISTS (SELECT 1 FROM delivery_attempts a WHERE a.user_id = d.user_id
            AND a.platform = d.platform AND a.fire_at = s.next_fire_at
            AND a.schedule_revision = s.revision AND a.registration_revision = d.registration_revision
            AND a.state = 'accepted'))
          AND EXISTS (SELECT 1 FROM delivery_attempts a WHERE a.user_id = s.user_id
            AND a.fire_at = s.next_fire_at AND a.schedule_revision = s.revision AND a.state = 'accepted')))
      ORDER BY s.next_fire_at LIMIT 100`).bind(now, DELIVERY_WINDOW_SEC, now, MAX_ATTEMPTS, now, now).all();
    for (let offset = 0; offset < (results?.length ?? 0); offset += 5) {
      await Promise.all(results.slice(offset, offset + 5).map(async schedule => {
        try { await processOccurrence(schedule, env, clock, sendPush); }
        catch { console.error("Scheduled occurrence processing failed; retained for next tick"); }
      }));
    }
    // Delivery metadata has bounded retention and contains no health payloads.
    await env.DB.prepare("DELETE FROM delivery_attempts WHERE fire_at < ?").bind(now - 30 * 86400).run();
  })();
  ctx.waitUntil(work);
  await work;
}
