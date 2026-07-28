import assert from "node:assert/strict";
import test from "node:test";

import worker from "../cloudflare/attribution-worker/src/worker.js";

const env = {
  APP_STORE_BASE_URL: "https://apps.apple.com/us/app/health-md/id6757763969",
  PLAY_STORE_BASE_URL: "https://play.google.com/store/apps/details?id=com.healthmd.android",
  DOWNLOAD_PAGE_URL: "https://healthmd.app/",
  APPLE_PROVIDER_TOKEN: "123456",
  CPP_CSV_PPID: "csv-product-page",
};

const context = {
  waitUntil(promise) {
    return promise;
  },
};

class FakeD1Statement {
  constructor(database, sql) {
    this.database = database;
    this.sql = sql.replace(/\s+/g, " ").trim();
    this.values = [];
  }

  bind(...values) {
    this.values = values;
    return this;
  }

  async first() {
    if (this.sql.startsWith("INSERT INTO campaign_ingest_windows")) {
      this.database.rateCount += 1;
      return { request_count: this.database.rateCount };
    }
    if (this.sql.startsWith("SELECT * FROM campaign_installs WHERE event_id")) {
      return this.database.events.get(this.values[0]) || null;
    }
    throw new Error(`Unexpected D1 first(): ${this.sql}`);
  }

  async run() {
    if (this.sql.startsWith("DELETE FROM campaign_ingest_windows")) {
      return { meta: { changes: 0 } };
    }
    if (!this.sql.startsWith("INSERT OR IGNORE INTO campaign_installs")) {
      throw new Error(`Unexpected D1 run(): ${this.sql}`);
    }

    const [
      eventId,
      installId,
      eventName,
      occurredAt,
      platform,
      appVersion,
      buildNumber,
      campaignToken,
      source,
      medium,
      contentAngle,
      referrerClickTimestampSeconds,
      installBeginTimestampSeconds,
      receivedAt,
    ] = this.values;
    if (this.database.events.has(eventId) || this.database.installIds.has(installId)) {
      return { meta: { changes: 0 } };
    }
    const row = {
      event_id: eventId,
      install_id: installId,
      event_name: eventName,
      occurred_at: occurredAt,
      platform,
      app_version: appVersion,
      build_number: buildNumber,
      campaign_token: campaignToken,
      source,
      medium,
      content_angle: contentAngle,
      referrer_click_timestamp_seconds: referrerClickTimestampSeconds,
      install_begin_timestamp_seconds: installBeginTimestampSeconds,
      received_at: receivedAt,
    };
    this.database.events.set(eventId, row);
    this.database.installIds.add(installId);
    return { meta: { changes: 1 } };
  }
}

class FakeD1Database {
  constructor() {
    this.events = new Map();
    this.installIds = new Set();
    this.rateCount = 0;
    this.batchStatements = [];
  }

  prepare(sql) {
    return new FakeD1Statement(this, sql);
  }

  async batch(statements) {
    this.batchStatements = statements;
    return statements.map(() => ({ meta: { changes: 0 } }));
  }
}

function validInstallEvent(overrides = {}) {
  return {
    schemaVersion: 1,
    eventId: "22222222-2222-4222-8222-222222222222",
    installId: "11111111-1111-4111-8111-111111111111",
    eventName: "campaign_install_attributed",
    occurredAt: "2026-07-14T12:00:00Z",
    platform: "android",
    appVersion: "1.5.1",
    buildNumber: "19",
    campaignToken: "yt_csv_001",
    source: "yt",
    medium: "campaign_shortlink",
    contentAngle: "csv",
    referrerClickTimestampSeconds: 1234567890,
    installBeginTimestampSeconds: 1234567900,
    ...overrides,
  };
}

function installRequest(payload, { token = "throttle-token", method = "POST" } = {}) {
  return new Request("https://healthmd.app/v1/installs", {
    method,
    headers: {
      "content-type": "application/json",
      ...(token === null ? {} : { authorization: `Bearer ${token}` }),
    },
    body: method === "POST" ? JSON.stringify(payload) : undefined,
  });
}

async function campaignRedirect(userAgent, extraHeaders = {}) {
  const response = await worker.fetch(
    new Request("https://healthmd.app/v/yt-csv-001", {
      headers: {
        "user-agent": userAgent,
        ...extraHeaders,
      },
    }),
    env,
    context,
  );

  assert.equal(response.status, 302);
  return {
    response,
    location: new URL(response.headers.get("location")),
  };
}

