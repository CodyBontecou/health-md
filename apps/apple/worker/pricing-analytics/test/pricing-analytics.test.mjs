import assert from "node:assert/strict";
import test from "node:test";

import worker, { deleteExpiredEvents } from "../src/index.ts";

const installId = "00000000-0000-4000-8000-000000000001";

class FakeD1Database {
  preparedSql = "";
  statements = [];
  runSql = [];

  prepare(sql) {
    this.preparedSql = sql;
    return {
      bind: (...values) => ({ values }),
      run: async () => {
        this.runSql.push(sql);
        return { success: true };
      },
    };
  }

  async batch(statements) {
    this.statements = statements;
    return statements.map(() => ({ success: true }));
  }
}

async function postEvents(body) {
  const db = new FakeD1Database();
  const request = new Request("https://health-md-pricing-analytics.example/v1/events", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

  const response = await worker.fetch(request, { DB: db });
  const json = await response.json();
  return { db, response, json };
}

function baseProperties(extra = {}) {
  return {
    experimentId: "pricing_subscription_transition",
    variantId: "baseline_lifetime_only",
    platform: "ios",
    ...extra,
  };
}

test("accepts the currently released Apple v3.0.3 identifiers and envelope", async () => {
  const events = ["baseline_lifetime_only", "lifetime_offer_mix"].map((variantId, index) => ({
    eventId: `00000000-0000-4000-8000-00000000009${index}`,
    eventName: "pricing_onboarding_started",
    properties: {
      experimentId: "pricing_lifetime_offers",
      variantId,
      appVersion: "3.0.3",
      buildNumber: "303",
      platform: "ios",
      onboardingStep: "welcome",
      freeExportsUsed: 0,
      freeExportsRemaining: 10,
    },
  }));

  const { db, response, json } = await postEvents({ installId, events });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: events.length });
  assert.equal(db.statements.length, events.length);
  assert.equal(db.statements[0].values[3], "pricing_lifetime_offers");
  assert.equal(db.statements[0].values[4], "baseline_lifetime_only");
  assert.equal(db.statements[1].values[4], "lifetime_offer_mix");
});

test("accepts new onboarding events and stores onboardingStep in payload_json", async () => {
  const events = [
    ["00000000-0000-4000-8000-000000000101", "pricing_onboarding_started", "welcome"],
    ["00000000-0000-4000-8000-000000000102", "pricing_onboarding_step_viewed", "health_access"],
    ["00000000-0000-4000-8000-000000000103", "pricing_onboarding_step_viewed", "sample_export"],
    ["00000000-0000-4000-8000-000000000104", "pricing_onboarding_step_viewed", "obsidian_plugin"],
    ["00000000-0000-4000-8000-000000000105", "pricing_onboarding_health_skipped", "health_access"],
    ["00000000-0000-4000-8000-000000000106", "pricing_onboarding_folder_selected", "folder_setup"],
    ["00000000-0000-4000-8000-000000000107", "pricing_onboarding_folder_skipped", "folder_setup"],
    ["00000000-0000-4000-8000-000000000108", "pricing_onboarding_continue_free_tapped", "unlock"],
    ["00000000-0000-4000-8000-000000000109", "pricing_onboarding_purchase_tapped", "unlock"],
  ].map(([eventId, eventName, onboardingStep]) => ({
    eventId,
    eventName,
    properties: baseProperties({
      onboardingStep,
      paywallContext: onboardingStep === "unlock" ? "onboarding" : undefined,
    }),
  }));

  const { db, response, json } = await postEvents({ installId, events });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: events.length });
  assert.match(db.preparedSql, /onboarding_step/);
  assert.equal(db.statements.length, events.length);

  const payloadJson = db.statements[3].values.at(-1);
  assert.equal(JSON.parse(payloadJson).properties.onboardingStep, "obsidian_plugin");
  assert.equal(
    JSON.parse(db.statements[4].values.at(-1)).eventName,
    "pricing_onboarding_health_skipped",
  );
  assert.equal(
    JSON.parse(db.statements[6].values.at(-1)).eventName,
    "pricing_onboarding_folder_skipped",
  );
});

