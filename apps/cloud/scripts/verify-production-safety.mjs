import { existsSync, readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const cloud = resolve(import.meta.dirname, "..");
const repository = resolve(cloud, "../..");
const failures = [];
const checked = new Set();

function read(relative, base = cloud) {
  const path = resolve(base, relative);
  if (!existsSync(path)) { failures.push(`missing ${path}`); return ""; }
  checked.add(path.replace(`${repository}/`, ""));
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
  const entrySource = read(entry);
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
  if (profile !== "maintenance") forbid(text, /^AUDIT_RETENTION_DAYS\s*=/mu, file);
  forbid(text, /^(?:IDENTITY_KEY_B64|EXPORT_ENCRYPTION_KEYS_JSON|ACCOUNT_KEY_WRAPPING_KEYS_JSON|RESEND_API_KEY|PASSWORD_PEPPER_B64|AUTH_INVITE_EMAILS|CLOUD_RUNTIME_APPROVED|CLOUD_REPAIR_DEVICE_ENROLLMENT_ENABLED|CLOUD_REPAIR_DISPATCH_ENABLED)\s*=/mu, file);
  requireText(entrySource, `env.SERVICE_PROFILE !== "${profile}"`, entry);
  if (profile === "ingest") {
    requireText(text, 'MAX_EXPORT_BYTES = "26214400"', file);
    requireText(text, 'INGEST_TOKEN_HOURLY_LIMIT = "120"', file);
    requireText(text, 'INGEST_ACCOUNT_HOURLY_LIMIT = "240"', file);
    forbid(text, /^(?:AUTH_EMAIL_FROM|EXPORT_ENDPOINT_ORIGIN|SESSION_TTL_DAYS|MAGIC_LINK_TTL_MINUTES|EMAIL_SEND_HOURLY_LIMIT|DELETION_STATUS_TTL_DAYS|REVISION_RETENTION_DAYS)\s*=/mu, file);
    requireText(text, "Ingest must not receive legacy EXPORT_ENCRYPTION_KEYS_JSON/CURRENT_EXPORT_KEY_ID authority", file);
    forbid(text, /^CURRENT_EXPORT_KEY_ID\s*=/mu, file);
    forbid(text, /^\[assets\]$/mu, file);
    forbid(text, /^\[\[queues\./mu, file);
    forbid(text, /^binding\s*=\s*"LIFECYCLE_QUEUE"$/mu, file);
    requireText(entrySource, 'request.method === "POST" && path === "/api/v1/exports"', entry);
    requireText(entrySource, 'headers.delete("Cookie")', entry);
    requireText(entrySource, 'responseHeaders.delete("Set-Cookie")', entry);
  } else if (profile === "account") {
    requireText(text, "[assets]", file);
    requireText(text, 'binding = "ASSETS"', file);
    requireText(text, "[[queues.producers]]", file);
    requireText(text, 'binding = "LIFECYCLE_QUEUE"', file);
    requireText(text, 'EXPORT_ENDPOINT_ORIGIN = "https://api.healthmd.app"', file);
    requireText(text, 'EMAIL_SEND_HOURLY_LIMIT = "100"', file);
    requireText(text, 'DELETION_STATUS_TTL_DAYS = "30"', file);
    requireText(text, 'CURRENT_EXPORT_KEY_ID = "v1"', file);
    requireText(text, "EXPORT_ENCRYPTION_KEYS_JSON (legacy-read compatibility during migration)", file);
    requireText(text, "Split production rejects raw AUTH_INVITE_EMAILS configuration", file);
    forbid(text, /^AUTH_INVITE_EMAILS\s*=/mu, file);
    forbid(text, /^(?:INGEST_TOKEN_HOURLY_LIMIT|INGEST_ACCOUNT_HOURLY_LIMIT|REVISION_RETENTION_DAYS)\s*=/mu, file);
    forbid(text, /^\[\[queues\.consumers\]\]$/mu, file);
    forbid(entrySource, /["']\/api\/v1\/exports["']/u, entry);
  } else {
    requireText(text, "[triggers]", file);
    requireText(text, 'crons = ["*/5 * * * *"]', file);
    requireText(text, "[[queues.producers]]", file);
    requireText(text, "[[queues.consumers]]", file);
    requireText(text, 'dead_letter_queue = "healthmd-cloud-lifecycle-dead-letter-placeholder-not-for-deployment"', file);
    requireText(text, 'REVISION_RETENTION_DAYS = "30"', file);
    requireText(text, 'AUDIT_RETENTION_DAYS = "365"', file);
    requireText(text, "privacy/legal/operations must approve", file);
    requireText(text, 'DELETION_STATUS_TTL_DAYS = "30"', file);
    requireText(text, "Maintenance must not receive legacy EXPORT_ENCRYPTION_KEYS_JSON/CURRENT_EXPORT_KEY_ID authority", file);
    forbid(text, /^(?:AUTH_EMAIL_FROM|EXPORT_ENDPOINT_ORIGIN|MAX_EXPORT_BYTES|SESSION_TTL_DAYS|MAGIC_LINK_TTL_MINUTES|EMAIL_SEND_HOURLY_LIMIT|INGEST_TOKEN_HOURLY_LIMIT|INGEST_ACCOUNT_HOURLY_LIMIT)\s*=/mu, file);
    forbid(text, /^CURRENT_EXPORT_KEY_ID\s*=/mu, file);
    forbid(text, /^\[assets\]$/mu, file);
    requireText(entrySource, "validateConfiguration(env)", entry);
    requireText(entrySource, "message.retry()", entry);
    requireText(entrySource, "Endpoint not found.", entry);
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
  "docs/account-key-rotation-runbook.md", "docs/account-invite-runbook.md",
  "src/ingest-worker.ts", "src/account-worker.ts", "src/maintenance-worker.ts",
  "src/upload-intents.ts", "src/account-export-keys.ts", "src/telemetry.ts",
];
for (const path of requiredEvidence) read(path);
for (const path of ["src/ingest-worker.ts", "src/account-worker.ts", "src/maintenance-worker.ts"]) {
  const source = read(path);
  const validation = source.indexOf("validateConfiguration(env);");
  const routeDecision = source.indexOf("env.SERVICE_PROFILE !==");
  if (validation < 0 || routeDecision < 0 || validation > routeDecision) {
    failures.push(`${path}: full configuration validation must precede every HTTP route decision`);
  }
}
const splitAccountSource = read("src/account-worker.ts");
for (const route of [/\/api\/auth\/password-login/u, /\/api\/agent-tokens/u,
  /\/api\/repair\/device/u, /\/api\/repair\/devices/u, /\/api\/repair\/dispatch/u]) {
  forbid(splitAccountSource, route, "split account pilot-only routes");
}
const uploadIntentSource = read("src/upload-intents.ts");
for (const fragment of [
  "INSERT INTO upload_admissions", "FROM upload_admissions WHERE id = ? LIMIT 1",
  '"admission_verification_pending"', "releaseUploadAdmission", "renewUploadAdmission",
  '"admission_renewal_pending"', "AND expires_at = ? AND expires_at > ?",
  "WHERE id = ? AND expires_at = ? AND expires_at <= ?", "durable.expiresAt !== row.expiresAt",
  "ORDER BY expires_at, id LIMIT ?", "Upload admission cleanup verification is unavailable",
]) requireText(uploadIntentSource, fragment, "durable pre-body upload admission");
for (const fragment of [
  "SET state = 'aborting'", "Upload-intent cleanup claim verification is unavailable",
  "DELETE FROM upload_intents WHERE id = ? AND state = 'aborting'",
  "Upload-intent cleanup verification is unavailable",
  "Completed upload-intent cleanup verification is unavailable",
  "FROM upload_intents WHERE id = ? LIMIT 1", "durable.userId === intent.userId",
  "durable.objectKey === intent.objectKey", "durable.digest === intent.digest",
  'durable.state === "reserved"', "durable.createdAt === intent.createdAt",
  "durable.expiresAt === intent.expiresAt", '"reservation_verification_pending"',
]) requireText(uploadIntentSource, fragment, "durable upload reservation creation");
forbid(uploadIntentSource, /meta\.changes/u, "upload-intent correctness");
const reservationRead = uploadIntentSource.indexOf("FROM upload_intents WHERE id = ? LIMIT 1");
const reservationReturn = uploadIntentSource.indexOf("return intent;");
if (reservationRead < 0 || reservationReturn < reservationRead) {
  failures.push("upload-intents.ts: candidate reservation returned before durable exact read-back");
}
const httpSource = read("src/http.ts");
for (const fragment of [
  "const initialCapacity = declared === null ? Math.min(maximumBytes, 16 * 1024) : Number(declared)",
  "Math.min(maximumBytes,", "grown.set(buffer.subarray(0, total))",
  "return buffer.subarray(0, total)", "Preserve the stable bounded-body error",
  "deadlineEpochMs - Date.now()", 'new HttpError(408, "request_timeout"',
  "Preserve the stable lease-timeout error",
]) requireText(httpSource, fragment, "bounded contiguous request body");
forbid(httpSource, /chunks:\s*Uint8Array\[\]/u, "unbounded fragmented request body");
const exportsSource = read("src/exports.ts");
const authenticateIngest = exportsSource.indexOf("requireIngestToken(request, env)");
const budgetIngest = exportsSource.indexOf("limitIngest(env, principal.tokenId, principal.userId)");
const acquireAdmission = exportsSource.indexOf("acquireUploadAdmission(env, principal)");
const materializeBody = exportsSource.indexOf("readBoundedBody(request, maximumBytes,");
const renewAdmission = exportsSource.indexOf("renewUploadAdmission(env, admission)");
const parseEnvelope = exportsSource.indexOf("parseAndValidateEnvelope(body)");
if (authenticateIngest < 0 || budgetIngest < authenticateIngest || acquireAdmission < budgetIngest ||
    materializeBody < acquireAdmission || renewAdmission < materializeBody || parseEnvelope < renewAdmission) {
  failures.push("exports.ts: auth/budget/admission/body/deadline-renewal/parse ordering is not fail-closed");
}
requireText(exportsSource, "if (!admissionConsumed) await releaseUploadAdmission(env, admission)",
  "pre-intent admission release");
requireText(exportsSource, "AND EXISTS (SELECT 1 FROM upload_intents i", "active-intent export commit gate");
requireText(exportsSource, "i.state IN ('reserved', 'object_written')", "active-intent export commit gate");
const accountKeySource = read("src/account-export-keys.ts");
requireText(accountKeySource, 'if (env.ACCOUNT_KEY_MODE !== "per_account")', "per-account ingest key path");
requireText(accountKeySource, 'parseExportKeyring(env.EXPORT_ENCRYPTION_KEYS_JSON ?? "")',
  "legacy account-read key path");
for (const fragment of [
  "created_at AS createdAt", "winner.wrappedKey === wrapped.wrappedKey",
  "winner.wrapIv === wrapped.iv", "winner.createdAt === createdAt",
  "Account export key creation verification is unavailable",
]) requireText(accountKeySource, fragment, "durable account-key creation");
forbid(accountKeySource, /meta\.changes/u, "account-key creation/rewrap correctness");
const authSource = read("src/auth.ts");
for (const fragment of [
  'keyedLookup(email, env.IDENTITY_KEY_B64, "account-invite-v1")',
  "WHERE invite_lookup = ?", "invitesPerRun: 500", "magicLinksPerRun: 500",
  "sessionsPerRun: 500", "rateAttemptsPerRun: 50_000",
  "rateBucketsPerRun: 5_000", "ORDER BY expires_at, id LIMIT ?",
]) requireText(authSource, fragment, "bounded auth cleanup");
const lifecycleSource = read("src/lifecycle.ts");
for (const fragment of [
  "Invalid deletion-receipt cleanup limit", "ORDER BY status_expires_at, status_token_hash LIMIT ?",
  "ORDER BY completed_at, id LIMIT ?",
]) requireText(lifecycleSource, fragment, "bounded deletion-receipt cleanup");
requireText(lifecycleSource, "state IN ('reserved', 'object_written', 'aborting')",
  "account deletion includes claimed upload cleanup");
const indexSource = read("src/index.ts");
requireText(indexSource, '(profile === "ingest" || profile === "maintenance") &&',
  "legacy decrypt authority rejection");
requireText(indexSource, '!!env.EXPORT_ENCRYPTION_KEYS_JSON || !!env.CURRENT_EXPORT_KEY_ID',
  "legacy decrypt authority rejection");
requireText(indexSource, "invalidExcessSettings", "split profile runtime-setting isolation");
requireText(indexSource, "[env.EXPORT_ENDPOINT_ORIGIN, env.SESSION_TTL_DAYS", "ingest runtime-setting isolation");
requireText(indexSource, "[env.INGEST_TOKEN_HOURLY_LIMIT", "account runtime-setting isolation");
requireText(indexSource, "[env.EXPORT_ENDPOINT_ORIGIN, env.MAX_EXPORT_BYTES", "maintenance runtime-setting isolation");
requireText(indexSource, "phase(() => purgeExpiredAuthState(env))", "scheduled bounded auth cleanup");
requireText(indexSource, "phase(() => reconcileUploadAdmissions(env))", "scheduled bounded admission cleanup");
requireText(indexSource, "phase(() => reconcileUploadIntents(env))", "scheduled bounded intent cleanup");
requireText(indexSource, "phase(() => purgeExpiredDeletionReceipts(env))", "scheduled bounded receipt cleanup");
const repairDraftSource = read("src/repair-drafts.ts");
requireText(repairDraftSource, "ORDER BY expires_at, id LIMIT ?", "bounded repair-draft cleanup");
requireText(repairDraftSource, "Invalid repair-draft cleanup limit", "bounded repair-draft cleanup");
const repairDeviceSource = read("src/repair-devices.ts");
requireText(repairDeviceSource, "ORDER BY COALESCE(grant_expires_at, pairing_expires_at), id LIMIT ?",
  "bounded repair-device cleanup");
requireText(repairDeviceSource, "Invalid repair-device cleanup limit", "bounded repair-device cleanup");
requireText(indexSource, "phase(() => purgeExpiredRepairDrafts(env))", "scheduled bounded repair-draft cleanup");
requireText(indexSource, "phase(() => purgeExpiredRepairDevices(env))", "scheduled bounded repair-device cleanup");
const inviteTool = read("scripts/prepare-account-invites.mjs");
for (const fragment of [
  'privateRegularFile(emailFile, "Invite email input")', "must be a regular owner-only file",
  "Invite SQL output already exists",
  "account-invite-v1\\0", 'openSync(outputFile, "wx", 0o600)', "more than 90 days away",
]) requireText(inviteTool, fragment, "account invite provisioning");
forbid(inviteTool, /console\.(?:log|error)/u, "account invite provisioning output");
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
const expectedMigrationPrefixes = Array.from({ length: 18 }, (_, index) =>
  String(index + 1).padStart(4, "0"));
const migrationPrefixes = migrations.map((name) => name.slice(0, 4));
if (JSON.stringify(migrationPrefixes) !== JSON.stringify(expectedMigrationPrefixes)) {
  failures.push(`migrations: expected exactly one contiguous source migration per prefix 0001-0018, found ${migrations.join(",")}`);
}
const ingestMigration = read("migrations/0010_multi_user_ingest.sql");
requireText(ingestMigration, "CREATE TABLE upload_admissions", "migration 0010");
requireText(ingestMigration, "CREATE TRIGGER upload_admissions_reserve", "migration 0010");
requireText(ingestMigration, "CREATE TABLE upload_intents", "migration 0010");
requireText(ingestMigration, "admission_id TEXT NOT NULL UNIQUE", "migration 0010");
requireText(ingestMigration, "CREATE TRIGGER upload_intents_reserve", "migration 0010");
requireText(ingestMigration, "CREATE TRIGGER upload_intents_consume_admission", "migration 0010");
requireText(ingestMigration, "'reserved', 'object_written', 'aborting', 'committed'", "migration 0010");
requireText(ingestMigration, "WHEN OLD.state IN ('reserved', 'object_written', 'aborting')", "migration 0010");
requireText(ingestMigration, "RAISE(ABORT, 'upload_admission_rejected')", "migration 0010");
requireText(ingestMigration, "RAISE(ABORT, 'upload_reservation_rejected')", "migration 0010");
const deletionAuthorityMigration = read("migrations/0015_deletion_receipt_authorities.sql");
requireText(deletionAuthorityMigration, "CREATE TABLE account_deletion_receipts", "migration 0015");
requireText(deletionAuthorityMigration, "UPDATE account_deletions", "migration 0015");
const magicLinkMigration = read("migrations/0016_magic_link_session_claims.sql");
requireText(magicLinkMigration, "ADD COLUMN claim_nonce", "migration 0016");
requireText(magicLinkMigration, "CREATE UNIQUE INDEX magic_links_claim_nonce", "migration 0016");
const rateLimitMigration = read("migrations/0017_rate_limit_attempts.sql");
requireText(rateLimitMigration, "CREATE TABLE auth_rate_limit_attempts", "migration 0017");
requireText(rateLimitMigration, "CREATE TRIGGER auth_rate_limit_attempt_applied", "migration 0017");
const inviteMigration = read("migrations/0018_account_invites.sql");
requireText(inviteMigration, "CREATE TABLE account_invites", "migration 0018");
requireText(inviteMigration, "CHECK (length(invite_lookup) = 64)", "migration 0018");
requireText(inviteMigration, "expires_at TEXT NOT NULL", "migration 0018");
requireText(inviteMigration, "CHECK (expires_at > created_at)", "migration 0018");
requireText(inviteMigration, "CREATE INDEX account_invites_expiry", "migration 0018");

const workflow = read(".github/workflows/cloud-ci.yml", repository);
for (const line of workflow.split("\n")) {
  if (line.includes("wrangler deploy") && !line.includes("--dry-run")) {
    failures.push("Cloud CI contains a non-dry-run wrangler deployment command");
  }
}
requireText(workflow, "permissions:\n  contents: read", "Cloud CI");
for (const command of [
  "npm ci", "npm run check", "npm run verify:production-safety", "npm run test:smoke",
  "npm run build:vm", "--config wrangler.ingest.toml", "--config wrangler.account.toml",
  "--config wrangler.maintenance.toml", "npm audit --audit-level=moderate",
]) requireText(workflow, command, "Cloud CI");

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
  checkedFiles: checked.size,
}, null, 2));
