import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function run(command, args) {
  return new Promise((resolveRun, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      stdio: "inherit",
      shell: false,
      env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
    });
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (signal) reject(new Error(`${command} terminated by ${signal}`));
      else if (code === 0) resolveRun();
      else reject(new Error(`${command} exited with ${code ?? "unknown"}`));
    });
  });
}

const port = process.env.PRACTICE_LOCAL_PORT ?? "8787";
const protocol = process.env.PRACTICE_LOCAL_PROTOCOL ?? "http";
if (!/^\d{2,5}$/.test(port)) throw new Error("PRACTICE_LOCAL_PORT must be a numeric local port");
if (protocol !== "http" && protocol !== "https") throw new Error("PRACTICE_LOCAL_PROTOCOL must be http or https");
if (process.argv.includes("--prebuilt")) {
  // Only check:ci uses this path, immediately after check built the current tree.
  // Standalone npm start and test:e2e always build their own assets.
  const manifest = JSON.parse(await readFile(resolve(root, "dist/asset-manifest.json"), "utf8"));
  if (manifest.mode !== "synthetic") throw new Error("Prebuilt assets must be synthetic");
  for (const asset of ["index.html", "assets/app.js", "styles.css"]) {
    if ((await readFile(resolve(root, "dist", asset))).length === 0) {
      throw new Error(`Prebuilt asset is empty: ${asset}`);
    }
  }
} else {
  await run(process.execPath, [resolve(root, "scripts/build.mjs")]);
}
console.log(`Starting synthetic-only Practice portal at ${protocol}://127.0.0.1:${port}`);
await run(resolve(root, "node_modules/.bin/wrangler"), ["dev", "--local", "--local-protocol", protocol, "--ip", "127.0.0.1", "--port", port]);