test("rejects unknown envelope, event, and property fields", async () => {
  const cases = [
    {
      body: {
        installId,
        events: [],
        healthValue: 72,
      },
      error: "unknown_envelope_field:healthValue",
    },
    {
      body: {
        installId,
        events: [{
          eventId: "00000000-0000-4000-8000-000000000210",
          eventName: "pricing_onboarding_started",
          properties: baseProperties(),
          filePath: "/Users/example/Health/2026-08-02.json",
        }],
      },
      error: "unknown_event_field:filePath",
    },
    {
      body: {
        installId,
        eventId: "00000000-0000-4000-8000-000000000211",
        eventName: "pricing_onboarding_started",
        properties: baseProperties({ metricName: "step_count" }),
      },
      error: "unknown_property:metricName",
    },
  ];

  for (const testCase of cases) {
    const { response, json } = await postEvents(testCase.body);
    assert.equal(response.status, 400);
    assert.equal(json.error, testCase.error);
  }
});

test("rejects non-object properties instead of silently discarding them", async () => {
  const { response, json } = await postEvents({
    installId,
    eventId: "00000000-0000-4000-8000-000000000212",
    eventName: "pricing_onboarding_started",
    properties: "exported health content",
  });

  assert.equal(response.status, 400);
  assert.equal(json.error, "properties_must_be_object");
});

test("normalized storage payload excludes identifiers and prohibited content", async () => {
  const { db, response } = await postEvents({
    installId,
    eventId: "00000000-0000-4000-8000-000000000213",
    eventName: "pricing_onboarding_started",
    properties: baseProperties({
      onboardingStep: "welcome",
      freeExportsUsed: 0,
      freeExportsRemaining: 10,
    }),
  });

  assert.equal(response.status, 200);
  const payload = JSON.parse(db.statements[0].values.at(-1));
  assert.deepEqual(Object.keys(payload).sort(), ["eventName", "properties"]);
  assert.equal(JSON.stringify(payload).includes(installId), false);
  for (const prohibited of ["healthValue", "metricName", "healthDate", "filePath", "peerName", "credential"]) {
    assert.equal(Object.hasOwn(payload.properties, prohibited), false);
  }
});

test("deletes pricing analytics rows older than thirteen months", async () => {
  const db = new FakeD1Database();
  await deleteExpiredEvents({ DB: db });

  assert.equal(db.runSql.length, 1);
  assert.match(db.runSql[0], /DELETE FROM pricing_events/);
  assert.match(db.runSql[0], /received_at < strftime/);
  assert.match(db.runSql[0], /'-13 months'/);
});

test("rejects onboardingStep values outside the coarse allowlist", async () => {
  const { response, json } = await postEvents({
    installId,
    eventId: "00000000-0000-4000-8000-000000000201",
    eventName: "pricing_onboarding_step_viewed",
    properties: baseProperties({ onboardingStep: "folder:/Users/cody/Documents" }),
  });

  assert.equal(response.status, 400);
  assert.equal(json.error, "unknown_property_value:onboardingStep");
});

test("dedupes health authorization completion by install and status", async () => {
  const events = [
    {
      eventId: "00000000-0000-4000-8000-000000000401",
      eventName: "pricing_health_authorization_completed",
      properties: baseProperties({ authorizationStatus: "authorized" }),
    },
    {
      eventId: "00000000-0000-4000-8000-000000000402",
      eventName: "pricing_health_authorization_completed",
      properties: baseProperties({ authorizationStatus: "authorized" }),
    },
    {
      eventId: "00000000-0000-4000-8000-000000000403",
      eventName: "pricing_health_authorization_completed",
      properties: baseProperties({ authorizationStatus: "unknown" }),
    },
  ];

  const { db, response, json } = await postEvents({ installId, events });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: events.length });
  assert.equal(
    db.statements[0].values[0],
    `dedupe:pricing_health_authorization_completed:${installId}:authorized`,
  );
  assert.equal(
    db.statements[1].values[0],
    `dedupe:pricing_health_authorization_completed:${installId}:authorized`,
  );
  assert.equal(
    db.statements[2].values[0],
    `dedupe:pricing_health_authorization_completed:${installId}:unknown`,
  );
});

test("accepts source paywall context on purchase events", async () => {
  const { db, response, json } = await postEvents({
    installId,
    eventId: "00000000-0000-4000-8000-000000000301",
    eventName: "pricing_purchase_finished",
    properties: baseProperties({
      paywallContext: "onboarding",
      onboardingStep: "unlock",
      productId: "com.codybontecou.obsidianhealth.unlock.family",
      purchaseOutcome: "succeeded",
      freeExportsUsed: 0,
      freeExportsRemaining: 10,
    }),
  });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: 1 });

  const payload = JSON.parse(db.statements[0].values.at(-1));
  assert.equal(payload.eventName, "pricing_purchase_finished");
  assert.equal(payload.properties.paywallContext, "onboarding");
  assert.equal(payload.properties.onboardingStep, "unlock");
  assert.equal(payload.properties.productId, "com.codybontecou.obsidianhealth.unlock.family");
});

