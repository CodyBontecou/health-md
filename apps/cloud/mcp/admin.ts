import { join, resolve } from "node:path";
import { VmDatabase, vmReaderGroupId } from "../vm/storage";
import { keyedLookup } from "../src/crypto";
import { normalizeUsername } from "../src/password";
import { createReadToken, listReadTokens, revokeReadToken } from "./auth";

async function main(): Promise<void> {
  process.umask(vmReaderGroupId() === null ? 0o077 : 0o027);
  const dataDir = process.env.HEALTHMD_VM_DATA_DIR;
  const sourceDir = process.env.HEALTHMD_CLOUD_SOURCE_DIR;
  const identityKey = process.env.IDENTITY_KEY_B64;
  if (!dataDir || !sourceDir || !identityKey) throw new Error("Private MCP administration configuration missing");
  const [action, ...options] = (process.argv as string[]).slice(2);
  const flags = new Map<string, string>(options.map((option: string) => {
    const match = /^--([a-z-]+)=([^\u0000-\u001f]+)$/u.exec(option);
    if (!match) throw new Error("Use --user=owner --label=agent --days=90 or --id=<token-id>");
    return [match[1]!, match[2]!] as const;
  }));
  if (flags.size !== options.length) throw new Error("Duplicate CLI flags are not allowed");
  if (!action || !["create", "list", "revoke"].includes(action)) throw new Error("Use create, list or revoke");
  const db = new VmDatabase(resolve(dataDir), join(resolve(sourceDir), "migrations"));
  try {
    if (action === "revoke") {
      if (flags.size !== 1 || !flags.get("id")) throw new Error("Revoke requires --id=<token-id>");
      if (!revokeReadToken(db.connection, flags.get("id")!)) throw new Error("Token not found or already revoked");
      process.stdout.write("Read token revoked.\n");
      return;
    }
    const user = normalizeUsername(flags.get("user"));
    const lookup = await keyedLookup(user, identityKey, "username-lookup-v1");
    const row = db.connection.prepare(`SELECT p.user_id AS userId FROM password_credentials p
      JOIN users u ON u.id = p.user_id WHERE p.username_lookup = ? AND u.status = 'active'`)
      .get(lookup) as { userId: string } | undefined;
    if (!row) throw new Error("Active account not found");
    if (action === "list") {
      if (flags.size !== 1) throw new Error("List requires only --user=owner");
      process.stdout.write(`${JSON.stringify(listReadTokens(db.connection, row.userId))}\n`);
      return;
    }
    if (flags.size < 2 || flags.size > 4 || !flags.get("label") ||
        [...flags.keys()].some((key) => !["user", "label", "days", "scope"].includes(key)) ||
        (flags.has("scope") && !["aggregates", "full_export"].includes(flags.get("scope")!))) {
      throw new Error("Create requires --user=owner --label=agent [--days=90] [--scope=full_export]");
    }
    const issued = createReadToken(db.connection, row.userId, flags.get("label")!,
      flags.has("days") ? Number(flags.get("days")) : 90,
      flags.get("scope") === "full_export" ? "full_export" : "aggregates");
    process.stdout.write(`Token ID: ${issued.id}\nExpires: ${issued.expiresAt}\nRead token (shown once): ${issued.token}\n`);
  } finally { db.close(); }
}

main().catch(() => {
  // Never echo CLI arguments, tokens, usernames or DB errors in generic failures.
  process.stderr.write("Read-token administration failed; check usage and private migration state.\n");
  process.exitCode = 1;
});
