import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const child = spawn(
  resolve(root, "node_modules/.bin/wrangler"),
  ["deploy", "--dry-run", "--outdir", ".wrangler/dry-run"],
  {
    cwd: root,
    stdio: "inherit",
    env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
  },
);

const exitCode = await new Promise((resolveExit, reject) => {
  child.once("error", reject);
  child.once("exit", (code, signal) => {
    if (signal) reject(new Error(`Wrangler terminated by ${signal}`));
    else resolveExit(code ?? 1);
  });
});
process.exitCode = exitCode;
