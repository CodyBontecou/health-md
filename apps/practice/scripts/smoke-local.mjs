import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const port = "18787";
const child = spawn(
  resolve(root, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--ip", "127.0.0.1", "--port", port],
  {
    cwd: root,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, WRANGLER_SEND_METRICS: "false" },
  },
);
let output = "";
child.stdout.on("data", (chunk) => { output += chunk.toString(); });
child.stderr.on("data", (chunk) => { output += chunk.toString(); });

const deadline = Date.now() + 45_000;
const baseUrl = `http://127.0.0.1:${port}`;

function assertClinicalHeaders(response) {
  if (response.headers.get("cache-control") !== "no-store") {
    throw new Error("Local runtime did not return Cache-Control: no-store");
  }
  if (!response.headers.get("content-security-policy")?.includes("default-src 'none'")) {
    throw new Error("Local runtime did not return the restrictive CSP");
  }
  if (response.headers.get("access-control-allow-origin") !== null) {
    throw new Error("Local runtime unexpectedly returned a CORS header");
  }
}

async function verifyStaticRuntime() {
  const expected = [
    ["/portal", 200, "text/html"],
    ["/styles.css", 200, "text/css"],
    ["/assets/app.js", 200, "javascript"],
    ["/portal/report/packet_synthetic_apple", 404, "text/plain"],
  ];
  for (const [path, status, contentType] of expected) {
    const response = await fetch(`${baseUrl}${path}`, { cache: "no-store" });
    if (response.status !== status) throw new Error(`${path} returned ${response.status}`);
    if (!response.headers.get("content-type")?.includes(contentType)) {
      throw new Error(`${path} returned an unexpected content type`);
    }
    assertClinicalHeaders(response);
    const body = await response.text();
    if (path === "/portal" && !body.includes("Health.md Practice")) {
      throw new Error("Portal route did not return the built application shell");
    }
  }
}

try {
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`Wrangler exited with ${child.exitCode}: ${output.slice(-2000)}`);
    }
    try {
      const response = await fetch(`${baseUrl}/api/v1/meta`, {
        headers: { Accept: "application/json" },
        cache: "no-store",
      });
      if (response.ok) {
        const body = await response.json();
        if (body.mode !== "synthetic" || body.productionEnabled !== false) {
          throw new Error("Local runtime did not report the synthetic production gate");
        }
        assertClinicalHeaders(response);
        await verifyStaticRuntime();
        console.log("Synthetic local API, portal, assets, and rejection smoke checks passed.");
        process.exitCode = 0;
        break;
      }
    } catch (error) {
      if (error instanceof Error && !error.message.includes("fetch failed")) throw error;
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 250));
  }
  if (process.exitCode !== 0) {
    throw new Error(`Timed out waiting for local runtime: ${output.slice(-2000)}`);
  }
} finally {
  child.kill("SIGTERM");
  await Promise.race([
    new Promise((resolveExit) => child.once("exit", resolveExit)),
    new Promise((resolveWait) => setTimeout(resolveWait, 2_000)),
  ]);
  if (child.exitCode === null) child.kill("SIGKILL");
}
