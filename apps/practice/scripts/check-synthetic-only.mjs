import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { reviewedBinarySha256, syntheticBoundaryFiles } from "./synthetic-boundary-manifest.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(root, "../..");
const findings = [];
const categories = new Set();
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const runtimePrefixes = ["apps/practice/src/", "apps/practice/static/", "apps/practice/dist/"];
const testPrefixes = ["apps/practice/test/", "apps/practice/e2e/"];
const approvedRuntimeHosts = new Set(["practice.invalid", "example.invalid", "localhost", "127.0.0.1"]);
const approvedTestHosts = new Set([...approvedRuntimeHosts, "practice.synthetic.invalid", "remote.invalid", "invalid.example", "other.invalid"]);
const approvedDiscoveryReferenceHosts = new Set(["hl7.org", "fhir.epic.com", "www.mychart.org", "docs.athenahealth.com", "www.athenahealth.com", "fhir.eclinicalworks.com", "healow.com", "docs.oracle.com", "www.oracle.com"]);
const analyticsDefinitionFiles = new Set(["apps/practice/scripts/check-synthetic-only.mjs", "apps/practice/scripts/test-declarations.mjs", "apps/practice/test/clinical-boundary.test.ts"]);

function report(category, display, message) { categories.add(category); findings.push(`${display}: ${message}`); }
function sha256(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function isRuntime(display) { return runtimePrefixes.some(prefix => display.startsWith(prefix)); }
function isTest(display) { return testPrefixes.some(prefix => display.startsWith(prefix)); }
function dependencyMetadata(display) { return display === "apps/practice/package-lock.json" || display === "apps/practice/LICENSE"; }
function approvedUrl(display, url) {
  if (!/^https?:$/.test(url.protocol)) return false;
  const builtNamespace = display.startsWith("apps/practice/dist/") && ["react.dev", "www.w3.org"].includes(url.hostname);
  if (builtNamespace || approvedRuntimeHosts.has(url.hostname)) return true;
  if (display === "docs/product/practice/pilot-ehr-vendor-discovery-aid.md" && approvedDiscoveryReferenceHosts.has(url.hostname)) return true;
  return isTest(display) && approvedTestHosts.has(url.hostname);
}
function scan(display, contents) {
  if (!dependencyMetadata(display)) {
    for (const match of contents.matchAll(/https?:\/\/[^\s"'`<>)}\]]+/gi)) {
      const candidate = match[0].split("${", 1)[0];
      let url; try { url = new URL(candidate); } catch { report("destination", display, "malformed URL"); continue; }
      if (!approvedUrl(display, url)) report("destination", display, `third-party or production-like destination ${url.origin}`);
    }
  }
  const checks = [
    ["secret", /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bBearer\s+[A-Za-z0-9._~-]{12,}|\bsk_(?:live|test)_[A-Za-z0-9]{8,}|\bAKIA[A-Z0-9]{16}\b/i, "credential or private-key material"],
    ["real-person", /\b\d{3}-\d{2}-\d{4}\b|\b(?:MRN|medical record number)\s*[:#]\s*[A-Za-z0-9-]{4,}|\b[A-Z][a-z]+\s+[A-Z][a-z]+\s+DOB\s+\d{4}-\d{2}-\d{2}\b/, "real-person/identity marker"],
    ["contact", /\b[A-Z0-9._%+-]+@(?!example\.invalid\b|practice\.invalid\b)[A-Z0-9.-]+\.[A-Z]{2,}\b/i, "non-reserved email address"],
    ["analytics", /google-analytics|segment\.com|hotjar|mixpanel|sentry\.io/i, "analytics, replay, or telemetry destination"],
  ];
  for (const [category, pattern, message] of checks) if (!(category === "analytics" && analyticsDefinitionFiles.has(display)) && pattern.test(contents)) report(category, display, message);
  if (isRuntime(display) && /dangerouslySetInnerHTML|\.innerHTML\b|document\.write\s*\(/.test(contents) && !display.startsWith("apps/practice/dist/")) report("unsafe-html", display, "unsafe HTML sink");
  if (isRuntime(display) && /<(?:img|script|link)[^>]+(?:src|href)=["']\/\//i.test(contents)) report("destination", display, "protocol-relative asset");
}

if (process.argv.includes("--seed-canary")) {
  scan("seed/credential", ["Authorization: Be", "arer canary_secret_material_12345"].join(""));
  scan("seed/person", ["Morgan Ac", "tual DOB 1980-01-02 and SSN ", ["123", "45", "6789"].join("-")].join(""));
  scan("seed/destination", ["ht", "tps://analytics", ".example.com/collect"].join(""));
  scan("seed/unapproved-reserved", ["ht", "tps://unapproved", ".invalid/collect"].join(""));
  scan("seed/analytics", ["ht", "tps://seg", "ment.com/collect"].join(""));
  scan("seed/contact", ["person@nonreserved", ".test"].join(""));
  scan("apps/practice/src/seed-unsafe.ts", ["element.in", "nerHTML = payload"].join(""));
  const expected = ["secret", "real-person", "destination", "analytics", "contact", "unsafe-html"];
  if (expected.some(category => !categories.has(category)) || !findings.some(finding => finding.includes("seed/unapproved-reserved"))) throw new Error(`Scanner canary was not rejected by every detector, including an unapproved .invalid host: ${[...categories].join(", ")}`);
  console.log(`Synthetic scanner canary correctly rejected ${findings.length} seeded prohibited values across ${expected.length} categories, including an unapproved .invalid host.`);
  process.exit(0);
}

const entries = await syntheticBoundaryFiles(root, repositoryRoot);
const decoded = new TextDecoder("utf-8", { fatal: true });
const runtimeText = [];
for (const entry of entries) {
  if (entry.symbolicLink) { report("filesystem", entry.display, "symbolic links are prohibited in the synthetic boundary"); continue; }
  const bytes = await readFile(entry.path);
  if (bytes.length > MAX_FILE_BYTES) { report("filesystem", entry.display, "file exceeds the bounded scanner size"); continue; }
  const reviewedSha = reviewedBinarySha256.get(entry.display);
  let contents;
  try {
    if (bytes.includes(0)) throw new TypeError("binary");
    contents = decoded.decode(bytes);
  } catch {
    if (!reviewedSha) report("binary", entry.display, "unexpected binary or invalid UTF-8 content");
    else if (sha256(bytes) !== reviewedSha) report("binary", entry.display, "reviewed binary digest changed");
    continue;
  }
  scan(entry.display, contents);
  if (entry.display.startsWith("apps/practice/src/") || entry.display.startsWith("apps/practice/static/")) runtimeText.push(contents);
  const name = basename(entry.display);
  if ((/^\.dev\.vars(?:\..+)?$/.test(name) || /^\.env(?:\..+)?$/.test(name)) && name !== ".env.example") report("secret", entry.display, "local secret/config file");
  if (/^wrangler\..+\.toml$/.test(name)) report("deployment", entry.display, "alternate deployment configuration");
}

const source = runtimeText.join("\n");
if (/localStorage|sessionStorage|indexedDB|serviceWorker/.test(source)) report("persistence", "apps/practice/src/static", "browser persistence API");
if (/console\.(?:log|debug|info|warn|error)/.test(source)) report("logging", "apps/practice/src/static", "browser logging call");

const workflowDirectory = resolve(repositoryRoot, ".github/workflows");
for (const entry of await readdir(workflowDirectory, { withFileTypes: true })) {
  if (!entry.isFile() || !/\.ya?ml$/.test(entry.name)) continue;
  const contents = await readFile(resolve(workflowDirectory, entry.name), "utf8");
  if (/apps\/practice|practice-ci|Health\.md Practice/i.test(contents) && /\b(?:wrangler|cloudflare|pages)\s+deploy\b|\bnpm\s+publish\b/i.test(contents)) report("deployment", `.github/workflows/${entry.name}`, "Practice deployment or publication command is prohibited");
}
const packageJson = JSON.parse(await readFile(resolve(root, "package.json"), "utf8"));
if (JSON.stringify(Object.keys(packageJson.dependencies ?? {}).sort()) !== JSON.stringify(["react", "react-dom"])) report("dependency", "apps/practice/package.json", "unexpected runtime dependency");
if (Object.values(packageJson.scripts ?? {}).some(value => /\b(?:wrangler|cloudflare|pages)\s+deploy\b|\bnpm\s+publish\b/i.test(String(value)))) report("deployment", "apps/practice/package.json", "deployment or publication script is prohibited");
const wrangler = await readFile(resolve(root, "wrangler.toml"), "utf8");
if (!/^workers_dev\s*=\s*false$/m.test(wrangler) || /^routes?\s*=/m.test(wrangler) || /^\[\[routes?\]\]/m.test(wrangler) || /^\[env\./m.test(wrangler)) report("deployment", "apps/practice/wrangler.toml", "runtime must have no route, workers.dev, or named environment");
const sections = [...wrangler.matchAll(/^\[([^\]]+)\]$/gm)].map(match => match[1]);
if (sections.some(section => !["assets", "vars"].includes(section))) report("deployment", "apps/practice/wrangler.toml", `unsupported binding/config section ${sections.join(", ")}`);
if (!/^PRACTICE_RUNTIME_MODE\s*=\s*"synthetic"$/m.test(wrangler)) report("deployment", "apps/practice/wrangler.toml", "exact synthetic mode required");
const envExample = await readFile(resolve(root, ".env.example"), "utf8");
if (envExample.trim() !== "# Local development accepts this exact non-secret value only.\n# Any missing, unknown, or production-like value fails closed.\nPRACTICE_RUNTIME_MODE=synthetic") report("deployment", "apps/practice/.env.example", "unexpected configuration");
const catalog = await readFile(resolve(root, "src/synthetic/catalog.ts"), "utf8");
for (const marker of ["Fictional Practice A", "(fictional)", "productionEnabled: false", 'mode: "synthetic"']) if (!catalog.includes(marker)) report("fictional", "apps/practice/src/synthetic/catalog.ts", `missing ${marker}`);
const requiredPrefixes = ["apps/practice/src/", "apps/practice/test/", "apps/practice/e2e/", "apps/practice/docs/", "apps/practice/scripts/", "apps/practice/qualification/v1/", "docs/product/practice/"];
for (const prefix of requiredPrefixes) if (!entries.some(entry => entry.display.startsWith(prefix))) report("coverage", prefix, "required synthetic boundary root was not scanned");

if (findings.length) throw new Error(`Synthetic boundary check failed:\n${findings.join("\n")}`);
console.log(`Synthetic source/build/test/document/config/workflow scan passed for ${entries.length} governed files, including reviewed binary policy.`);