test("valid Android install attribution is stored with only allowlisted fields", async () => {
  const database = new FakeD1Database();
  const response = await worker.fetch(
    installRequest(validInstallEvent()),
    { ...env, DB: database, CAMPAIGN_ATTRIBUTION_INGEST_TOKEN: "throttle-token" },
    context,
  );

  assert.equal(response.status, 202);
  assert.deepEqual(await response.json(), { accepted: true, duplicate: false });
  assert.equal(database.events.size, 1);
  const [row] = database.events.values();
  assert.equal(row.campaign_token, "yt_csv_001");
  assert.equal(row.install_id, "11111111-1111-4111-8111-111111111111");
  assert.equal("raw_referrer" in row, false);
  assert.equal("ip_address" in row, false);
  assert.equal("user_agent" in row, false);
  assert.equal("device_model" in row, false);
});

test("duplicate event IDs are idempotent and return 2xx", async () => {
  const database = new FakeD1Database();
  const ingestEnv = {
    ...env,
    DB: database,
    CAMPAIGN_ATTRIBUTION_INGEST_TOKEN: "throttle-token",
  };

  const first = await worker.fetch(installRequest(validInstallEvent()), ingestEnv, context);
  const duplicate = await worker.fetch(installRequest(validInstallEvent()), ingestEnv, context);

  assert.equal(first.status, 202);
  assert.equal(duplicate.status, 200);
  assert.deepEqual(await duplicate.json(), { accepted: true, duplicate: true });
  assert.equal(database.events.size, 1);
});

test("event or install ID reuse with different content is rejected", async () => {
  const database = new FakeD1Database();
  const ingestEnv = {
    ...env,
    DB: database,
    CAMPAIGN_ATTRIBUTION_INGEST_TOKEN: "throttle-token",
  };
  await worker.fetch(installRequest(validInstallEvent()), ingestEnv, context);

  const response = await worker.fetch(
    installRequest(validInstallEvent({ appVersion: "1.5.2" })),
    ingestEnv,
    context,
  );

  assert.equal(response.status, 409);
  assert.equal(database.events.size, 1);
});

test("install ingest rejects unknown, raw, malformed, and mismatched campaign fields", async () => {
  const invalidPayloads = [
    validInstallEvent({ rawReferrer: "utm_source=yt&private=value" }),
    validInstallEvent({ healthData: { steps: 1234 } }),
    validInstallEvent({ campaignToken: "yt_privacy_001" }),
    validInstallEvent({ medium: "cpc" }),
    validInstallEvent({ eventId: "not-a-uuid" }),
  ];

  for (const payload of invalidPayloads) {
    const response = await worker.fetch(
      installRequest(payload, { token: null }),
      {
        ...env,
        DB: new FakeD1Database(),
        ALLOW_UNAUTHENTICATED_INGEST: "true",
      },
      context,
    );
    assert.equal(response.status, 400);
  }
});

test("install ingest fails closed when no token is configured", async () => {
  const response = await worker.fetch(
    installRequest(validInstallEvent(), { token: null }),
    { ...env, DB: new FakeD1Database() },
    context,
  );

  assert.equal(response.status, 503);
});

test("install ingest accepts the previous token during rotation", async () => {
  const response = await worker.fetch(
    installRequest(validInstallEvent()),
    {
      ...env,
      DB: new FakeD1Database(),
      CAMPAIGN_ATTRIBUTION_INGEST_TOKEN: "new-token",
      CAMPAIGN_ATTRIBUTION_INGEST_TOKEN_PREVIOUS: "throttle-token",
    },
    context,
  );

  assert.equal(response.status, 202);
});

test("install ingest rejects query parameters at the routed endpoint", async () => {
  const response = await worker.fetch(
    new Request("https://healthmd.app/v1/installs?unexpected=true", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(validInstallEvent()),
    }),
    { ...env, DB: new FakeD1Database(), ALLOW_UNAUTHENTICATED_INGEST: "true" },
    context,
  );

  assert.equal(response.status, 400);
});

