import { computeNextFire } from "./scheduling.js";

const BUNDLE_ID = "com.codybontecou.obsidianhealth";
const USER_ID_RE = /^[A-Za-z0-9_-]{16,64}$/;
const APNS_TOKEN_RE = /^[A-Fa-f0-9]{32,200}$/;
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" }
  });
}
async function bodyOf(request) {
  try { return await request.json(); } catch { return null; }
}
function validUser(userId) { return typeof userId === "string" && USER_ID_RE.test(userId); }
function integer(n, lo, hi) { return Number.isInteger(n) && n >= lo && n <= hi; }

export async function handleRegisterDevice(request, env) {
  const body = await bodyOf(request);
  if (!body || typeof body !== "object") return json({ error: "Invalid JSON body" }, 400);
  const { userId, platform, apnsToken, bundleId, apnsEnvironment } = body;
  if (!validUser(userId)) return json({ error: "Invalid userId" }, 400);
  if (platform !== "ios" && platform !== "macos") return json({ error: "Invalid platform" }, 400);
  if (typeof apnsToken !== "string" || !APNS_TOKEN_RE.test(apnsToken)) return json({ error: "Invalid apnsToken" }, 400);
  if (bundleId !== BUNDLE_ID) return json({ error: "Bundle ID mismatch" }, 400);
  if (apnsEnvironment !== undefined && apnsEnvironment !== "development" && apnsEnvironment !== "production") {
    return json({ error: "Invalid apnsEnvironment" }, 400);
  }
  await env.DB.prepare(`
    INSERT INTO devices (user_id, platform, apns_token, bundle_id, last_seen, apns_environment, registration_revision)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id, platform) DO UPDATE SET
      registration_revision = CASE
        WHEN devices.apns_token != excluded.apns_token OR devices.bundle_id != excluded.bundle_id
          OR (excluded.apns_environment IS NOT NULL AND devices.apns_environment IS NOT excluded.apns_environment)
          OR devices.apns_blocked_reason IS NOT NULL
        THEN excluded.registration_revision ELSE devices.registration_revision END,
      apns_environment = CASE
        WHEN excluded.apns_environment IS NOT NULL THEN excluded.apns_environment
        WHEN devices.apns_token = excluded.apns_token AND devices.bundle_id = excluded.bundle_id
          THEN devices.apns_environment ELSE NULL END,
      apns_token = excluded.apns_token, bundle_id = excluded.bundle_id,
      last_seen = excluded.last_seen,
      apns_blocked_reason = NULL
  `).bind(userId, platform, apnsToken.toLowerCase(), bundleId, Math.floor(Date.now() / 1000), apnsEnvironment ?? null, crypto.randomUUID()).run();
  return json({ ok: true });
}

export async function handleUpsertSchedule(request, env) {
  const body = await bodyOf(request);
  if (!body || typeof body !== "object") return json({ error: "Invalid JSON body" }, 400);
  const { userId, timezone, schedule } = body;
  if (!validUser(userId)) return json({ error: "Invalid userId" }, 400);
  try {
    if (typeof timezone !== "string" || !timezone) throw new Error();
    new Intl.DateTimeFormat("en-US", { timeZone: timezone });
  } catch { return json({ error: "Invalid timezone" }, 400); }
  if (!schedule || typeof schedule !== "object") return json({ error: "Missing schedule" }, 400);
  if (schedule.isEnabled === false) {
    await env.DB.prepare("UPDATE schedules SET is_enabled = 0, revision = revision + 1, updated_at = ? WHERE user_id = ?")
      .bind(Math.floor(Date.now() / 1000), userId).run();
    return json({ ok: true, isEnabled: false });
  }
  if (schedule.frequency !== "daily" && schedule.frequency !== "weekly") return json({ error: "Invalid frequency" }, 400);
  if (!integer(schedule.hour, 0, 23)) return json({ error: "Invalid hour" }, 400);
  if (!integer(schedule.minute, 0, 59)) return json({ error: "Invalid minute" }, 400);
  if (schedule.frequency === "weekly" && !integer(schedule.weekday, 1, 7)) return json({ error: "Weekly schedule requires weekday in [1,7]" }, 400);
  const now = Math.floor(Date.now() / 1000);
  const next = computeNextFire(schedule, timezone, now);
  await env.DB.prepare(`
    INSERT INTO schedules (user_id, is_enabled, frequency, hour, minute, weekday, timezone, next_fire_at, updated_at, revision)
    VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?, 1)
    ON CONFLICT(user_id) DO UPDATE SET is_enabled = 1, frequency = excluded.frequency,
      hour = excluded.hour, minute = excluded.minute, weekday = excluded.weekday,
      timezone = excluded.timezone, next_fire_at = excluded.next_fire_at,
      updated_at = excluded.updated_at, revision = schedules.revision + 1
  `).bind(userId, schedule.frequency, schedule.hour, schedule.minute,
    schedule.frequency === "weekly" ? schedule.weekday : null, timezone, next, now).run();
  return json({ ok: true, nextFireAt: next });
}

export async function routeNotificationRequest(request, env) {
  const { pathname } = new URL(request.url);
  const deletion = request.method === "DELETE" && pathname.match(/^\/devices\/([^/]+)\/([^/]+)$/);
  const registration = request.method === "POST" && pathname === "/devices/register";
  const upsert = request.method === "POST" && pathname === "/schedules/upsert";
  if (!deletion && !registration && !upsert) return null;
  if (!env.DB) return json({ error: "D1 binding not configured" }, 503);
  if (registration) return handleRegisterDevice(request, env);
  if (upsert) return handleUpsertSchedule(request, env);
  let userId, platform;
  try { userId = decodeURIComponent(deletion[1]); platform = decodeURIComponent(deletion[2]); }
  catch { return json({ error: "Invalid device path" }, 400); }
  if (!validUser(userId)) return json({ error: "Invalid userId" }, 400);
  if (platform !== "ios" && platform !== "macos") return json({ error: "Invalid platform" }, 400);
  await env.DB.prepare("DELETE FROM devices WHERE user_id = ? AND platform = ?").bind(userId, platform).run();
  return json({ ok: true });
}
