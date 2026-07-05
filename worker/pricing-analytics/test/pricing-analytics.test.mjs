import assert from "node:assert/strict";
import test from "node:test";

import worker from "../src/index.ts";

const installId = "00000000-0000-4000-8000-000000000001";

class FakeD1Database {
  preparedSql = "";
  statements = [];

  prepare(sql) {
    this.preparedSql = sql;
    return {
      bind: (...values) => ({ values }),
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

test("accepts new onboarding events and stores onboardingStep in payload_json", async () => {
  const events = [
    ["00000000-0000-4000-8000-000000000101", "pricing_onboarding_started", "welcome"],
    ["00000000-0000-4000-8000-000000000102", "pricing_onboarding_step_viewed", "health_access"],
    ["00000000-0000-4000-8000-000000000103", "pricing_onboarding_step_viewed", "sample_export"],
    ["00000000-0000-4000-8000-000000000104", "pricing_onboarding_step_viewed", "obsidian_plugin"],
    ["00000000-0000-4000-8000-000000000105", "pricing_onboarding_folder_selected", "folder_setup"],
    ["00000000-0000-4000-8000-000000000106", "pricing_onboarding_continue_free_tapped", "unlock"],
    ["00000000-0000-4000-8000-000000000107", "pricing_onboarding_purchase_tapped", "unlock"],
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
      productId: "com.codybontecou.obsidianhealth.unlock.family",
      purchaseOutcome: "succeeded",
      freeExportsUsed: 0,
      freeExportsRemaining: 3,
    }),
  });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: 1 });

  const payload = JSON.parse(db.statements[0].values.at(-1));
  assert.equal(payload.eventName, "pricing_purchase_finished");
  assert.equal(payload.properties.paywallContext, "onboarding");
  assert.equal(payload.properties.productId, "com.codybontecou.obsidianhealth.unlock.family");
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
      freeExportsUsed: 3,
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
      freeExportsRemaining: 3,
    }),
  });

  assert.equal(response.status, 200);
  assert.deepEqual(json, { ok: true, accepted: 1 });

  const payload = JSON.parse(db.statements[0].values.at(-1));
  assert.equal(payload.eventName, "pricing_purchase_finished");
  assert.equal(payload.properties.productId, "com.codybontecou.obsidianhealth.unlock.family.upgrade");
});