test("accepts privacy-safe Android onboarding events", async () => {
  const events = [
    {
      eventId: "00000000-0000-4000-8000-000000000305",
      eventName: "pricing_onboarding_step_viewed",
      properties: {
        appVersion: "1.5.4",
        buildNumber: "25",
        platform: "android",
        onboardingStep: "health_access",
        paywallContext: "onboarding",
        freeExportsUsed: 2,
        freeExportsRemaining: 8,
      },
    },
    {
      eventId: "00000000-0000-4000-8000-000000000306",
      eventName: "pricing_onboarding_purchase_tapped",
      properties: {
        appVersion: "1.5.4",
        buildNumber: "25",
        platform: "android",
        onboardingStep: "unlock",
        paywallContext: "onboarding",
        freeExportsUsed: 2,
        freeExportsRemaining: 8,
        productId: "health_md_premium_lifetime",
      },
    },
  ];

  const { db, response, json } = await postEvents({ installId, events });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: events.length });
  const stepPayload = JSON.parse(db.statements[0].values.at(-1));
  const purchasePayload = JSON.parse(db.statements[1].values.at(-1));
  assert.equal(stepPayload.properties.platform, "android");
  assert.equal(stepPayload.properties.onboardingStep, "health_access");
  assert.equal(purchasePayload.properties.productId, "health_md_premium_lifetime");
});

test("accepts coarse macOS onboarding steps", async () => {
  const steps = ["mac_how_it_works", "mac_iphone_app", "mac_connect"];
  const events = steps.map((onboardingStep, index) => ({
    eventId: `00000000-0000-4000-8000-00000000031${index}`,
    eventName: "pricing_onboarding_step_viewed",
    properties: {
      appVersion: "3.0.0",
      buildNumber: "300",
      platform: "macos",
      onboardingStep,
    },
  }));

  const { db, response, json } = await postEvents({ installId, events });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: events.length });
  assert.deepEqual(
    db.statements.map((statement) => JSON.parse(statement.values.at(-1)).properties.onboardingStep),
    steps,
  );
});

test("accepts API endpoint export targets", async () => {
  const { db, response, json } = await postEvents({
    installId,
    eventId: "00000000-0000-4000-8000-000000000304",
    eventName: "pricing_export_succeeded",
    properties: baseProperties({
      exportTargetType: "api_endpoint",
      formatCount: 1,
      metricCountBucket: "1_5",
      dateRangePreset: "today",
      dateSpanBucket: "same_day",
    }),
  });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: 1 });
  const payload = JSON.parse(db.statements[0].values.at(-1));
  assert.equal(payload.properties.exportTargetType, "api_endpoint");
});

test("accepts subscription product purchase events", async () => {
  const { db, response, json } = await postEvents({
    installId,
    eventId: "00000000-0000-4000-8000-000000000303",
    eventName: "pricing_purchase_finished",
    properties: baseProperties({
      paywallContext: "export_quota",
      productId: "com.codybontecou.obsidianhealth.pro.family.monthly",
      purchaseOutcome: "succeeded",
      freeExportsUsed: 10,
      freeExportsRemaining: 0,
    }),
  });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: 1 });

  const payload = JSON.parse(db.statements[0].values.at(-1));
  assert.equal(payload.eventName, "pricing_purchase_finished");
  assert.equal(payload.properties.productId, "com.codybontecou.obsidianhealth.pro.family.monthly");
});

test("accepts family upgrade product purchase events", async () => {
  const { db, response, json } = await postEvents({
    installId,
    eventId: "00000000-0000-4000-8000-000000000302",
    eventName: "pricing_purchase_finished",
    properties: baseProperties({
      paywallContext: "settings",
      productId: "com.codybontecou.obsidianhealth.unlock.family.upgrade",
      purchaseOutcome: "succeeded",
      freeExportsUsed: 0,
      freeExportsRemaining: 10,
    }),
  });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: 1 });

  const payload = JSON.parse(db.statements[0].values.at(-1));
  assert.equal(payload.eventName, "pricing_purchase_finished");
  assert.equal(payload.properties.productId, "com.codybontecou.obsidianhealth.unlock.family.upgrade");
});
