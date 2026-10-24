import assert from "node:assert/strict";
import test from "node:test";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

test("campaign SQL joins late attribution, excludes restores/failures and counts buyers once", () => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const output = execFileSync("python3", ["-c", `
import sqlite3,json,pathlib
p=pathlib.Path(${JSON.stringify(root)})
db=sqlite3.connect(':memory:')
db.row_factory=sqlite3.Row
db.executescript((p/'migrations/0001_pricing_events.sql').read_text())
db.executescript((p/'migrations/0002_add_onboarding_step.sql').read_text())
def event(id,install,name,outcome=None,props=None):
 db.execute('INSERT INTO pricing_events(id,install_id,event_name,platform,purchase_outcome,payload_json) VALUES(?,?,?,?,?,?)',(id,install,name,'ios',outcome,json.dumps({'properties':props or {}})))
for install in ['a','b','c']:
 event('start'+install,install,'pricing_apple_ads_attribution_started')
 db.execute("UPDATE pricing_events SET received_at='2026-01-01T00:00:00Z' WHERE id=?",('start'+install,))
event('old','b','pricing_purchase_finished','succeeded')
db.execute("UPDATE pricing_events SET received_at='2025-01-01T00:00:00Z' WHERE id='old'")
# Purchase arrives before attribution; repeated successful events are one buyer.
event('p1','a','pricing_purchase_finished','succeeded')
event('p2','a','pricing_purchase_finished','succeeded')
for install,claim in [('a','Click'),('b','Click'),('c','Impression')]:
 event('attr'+install,install,'pricing_apple_ads_attribution_resolved',props={'appleAdsStatus':'matched','appleAdsCampaignId':42,'appleAdsClaimType':claim,'appleAdsConversionType':'Download'})
event('p3','b','pricing_purchase_finished','failed')
event('p4','c','pricing_restore_finished','succeeded')
event('p5','unknown','pricing_purchase_finished','succeeded')
print(json.dumps([dict(r) for r in db.execute((p/'queries/apple-ads-conversion.sql').read_text())]))
`], {encoding:"utf8"});
  const rows = JSON.parse(output);
  const click = rows.find(r => r.claim_type === "Click");
  assert.equal(click.resolved_installs, 2);
  assert.equal(click.purchasing_installs, 1);
  assert.equal(click.purchase_conversion_percent, 50);
  assert.equal(rows.find(r => r.claim_type === "Impression").purchasing_installs, 0);
  assert.equal(rows.length, 2);
});
