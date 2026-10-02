import { afterEach, expect, it } from "vitest";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createVmEnvironment } from "../vm/runtime";
import { createSingleUserAccount } from "../vm/bootstrap";
import { startVmServer } from "../vm/server";
import { sha256Hex } from "../src/crypto";
import worker from "../src/index";

const root = resolve(import.meta.dirname, "..");
const origin = "https://account.example.test";
const password = "synthetic-owner-password-for-tests";
const folders: string[] = [];
afterEach(() => { for (const folder of folders.splice(0)) rmSync(folder, { recursive: true, force: true }); });
function setup() {
  const dir = mkdtempSync(join(tmpdir(), "healthmd-repair-drafts-test-")); folders.push(dir);
  const secret = () => Buffer.from(randomBytes(32)).toString("base64");
  const { env, db } = createVmEnvironment({ dataDirectory: dir, sourceDirectory: root,
    publicOrigin: origin, identityKey: secret(), exportKeys: JSON.stringify({ v1: secret() }),
    currentKeyId: "v1", passwordPepper: secret(), personalMvp: true, revisionRetention: "unlimited" });
  function req(path: string, method = "GET", cookie?: string, body?: unknown, from = origin) {
    return worker.fetch(new Request(`${origin}${path}`, { method, headers: {
      ...(cookie ? { Cookie: cookie } : {}), ...(body === undefined ? {} : {
        Origin: from, "Content-Type": "application/json", "X-HealthMd-Intent": "dashboard" }),
      ...(method === "DELETE" ? { Origin: from } : {}),
    }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }), env);
  }
  return { env, db, req };
}
const scope = { source: "ios", dates: ["2026-04-03", "2026-04-01"], scope: "metric_ids",
  metricIds: ["steps", "sleep_total"], detail: "summary" };

function ambiguousDraftDatabase(original: D1Database, options: {
  loseInsertResponse?: boolean; loseCancellationResponse?: boolean;
  failCreateVerification?: boolean; failCancellationVerification?: boolean;
}): D1Database {
  let insertLost = false;
  let cancellationLost = false;
  let createVerificationFailed = false;
  let cancellationVerificationFailed = false;
  return new Proxy(original, { get(target, property) {
    if (property === "batch") return async (statements: D1PreparedStatement[]) => {
      const result = await target.batch(statements);
      if (options.loseCancellationResponse && !cancellationLost) {
        cancellationLost = true;
        throw new Error("synthetic lost repair-draft cancellation response");
      }
      return result;
    };
    if (property === "prepare") return (query: string) => {
      const statement = target.prepare(query);
      return new Proxy(statement, { get(prepared, statementProperty) {
        if (statementProperty !== "bind") {
          const value = Reflect.get(prepared, statementProperty);
          return typeof value === "function" ? value.bind(prepared) : value;
        }
        return (...values: unknown[]) => {
          const bound = prepared.bind(...values);
          return new Proxy(bound, { get(boundStatement, boundProperty) {
            if (boundProperty === "run" && options.loseInsertResponse && !insertLost &&
                query.includes("INSERT INTO repair_drafts")) return async () => {
              const result = await boundStatement.run();
              insertLost = true;
              throw new Error("synthetic lost repair-draft creation response");
            };
            if (boundProperty === "first" && options.failCreateVerification &&
                !createVerificationFailed && query.includes("FROM repair_drafts WHERE id = ? AND user_id = ?")) {
              return async () => {
                createVerificationFailed = true;
                throw new Error("synthetic repair-draft creation verification outage");
              };
            }
            if (boundProperty === "first" && options.failCancellationVerification &&
                !cancellationVerificationFailed && query.includes("FROM repair_drafts d WHERE d.id = ?")) {
              return async () => {
                cancellationVerificationFailed = true;
                throw new Error("synthetic repair-draft cancellation verification outage");
              };
            }
            const value = Reflect.get(boundStatement, boundProperty);
            return typeof value === "function" ? value.bind(boundStatement) : value;
          } });
        };
      } });
    };
    const value = Reflect.get(target, property);
    return typeof value === "function" ? value.bind(target) : value;
  } }) as D1Database;
}

