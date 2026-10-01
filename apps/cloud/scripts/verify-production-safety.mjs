import { existsSync, readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const cloud = resolve(import.meta.dirname, "..");
const repository = resolve(cloud, "../..");
const failures = [];
const checked = [];

function read(relative, base = cloud) {
  const path = resolve(base, relative);
  if (!existsSync(path)) { failures.push(`missing ${path}`); return ""; }
  checked.push(path.replace(`${repository}/`, ""));
  return readFileSync(path, "utf8");
}
function requireText(text, fragment, label) {
  if (!text.includes(fragment)) failures.push(`${label}: missing ${JSON.stringify(fragment)}`);
}
function forbid(text, pattern, label) {
  if (pattern.test(text)) failures.push(`${label}: forbidden ${pattern}`);
}

const profiles = [
  ["wrangler.ingest.toml", "ingest", "src/ingest-worker.ts"],
  ["wrangler.account.toml", "account", "src/account-worker.ts"],
  ["wrangler.maintenance.toml", "maintenance", "src/maintenance-worker.ts"],
];
for (const [file, profile, entry] of profiles) {
  const text = read(file);
  requireText(text, `main = "${entry}"`, file);
  requireText(text, `SERVICE_PROFILE = "${profile}"`, file);
  requireText(text, "DEPLOYMENT_REVISION = \"REPLACE_WITH_FULL_GIT_COMMIT_SHA\"", file);
  requireText(text, "AUTH_SIGNUP_MODE = \"closed\"", file);
  requireText(text, "workers_dev = false", file);
  requireText(text, "preview_urls = false", file);
  requireText(text, "00000000-0000-0000-0000-000000000000", file);
  requireText(text, "placeholder", file);
  requireText(text, "HEALTH_FREE_METRICS_REQUIRED = \"1\"", file);
  requireText(text, 'ACCOUNT_KEY_MODE = "per_account"', file);
  requireText(text, 'CURRENT_ACCOUNT_WRAPPING_KEY_ID = "kek-v1"', file);
  forbid(text, /^routes?\s*=/mu, file);
  forbid(text, /^(?:IDENTITY_KEY_B64|EXPORT_ENCRYPTION_KEYS_JSON|ACCOUNT_KEY_WRAPPING_KEYS_JSON|RESEND_API_KEY|PASSWORD_PEPPER_B64|AUTH_INVITE_EMAILS|CLOUD_RUNTIME_APPROVED|CLOUD_REPAIR_DEVICE_ENROLLMENT_ENABLED|CLOUD_REPAIR_DISPATCH_ENABLED)\s*=/mu, file);
  if (profile === "ingest") {
    requireText(text, 'INGEST_TOKEN_HOURLY_LIMIT = "120"', file);
    requireText(text, 'INGEST_ACCOUNT_HOURLY_LIMIT = "240"', file);
    forbid(text, /^\[assets\]$/mu, file);
    forbid(text, /^\[\[queues\./mu, file);
    forbid(text, /^binding\s*=\s*"LIFECYCLE_QUEUE"$/mu, file);
  } else if (profile === "account") {
    requireText(text, "[assets]", file);
    requireText(text, 'binding = "ASSETS"', file);
    requireText(text, "[[queues.producers]]", file);
    requireText(text, 'binding = "LIFECYCLE_QUEUE"', file);
    requireText(text, 'EXPORT_ENDPOINT_ORIGIN = "https://api.healthmd.app"', file);
    requireText(text, 'EMAIL_SEND_HOURLY_LIMIT = "100"', file);
    requireText(text, 'DELETION_STATUS_TTL_DAYS = "30"', file);
    forbid(text, /^\[\[queues\.consumers\]\]$/mu, file);
  } else {
    requireText(text, "[triggers]", file);
    requireText(text, 'crons = ["*/5 * * * *"]', file);
    requireText(text, "[[queues.producers]]", file);
    requireText(text, "[[queues.consumers]]", file);
    requireText(text, 'dead_letter_queue = "healthmd-cloud-lifecycle-dead-letter-placeholder-not-for-deployment"', file);
    requireText(text, 'REVISION_RETENTION_DAYS = "30"', file);
    requireText(text, 'DELETION_STATUS_TTL_DAYS = "30"', file);
    forbid(text, /^\[assets\]$/mu, file);
  }
}
const combined = read("wrangler.toml");
requireText(combined, "00000000-0000-0000-0000-000000000000", "wrangler.toml");
requireText(combined, "AUTH_SIGNUP_MODE = \"closed\"", "wrangler.toml");
requireText(combined, "intentionally non-deployable", "wrangler.toml");

const adr = read("docs/architecture/adr-0008-multi-user-healthmd-cloud-production.md", repository);
requireText(adr, "Status: **Proposed — blocked", "ADR-0008");
const unassignedOwners = adr.match(/\| unassigned \| blocked \|/gu)?.length ?? 0;
if (unassignedOwners !== 5) failures.push(`ADR-0008: expected 5 unassigned blocked owners, found ${unassignedOwners}`);
const plan = read("docs/multi-user-production-rollout-plan.md");
const unchecked = plan.match(/^- \[ \] /gmu)?.length ?? 0;
if (unchecked < 13) failures.push(`rollout plan: expected at least 13 unchecked acceptance gates, found ${unchecked}`);
if (/^- \[[xX]\] /mu.test(plan)) failures.push("rollout plan: a gate was marked complete without replacing this blocked-state verifier");

const requiredEvidence = [
  "docs/production-authorization-matrix.md",
  "docs/production-data-flow-threat-model.md",
  "docs/production-observability-and-slo.md",
  "docs/production-load-qualification.md",
  "docs/production-readiness-audit.md",
  "docs/production-recovery-runbook.md",
  "docs/account-key-rotation-runbook.md",
  "src/ingest-worker.ts", "src/account-worker.ts", "src/maintenance-worker.ts",
  "src/upload-intents.ts", "src/account-export-keys.ts", "src/telemetry.ts",
];
for (const path of requiredEvidence) read(path);
const loadHarness = read("scripts/staging-load-lib.mjs");
requireText(loadHarness, '"api.healthmd.app"', "staging load harness");
requireText(loadHarness, "Refusing a live or non-staging hostname", "staging load harness");
requireText(loadHarness, "Expected full deployment revision is required", "staging load harness");
requireText(loadHarness, "Synthetic token file must be a regular owner-only file", "staging load harness");
requireText(loadHarness, "HEALTHMD_LOAD_DISTINCT_ACCOUNTS", "staging load harness");
const loadRunner = read("scripts/qualify-staging-load.mjs");
requireText(loadRunner, 'syntheticOnly: true', "staging load runner");
forbid(loadRunner, /console\.(?:log|error)\([^\n]*(?:token|endpoint|body)/u, "staging load runner output");
const migrations = readdirSync(resolve(cloud, "migrations"))
  .filter((name) => /^\d{4}_.+\.sql$/u.test(name)).sort();
if (migrations.length !== 17 || migrations[0]?.slice(0, 4) !== "0001" ||
    migrations.at(-1)?.slice(0, 4) !== "0017") {
  failures.push(`migrations: expected contiguous source set 0001-0017, found ${migrations.join(",")}`);
}

const workflow = read(".github/workflows/cloud-ci.yml", repository);
for (const line of workflow.split("\n")) {
  if (line.includes("wrangler deploy") && !line.includes("--dry-run")) {
    failures.push("Cloud CI contains a non-dry-run wrangler deployment command");
  }
}
requireText(workflow, "permissions:\n  contents: read", "Cloud CI");

if (failures.length) {
  console.error(JSON.stringify({ safe: false, failures }, null, 2));
  process.exit(1);
}
console.log(JSON.stringify({
  safe: true,
  meaning: "Production remains deliberately blocked; this is not launch readiness.",
  profiles: profiles.map(([, profile]) => profile),
  uncheckedAcceptanceGates: unchecked,
  unassignedOwners,
  migrations: `${migrations[0]}..${migrations.at(-1)}`,
  checkedFiles: checked.length,
}, null, 2));
