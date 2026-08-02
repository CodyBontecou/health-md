import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const packageRoot = fileURLToPath(new URL("../", import.meta.url));
const queryPath = fileURLToPath(new URL("../queries/onboarding-funnel.sql", import.meta.url));
const wranglerPath = fileURLToPath(
  new URL("../node_modules/wrangler/bin/wrangler.js", import.meta.url),
);
const sql = readFileSync(queryPath, "utf8")
  .replace(/^--.*$/gm, "")
  .trim();

const result = spawnSync(
  process.execPath,
  [wranglerPath, "d1", "execute", "health-md-pricing-analytics", "--remote", "--command", sql],
  { cwd: packageRoot, stdio: "inherit" },
);

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
