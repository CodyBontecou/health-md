import { createHmac } from "node:crypto";
import { closeSync, existsSync, openSync, readFileSync, statSync, unlinkSync, writeFileSync } from "node:fs";

const emailFile = process.env.HEALTHMD_INVITE_EMAIL_FILE;
const keyFile = process.env.HEALTHMD_IDENTITY_KEY_FILE;
const outputFile = process.env.HEALTHMD_INVITE_SQL_OUTPUT;
const expiresAt = process.env.HEALTHMD_INVITE_EXPIRES_AT;
const operation = process.env.HEALTHMD_INVITE_OPERATION ?? "grant";
const EMAIL_PATTERN = /^[^\s@]{1,64}@[^\s@]{1,190}$/u;

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}
function privateRegularFile(path, label) {
  if (!path) fail(`${label} path is required.`);
  let metadata;
  try { metadata = statSync(path); } catch { fail(`${label} is unavailable.`); }
  if (!metadata.isFile() || (metadata.mode & 0o077) !== 0) {
    fail(`${label} must be a regular owner-only file.`);
  }
}

privateRegularFile(emailFile, "Invite email input");
privateRegularFile(keyFile, "Identity key input");
if (!outputFile) fail("Invite SQL output path is required.");
if (existsSync(outputFile)) fail("Invite SQL output already exists.");

if (operation !== "grant" && operation !== "revoke") fail("Invite operation must be grant or revoke.");
const now = new Date();
const expiry = operation === "grant" ? new Date(expiresAt ?? "") : null;
if (operation === "grant" && (!expiry || !Number.isFinite(expiry.getTime()) || expiry <= now ||
    expiry.getTime() > now.getTime() + 90 * 86_400_000)) {
  fail("Invite expiry must be a future ISO timestamp no more than 90 days away.");
}
if (operation === "revoke" && expiresAt) fail("Invite revocation must not specify an expiry.");
const canonicalExpiry = expiry?.toISOString();
const keyText = readFileSync(keyFile, "utf8").trim();
if (!/^[A-Za-z0-9+/]{43}=$/u.test(keyText)) fail("Identity key must be canonical base64.");
const key = Buffer.from(keyText, "base64");
if (key.byteLength !== 32 || key.toString("base64") !== keyText) {
  fail("Identity key must contain exactly 32 bytes.");
}
const emails = readFileSync(emailFile, "utf8").split(/\r?\n/u).filter((line) => line.trim() !== "")
  .map((line) => line.trim().toLowerCase());
if (emails.length < 1 || emails.length > 1_000 || emails.some((email) =>
  email.length > 254 || !EMAIL_PATTERN.test(email) || /[\r\n]/u.test(email))) {
  fail("Invite input must contain 1 through 1000 valid email addresses.");
}
if (new Set(emails).size !== emails.length) fail("Invite input contains duplicate normalized addresses.");
const lookups = emails.map((email) => createHmac("sha256", key)
  .update(`email-lookup-v1\0${email}`, "utf8").digest("hex"));
const createdAt = now.toISOString();
const sql = [
  "BEGIN TRANSACTION;",
  ...lookups.map((lookup) => operation === "grant" ?
    `INSERT INTO account_invites (email_lookup, created_at, expires_at) VALUES ('${lookup}', '${createdAt}', '${canonicalExpiry}') ON CONFLICT(email_lookup) DO UPDATE SET created_at = excluded.created_at, expires_at = excluded.expires_at;` :
    `DELETE FROM account_invites WHERE email_lookup = '${lookup}';`),
  "COMMIT;",
  "",
].join("\n");
let descriptor;
let createdOutput = false;
try {
  descriptor = openSync(outputFile, "wx", 0o600);
  createdOutput = true;
  writeFileSync(descriptor, sql, { encoding: "utf8" });
  closeSync(descriptor);
} catch {
  if (descriptor !== undefined) {
    try { closeSync(descriptor); } catch { /* already closed */ }
  }
  if (createdOutput) {
    try { unlinkSync(outputFile); } catch { /* preserve the fixed failure below */ }
  }
  fail("Invite SQL output could not be written safely.");
}
const operationLabel = operation === "grant" ? "grant" : "revocation";
process.stdout.write(`Prepared ${lookups.length} hashed account invite ${operationLabel}${lookups.length === 1 ? "" : "s"}.\n`);
