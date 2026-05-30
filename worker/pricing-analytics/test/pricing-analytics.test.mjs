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
    experimentId: "pricing_lifetime_unlock",
    variantId: "baseline_lifetime_current",
    platform: "ios",
    ...extra,
  };
}

test("accepts new onboarding events and stores onboardingStep in payload_json", async () => {
  const events = [
    ["00000000-0000-4000-8000-000000000101", "pricing_onboarding_started", "welcome"],
    ["00000000-0000-4000-8000-000000000102", "pricing_onboarding_step_viewed", "health_access"],
    ["00000000-0000-4000-8000-000000000103", "pricing_onboarding_folder_selected", "folder_setup"],
    ["00000000-0000-4000-8000-000000000104", "pricing_onboarding_continue_free_tapped", "unlock"],
    ["00000000-0000-4000-8000-000000000105", "pricing_onboarding_purchase_tapped", "unlock"],
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

  const payloadJson = db.statements[2].values.at(-1);
  assert.equal(JSON.parse(payloadJson).properties.onboardingStep, "folder_setup");
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

test("accepts source paywall context on purchase events", async () => {
  const { db, response, json } = await postEvents({
    installId,
    eventId: "00000000-0000-4000-8000-000000000301",
    eventName: "pricing_purchase_finished",
    properties: baseProperties({
      paywallContext: "onboarding",
      productId: "com.codybontecou.obsidianhealth.unlock",
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
});
