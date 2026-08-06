import { readFile, readdir } from "node:fs/promises";
import { dirname, extname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const roots = ["src", "static", "fixtures", "qualification/v1", "dist"].map(path => resolve(root, path));
const extensions = new Set([".ts", ".tsx", ".css", ".html", ".js", ".json", ".md"]);
const findings = [];
const categories = new Set();

async function filesUnder(directory) {
  const output = [];
  try {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) output.push(...await filesUnder(path));
      else if (extensions.has(extname(entry.name))) output.push(path);
    }
  } catch (error) { if (error.code !== "ENOENT") throw error; }
  return output;
}
function report(category, display, message) { categories.add(category); findings.push(`${display}: ${message}`); }
function scan(display, contents) {
  const built = display.startsWith("dist/");
  for (const match of contents.matchAll(/https?:\/\/[^\s"'`<>)}\]]+/gi)) {
    let url; try { url = new URL(match[0]); } catch { report("destination", display, "malformed URL"); continue; }
    const inertBundledNamespace = built && ["react.dev", "www.w3.org"].includes(url.hostname);
    const approvedReservedHost = ["practice.invalid", "example.invalid", "localhost", "127.0.0.1"].includes(url.hostname);
    if (!inertBundledNamespace && !approvedReservedHost) report("destination", display, `third-party or production-like destination ${url.origin}`);
  }
  const checks = [
    ["secret", /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bBearer\s+[A-Za-z0-9._~-]{12,}|\bsk_(?:live|test)_[A-Za-z0-9]{8,}|\bAKIA[A-Z0-9]{16}\b/i, "credential or private-key material"],
    ["real-person", /\b\d{3}-\d{2}-\d{4}\b|\b(?:MRN|medical record number)\s*[:#]\s*[A-Za-z0-9-]{4,}|\b[A-Z][a-z]+\s+[A-Z][a-z]+\s+DOB\s+\d{4}-\d{2}-\d{2}\b/, "real-person/identity marker"],
    ["contact", /\b[A-Z0-9._%+-]+@(?!example\.invalid\b|practice\.invalid\b)[A-Z0-9.-]+\.[A-Z]{2,}\b/i, "non-reserved email address"],
    ["analytics", /google-analytics|segment\.com|hotjar|mixpanel|sentry\.io/i, "analytics, replay, or telemetry destination"],
    ["unsafe-html", /dangerouslySetInnerHTML|\.innerHTML\b|document\.write\s*\(/, "unsafe HTML sink"],
  ];
  for (const [category, pattern, message] of checks) if (!(built && category === "unsafe-html") && pattern.test(contents)) report(category, display, message);
  if (/<(?:img|script|link)[^>]+(?:src|href)=["']\/\//i.test(contents)) report("destination", display, "protocol-relative asset");
}

if (process.argv.includes("--seed-canary")) {
  scan("seed/credential", "Authorization: Bearer canary_secret_material_12345");
  scan("seed/person", "Morgan Actual DOB 1980-01-02 and SSN 123-45-6789");
  scan("seed/destination", "https://analytics.example.com/collect");
  scan("seed/unapproved-reserved", "https://unapproved.invalid/collect");
  scan("seed/analytics", "https://segment.com/collect");
  scan("seed/contact", "person@nonreserved.test");
  scan("seed/unsafe-html", "element.innerHTML = payload");
  const expected = ["secret", "real-person", "destination", "analytics", "contact", "unsafe-html"];
  if (expected.some(category => !categories.has(category)) || !findings.some(finding => finding.includes("seed/unapproved-reserved"))) throw new Error(`Scanner canary was not rejected by every detector, including an unapproved .invalid host: ${[...categories].join(", ")}`);
  console.log(`Synthetic scanner canary correctly rejected ${findings.length} seeded prohibited values across ${expected.length} categories, including an unapproved .invalid host.`);
  process.exit(0);
}

const files = (await Promise.all(roots.map(filesUnder))).flat();
for (const path of files) scan(relative(root, path), await readFile(path, "utf8"));
const source = (await Promise.all(files.filter(path => path.includes(`${join("", "src")}/`) || path.includes(`${join("", "static")}/`)).map(path => readFile(path, "utf8")))).join("\n");
if (/localStorage|sessionStorage|indexedDB|serviceWorker/.test(source)) report("persistence", "src/static", "browser persistence API");
if (/console\.(?:log|debug|info|warn|error)/.test(source)) report("logging", "src/static", "browser logging call");

const rootEntries = await readdir(root, { withFileTypes: true });
for (const entry of rootEntries) {
  if (entry.isFile() && (/^\.dev\.vars(?:\..+)?$/.test(entry.name) || /^\.env(?:\..+)?$/.test(entry.name)) && entry.name !== ".env.example") report("secret", entry.name, "local secret/config file");
  if (entry.isFile() && /^wrangler\..+\.toml$/.test(entry.name)) report("deployment", entry.name, "alternate deployment configuration");
}
const wrangler = await readFile(resolve(root, "wrangler.toml"), "utf8");
if (!/^workers_dev\s*=\s*false$/m.test(wrangler) || /^routes?\s*=/m.test(wrangler) || /^\[\[routes?\]\]/m.test(wrangler) || /^\[env\./m.test(wrangler)) report("deployment", "wrangler.toml", "runtime must have no route, workers.dev, or named environment");
const sections = [...wrangler.matchAll(/^\[([^\]]+)\]$/gm)].map(match => match[1]);
if (sections.some(section => !["assets", "vars"].includes(section))) report("deployment", "wrangler.toml", `unsupported binding/config section ${sections.join(", ")}`);
if (!/^PRACTICE_RUNTIME_MODE\s*=\s*"synthetic"$/m.test(wrangler)) report("deployment", "wrangler.toml", "exact synthetic mode required");
const envExample = await readFile(resolve(root, ".env.example"), "utf8");
if (envExample.trim() !== "# Local development accepts this exact non-secret value only.\n# Any missing, unknown, or production-like value fails closed.\nPRACTICE_RUNTIME_MODE=synthetic") report("deployment", ".env.example", "unexpected configuration");
const packageJson = JSON.parse(await readFile(resolve(root, "package.json"), "utf8"));
if (JSON.stringify(Object.keys(packageJson.dependencies ?? {}).sort()) !== JSON.stringify(["react", "react-dom"])) report("dependency", "package.json", "unexpected runtime dependency");
const catalog = await readFile(resolve(root, "src/synthetic/catalog.ts"), "utf8");
for (const marker of ["Fictional Practice A", "(fictional)", "productionEnabled: false", 'mode: "synthetic"']) if (!catalog.includes(marker)) report("fictional", "src/synthetic/catalog.ts", `missing ${marker}`);
if (findings.length) throw new Error(`Synthetic boundary check failed:\n${findings.join("\n")}`);
console.log(`Synthetic source/build/fixture/qualification scan passed for ${files.length} files.`);