test("install ingest enforces token, body size, method, and aggregate rate limit", async () => {
  const database = new FakeD1Database();
  const protectedEnv = {
    ...env,
    DB: database,
    CAMPAIGN_ATTRIBUTION_INGEST_TOKEN: "throttle-token",
  };

  const unauthorized = await worker.fetch(
    installRequest(validInstallEvent(), { token: null }),
    protectedEnv,
    context,
  );
  assert.equal(unauthorized.status, 401);

  const oversized = await worker.fetch(
    installRequest(validInstallEvent({ padding: "x".repeat(5_000) })),
    protectedEnv,
    context,
  );
  assert.equal(oversized.status, 413);

  const wrongMethod = await worker.fetch(
    installRequest(validInstallEvent(), { method: "GET" }),
    protectedEnv,
    context,
  );
  assert.equal(wrongMethod.status, 405);

  database.rateCount = 300;
  const rateLimited = await worker.fetch(
    installRequest(validInstallEvent()),
    protectedEnv,
    context,
  );
  assert.equal(rateLimited.status, 429);
  assert.equal(rateLimited.headers.get("retry-after"), "60");
});

test("scheduled retention deletes only expired aggregate attribution state", async () => {
  const database = new FakeD1Database();
  let retentionPromise;
  worker.scheduled(
    { scheduledTime: Date.parse("2026-03-31T04:17:00Z") },
    { ...env, DB: database },
    { waitUntil(promise) { retentionPromise = promise; } },
  );
  await retentionPromise;

  assert.equal(database.batchStatements.length, 3);
  const statements = database.batchStatements.map((statement) => statement.sql);
  assert.ok(statements.some((sql) => sql.startsWith("DELETE FROM campaign_clicks")));
  assert.ok(statements.some((sql) => sql.startsWith("DELETE FROM campaign_installs")));
  assert.ok(statements.some((sql) => sql.startsWith("DELETE FROM campaign_ingest_windows")));
  assert.equal(statements.some((sql) => /ip|user_agent|request_id/i.test(sql)), false);
  const clickDelete = database.batchStatements.find((statement) =>
    statement.sql.startsWith("DELETE FROM campaign_clicks"));
  const rateDelete = database.batchStatements.find((statement) =>
    statement.sql.startsWith("DELETE FROM campaign_ingest_windows"));
  assert.equal(clickDelete.values[0], "2025-02-28T04:17:00.000Z");
  assert.equal(rateDelete.values[0], "2026-03-30T04:17:00.000Z");
});

test("Android campaign clicks redirect to Google Play with an install referrer", async () => {
  const { response, location } = await campaignRedirect(
    "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 YouTube/19.20.34",
  );

  assert.equal(location.origin, "https://play.google.com");
  assert.equal(location.searchParams.get("id"), "com.healthmd.android");
  assert.equal(response.headers.get("x-healthmd-attribution-warning"), null);

  const referrer = new URLSearchParams(location.searchParams.get("referrer"));
  assert.equal(referrer.get("utm_source"), "yt");
  assert.equal(referrer.get("utm_medium"), "campaign_shortlink");
  assert.equal(referrer.get("utm_campaign"), "yt_csv_001");
  assert.equal(referrer.get("utm_content"), "csv");
});

test("iOS campaign clicks redirect to the App Store with Apple attribution", async () => {
  const { location } = await campaignRedirect(
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 YouTube/19.20",
  );

  assert.equal(location.origin, "https://apps.apple.com");
  assert.equal(location.searchParams.get("pt"), "123456");
  assert.equal(location.searchParams.get("ct"), "yt_csv_001");
  assert.equal(location.searchParams.get("mt"), "8");
  assert.equal(location.searchParams.get("ppid"), "csv-product-page");
});

test("macOS campaign clicks redirect to the App Store", async () => {
  const { location } = await campaignRedirect(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15",
  );

  assert.equal(location.origin, "https://apps.apple.com");
});

test("desktop campaign clicks redirect to the download page with campaign parameters", async () => {
  const { response, location } = await campaignRedirect(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0",
  );

  assert.equal(location.origin, "https://healthmd.app");
  assert.equal(location.pathname, "/");
  assert.equal(location.searchParams.get("utm_source"), "yt");
  assert.equal(location.searchParams.get("utm_medium"), "campaign_shortlink");
  assert.equal(location.searchParams.get("utm_campaign"), "yt_csv_001");
  assert.equal(location.searchParams.get("utm_content"), "csv");
  assert.equal(response.headers.get("x-healthmd-attribution-warning"), null);
});

test("client platform hints can identify Android when the user agent cannot", async () => {
  const { location } = await campaignRedirect("Mozilla/5.0", {
    "sec-ch-ua-platform": '"Android"',
  });

  assert.equal(location.origin, "https://play.google.com");
});