it("previews without inventing readings, encrypts owner-only drafts, and never exposes a launch route", async () => {
  const { env, db, req } = setup();
  await createSingleUserAccount(env, "pilot", "pilot@example.test", password);
  const login = await req("/api/auth/password-login", "POST", undefined, { username: "pilot", password });
  const cookie = login.headers.get("set-cookie")?.split(";")[0];
  expect(login.status).toBe(200);
  expect(cookie).toBeDefined();
  const account = await startVmServer(env, 0, "account");
  const ingest = await startVmServer(env, 0, "ingest");
  try {
    expect((await req("/api/repair/drafts", "GET")).status).toBe(401);
    expect((await req("/api/repair/preview", "POST", undefined, scope)).status).toBe(401);
    expect((await req("/repair", "GET")).status).toBe(303);
    expect((await req("/repair-panel", "GET")).status).toBe(303);
    expect((await req("/repair", "GET", cookie)).status).toBe(200);
    const panel = await req("/repair-panel", "GET", cookie);
    expect(panel.status).toBe(200);
    expect(await panel.text()).toContain("id=\"repair-form\"");
    expect((await req("/api/repair/preview", "POST", cookie, scope, "https://other.example.test")).status).toBe(403);
    expect((await req("/api/repair/drafts", "POST", cookie, scope, "https://other.example.test")).status).toBe(403);
    for (const bad of [
      { ...scope, dates: [] }, { ...scope, dates: Array.from({ length: 32 }, (_, i) =>
        `2026-03-${String(i + 1).padStart(2, "0")}`) },
      { ...scope, dates: ["2026-04-01", "2026-04-01"] },
      { ...scope, dates: ["2026-02-30"] },
      { ...scope, dates: ["9999-12-31"] },
      { ...scope, metricIds: ["hrv_rmssd_ms"] },
      { ...scope, metricIds: [] },
      { ...scope, source: "android" },
      { ...scope, source: "android", scope: "entire_days", metricIds: [], detail: "lossless" },
      { ...scope, scope: "entire_days", metricIds: ["steps"] },
    ]) expect((await req("/api/repair/drafts", "POST", cookie, bad)).status).toBe(400);
    const empty = await req("/api/repair/preview", "POST", cookie, scope);
    expect(empty.status).toBe(200);
    expect(empty.headers.get("cache-control")).toBe("no-store");
    const emptyBody = await empty.json() as { launchable: boolean; days: Array<{ coverage: string }> };
    expect(emptyBody.launchable).toBe(false);
    expect(emptyBody.days.map((day) => day.coverage)).toEqual(["not_uploaded", "not_uploaded"]);

    const issued = await req("/api/ingest-tokens", "POST", cookie, { name: "Fictional phone" });
    const bearer = (await issued.json() as { token: string }).token;
    expect((await worker.fetch(new Request(`${origin}/api/repair/drafts`, {
      headers: { Authorization: `Bearer ${bearer}` },
    }), env)).status).toBe(401);
    const fixture = JSON.parse(readFileSync(resolve(root, "../apple/docs/reference/generated/core/summary-day.json"), "utf8"));
    fixture.date = "2026-04-01"; fixture.activity.steps = 0;
    fixture.sleep.totalDuration = null;
    const upload = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify({ schema: "healthmd.api_export", schema_version: 1,
        daily_record_schema: "healthmd.health_data", daily_record_schema_version: 8,
        source: "ios", exported_at: "2026-04-04T00:00:00Z",
        date_range: { start: "2026-04-01", end: "2026-04-01" },
        record_count: 1, records: [fixture], failed_date_details: [] }),
    }), env);
    expect(upload.status).toBe(201);
    const evidence = await req("/api/repair/preview", "POST", cookie, scope);
    expect(evidence.status).toBe(200);
    expect((await evidence.json() as { days: unknown[] }).days).toMatchObject([
      { date: "2026-04-01", coverage: "uploaded_day", safety: "existing_day_requires_review",
        metrics: { steps: "observed", sleep_total: "value_unavailable_in_uploaded_summary" } },
      { date: "2026-04-03", coverage: "not_uploaded", safety: "new_day_only",
        metrics: { steps: "no_uploaded_day" } },
    ]);
    const androidUpload = await worker.fetch(new Request(`${origin}/api/v1/exports`, {
      method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify({ schema: "healthmd.api_export", schema_version: 1,
        daily_record_schema: "healthmd.health_data", daily_record_schema_version: 4,
        source: "android", exported_at: "2026-04-04T12:00:00Z",
        date_range: { start: "2026-04-03", end: "2026-04-03" },
        record_count: 1, records: [{ schema: "healthmd.health_data", schema_version: 4,
          date: "2026-04-03", activity: { steps: 42 } }], failed_date_details: [] }),
    }), env);
    expect(androidUpload.status).toBe(201);
    const conflicting = await req("/api/repair/preview", "POST", cookie, scope);
    expect((await conflicting.json() as { days: unknown[] }).days).toMatchObject([
      { date: "2026-04-01", coverage: "uploaded_day", safety: "existing_day_requires_review" },
      { date: "2026-04-03", coverage: "different_source", safety: "source_conflict", metrics: {} },
    ]);
    const create = await req("/api/repair/drafts", "POST", cookie, { ...scope,
      ignoredSensitiveNote: "synthetic must not be stored" });
    expect(create.status).toBe(201);
    const saved = await create.json() as { id: string; spec: typeof scope; launchable: boolean };
    expect(saved.launchable).toBe(false);
    expect(saved.spec.dates).toEqual(["2026-04-01", "2026-04-03"]);
    const raw = db.connection.prepare("SELECT spec_ciphertext AS ciphertext, spec_iv AS iv FROM repair_drafts WHERE id = ?")
      .get(saved.id) as { ciphertext: string; iv: string };
    expect(raw.ciphertext).not.toContain("2026-04-01");
    expect(raw.ciphertext).not.toContain("synthetic must not be stored");
    expect(raw.iv).not.toBe(raw.ciphertext);
    expect((await req("/api/repair/drafts", "GET", cookie)).status).toBe(200);
    const drafts = await req("/api/repair/drafts", "GET", cookie);
    expect((await drafts.json() as { requests: Array<{ id: string; spec: typeof scope }> }).requests)
      .toMatchObject([{ id: saved.id, spec: saved.spec }]);
    expect((await req(`/api/repair/drafts/${saved.id}/launch`, "POST", cookie, {})).status).toBe(404);
    expect((await req("/api/device/requests", "GET", cookie)).status).toBe(404);
    expect((await req("/api/repair/drafts", "GET", `__Host-healthmd_cloud_session=wrong`)).status).toBe(401);
    const otherId = randomUUID(); const now = new Date().toISOString();
    db.connection.prepare(`INSERT INTO users (id, email_lookup, email_ciphertext, email_iv, status, created_at)
      VALUES (?, ?, 'synthetic', 'synthetic', 'active', ?)`).run(otherId, randomUUID(), now);
    const otherToken = `hmd_ses_${Buffer.from(randomBytes(32)).toString("base64url")}`;
    db.connection.prepare(`INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?)`).run(randomUUID(), otherId, await sha256Hex(otherToken),
      new Date(Date.now() + 3600000).toISOString(), now, now);
    const otherCookie = `__Host-healthmd_cloud_session=${otherToken}`;
    expect((await (await req("/api/repair/drafts", "GET", otherCookie)).json() as { requests: unknown[] }).requests)
      .toEqual([]);
    expect((await req(`/api/repair/drafts/${saved.id}`, "DELETE", otherCookie)).status).toBe(404);
    expect((await req(`/api/repair/drafts/${saved.id}`, "DELETE", cookie, undefined,
      "https://other.example.test")).status).toBe(403);
    expect((await req(`/api/repair/drafts/${saved.id}`, "DELETE", cookie)).status).toBe(200);
    expect((await req(`/api/repair/drafts/${saved.id}`, "DELETE", cookie)).status).toBe(200);
    expect((await (await req("/api/repair/drafts", "GET", cookie)).json() as { requests: unknown[] }).requests)
      .toEqual([]);
    expect((db.connection.prepare("SELECT spec_ciphertext AS ciphertext FROM repair_drafts WHERE id = ?")
      .get(saved.id) as { ciphertext: string }).ciphertext).toBe("");
    const fullDay = { source: "android", dates: ["2026-04-03"], scope: "entire_days",
      metricIds: [], detail: "time_series" };
    const androidEvidence = await req("/api/repair/preview", "POST", cookie, fullDay);
    expect((await androidEvidence.json() as { days: unknown[] }).days).toMatchObject([
      { date: "2026-04-03", coverage: "uploaded_day", safety: "existing_day_requires_review" },
    ]);
    // Separate ingress must not accidentally expose account-only planning.
    const hit = async (port: number, path: string, method: string) => new Promise<number>((done, fail) => {
      import("node:http").then(({ request }) => {
        const call = request({ host: "127.0.0.1", port, path, method,
          headers: { Host: "account.example.test", "X-Forwarded-Host": "account.example.test",
            "X-Forwarded-Proto": "https" } }, (result) => { result.resume(); result.on("end", () => done(result.statusCode ?? 0)); });
        call.on("error", fail); call.end();
      }).catch(fail);
    });
    expect(await hit(account.port, "/api/repair/drafts", "GET")).toBe(401);
    expect(await hit(account.port, "/repair-panel", "GET")).toBe(303);
    expect(await hit(ingest.port, "/api/repair/drafts", "GET")).toBe(404);
    expect(await hit(ingest.port, "/repair-panel", "GET")).toBe(404);
    expect(await hit(ingest.port, "/repair", "GET")).toBe(404);
  } finally { await account.close(); await ingest.close(); db.close(); }
}, 30_000);

it("recovers lost repair-draft create and cancel responses through exact durable state", async () => {
  const { env, db, req } = setup();
  await createSingleUserAccount(env, "pilot", "pilot@example.test", password);
  const login = await req("/api/auth/password-login", "POST", undefined, { username: "pilot", password });
  const cookie = login.headers.get("set-cookie")!.split(";")[0];
  env.DB = ambiguousDraftDatabase(env.DB, { loseInsertResponse: true, loseCancellationResponse: true });
  try {
    const created = await req("/api/repair/drafts", "POST", cookie, scope);
    expect(created.status).toBe(201);
    const id = (await created.json() as { id: string }).id;
    expect((await req(`/api/repair/drafts/${id}`, "DELETE", cookie)).status).toBe(200);
    expect((await req(`/api/repair/drafts/${id}`, "DELETE", cookie)).status).toBe(200);
    expect(db.connection.prepare(`SELECT state, spec_ciphertext AS ciphertext, spec_iv AS iv
      FROM repair_drafts WHERE id = ?`).get(id)).toMatchObject({ state: "cancelled", ciphertext: "", iv: "" });
  } finally { db.close(); }
});

it("withholds draft success while durable creation or cancellation verification is unreadable", async () => {
  const { env, db, req } = setup();
  await createSingleUserAccount(env, "pilot", "pilot@example.test", password);
  const login = await req("/api/auth/password-login", "POST", undefined, { username: "pilot", password });
  const cookie = login.headers.get("set-cookie")!.split(";")[0];
  const original = env.DB;
  try {
    env.DB = ambiguousDraftDatabase(original, { failCreateVerification: true });
    const uncertainCreate = await req("/api/repair/drafts", "POST", cookie, scope);
    expect(uncertainCreate.status).toBe(503);
    expect((await uncertainCreate.json() as { error: string }).error).toBe("draft_verification_pending");
    const id = (db.connection.prepare("SELECT id FROM repair_drafts ORDER BY created_at DESC LIMIT 1")
      .get() as { id: string }).id;

    env.DB = ambiguousDraftDatabase(original, { failCancellationVerification: true });
    const uncertainCancel = await req(`/api/repair/drafts/${id}`, "DELETE", cookie);
    expect(uncertainCancel.status).toBe(503);
    expect((await uncertainCancel.json() as { error: string }).error).toBe("draft_cancellation_pending");
    env.DB = original;
    expect((await req(`/api/repair/drafts/${id}`, "DELETE", cookie)).status).toBe(200);
  } finally { env.DB = original; db.close(); }
});

it("bounds encrypted drafts, fails closed on tampering and erases expired scopes", async () => {
  const { env, db, req } = setup();
  await createSingleUserAccount(env, "pilot", "pilot@example.test", password);
  const login = await req("/api/auth/password-login", "POST", undefined, { username: "pilot", password });
  const cookie = login.headers.get("set-cookie")!.split(";")[0];
  const ids: string[] = [];
  try {
    for (let i = 0; i < 10; i++) {
      const response = await req("/api/repair/drafts", "POST", cookie, { ...scope,
        dates: [`2026-04-${String(i + 1).padStart(2, "0")}`] });
      expect(response.status).toBe(201);
      ids.push((await response.json() as { id: string }).id);
    }
    expect((await req("/api/repair/drafts", "POST", cookie, scope)).status).toBe(409);
    db.connection.prepare("UPDATE repair_drafts SET spec_ciphertext = 'invalid' WHERE id = ?").run(ids[0]!);
    expect((await req("/api/repair/drafts", "GET", cookie)).status).toBe(503);
    db.connection.prepare("UPDATE repair_drafts SET expires_at = '2000-01-01T00:00:00Z'").run();
    await worker.scheduled({} as ScheduledEvent, env);
    expect((await req("/api/repair/drafts", "GET", cookie)).status).toBe(200);
    expect(db.connection.prepare("SELECT COUNT(*) AS n FROM repair_drafts").get()).toMatchObject({ n: 0 });
  } finally { db.close(); }
}, 30_000);
