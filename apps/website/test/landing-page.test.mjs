import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const index = await readFile(path.join(ROOT, "index.html"), "utf8");
const styles = await readFile(path.join(ROOT, "assets/landing.css"), "utf8");
const script = await readFile(path.join(ROOT, "assets/landing.js"), "utf8");
const threeScript = await readFile(path.join(ROOT, "assets/landing-three.js"), "utf8");
const buildScript = await readFile(path.join(ROOT, "scripts/build-site.mjs"), "utf8");
const packageJson = JSON.parse(await readFile(path.join(ROOT, "package.json"), "utf8"));

test("landing page makes the private automation bridge the only message", () => {
  assert.match(index, /The Private Bridge Between Health Data and Automation/);
  assert.match(index, /Health data<br><em>in motion\.<\/em>/);
  assert.match(index, /A private bridge from Apple Health and Health Connect to your files, scripts, and agents/);
  assert.match(index, /data-strand-canvas/);
  assert.equal((index.match(/<main>/g) ?? []).length, 1);
  assert.equal((index.match(/<section/g) ?? []).length, 1);
  assert.doesNotMatch(index, /id="bridge"|id="automation"|id="interfaces"|id="download"/);
  assert.doesNotMatch(index, /<footer/);
});

test("landing experience is locked to one viewport with a docs-only header", () => {
  assert.match(index, /<nav class="header-nav" aria-label="Documentation">/);
  assert.match(index, /<a class="header-docs-link" href="docs\/">/);
  assert.doesNotMatch(index, /data-menu-toggle|primary-navigation/);
  assert.match(styles, /html,\s*\nbody\s*{[\s\S]*?overflow:\s*hidden/);
  assert.match(styles, /main,\s*\n\.hero\s*{[\s\S]*?height:\s*100svh/);
  assert.match(styles, /\.hero-copy\s*{[\s\S]*?backdrop-filter:\s*none/);
});

test("hero uses official store badges with direct marketplace links", () => {
  const actions = index.match(/<div class="hero-actions"[\s\S]*?<\/div>/)?.[0] ?? "";
  assert.equal((actions.match(/<a /g) ?? []).length, 2);
  assert.match(actions, /href="https:\/\/apps\.apple\.com\/us\/app\/health-md\/id6757763969"/);
  assert.match(actions, /href="https:\/\/play\.google\.com\/store\/apps\/details\?id=com\.healthmd\.android"/);
  assert.match(actions, /assets\/store-badges\/download-on-app-store\.svg/);
  assert.match(actions, /assets\/store-badges\/get-it-on-google-play\.png/);
  assert.match(styles, /\.hero-store-badge-apple img\s*{[\s\S]*?width:\s*146px/);
  assert.match(styles, /\.hero-store-badge-google img\s*{[\s\S]*?width:\s*167px/);
});

test("hero DNA has projected depth and B-DNA-inspired Canvas fallback geometry", () => {
  assert.match(script, /fullGeometry/);
  assert.match(script, /grooveOffset:\s*Math\.PI \* 0\.86/);
  assert.match(script, /geometry\.pitch \/ 10\.5/);
  assert.match(script, /items\.sort/);
  assert.match(script, /kind:\s*"rung"/);
  assert.match(script, /kind:\s*"backbone"/);
  assert.match(script, /colorA:\s*"#d4d4d0"/);
});

test("hero upgrades to a locally served Three.js molecular scene", () => {
  assert.match(index, /<script type="module" src="assets\/landing-three\.js"><\/script>/);
  assert.match(index, /data-three-strand/);
  assert.match(threeScript, /THREE\.WebGLRenderer/);
  assert.match(threeScript, /THREE\.TubeGeometry/);
  assert.match(threeScript, /THREE\.CylinderGeometry/);
  assert.match(threeScript, /pitch \/ 10\.5/);
  assert.match(threeScript, /group\.rotation\.x/);
  assert.equal(packageJson.dependencies.three, "^0.185.1");
  assert.match(buildScript, /three\.module\.min\.js/);
  assert.match(buildScript, /three\.core\.min\.js/);
  assert.match(buildScript, /three\.LICENSE\.txt/);
});

test("landing page keeps the deliberate light-mode instrument design", () => {
  assert.match(styles, /color-scheme:\s*light/);
  assert.match(styles, /--paper:\s*#f6f6f2/);
  assert.match(styles, /\.hero-axis::before/);
  assert.match(styles, /\.hero-route/);
  assert.doesNotMatch(index, /data-theme-option|assets\/landing-minimal\.css/);
});

test("landing motion preserves safeguards and a static fallback", () => {
  assert.match(script, /prefers-reduced-motion: reduce/);
  assert.match(script, /requestAnimationFrame/);
  assert.match(script, /IntersectionObserver/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(script, /healthmd-three-failed/);
});

test("landing page JSON-LD remains valid and matches visible scope", () => {
  const blocks = [...index.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
  assert.equal(blocks.length, 1);
  for (const [, source] of blocks) assert.doesNotThrow(() => JSON.parse(source));
  assert.doesNotMatch(index, /FAQPage/);
});

test("landing page asset references resolve in the website source", async () => {
  const references = new Set(
    [...index.matchAll(/(?:href|src)="(assets\/[^"]+)"/g)].map((match) => match[1]),
  );
  assert.ok(references.size > 0);
  await Promise.all([...references].map((reference) => access(path.join(ROOT, reference))));
});

test("same-page landing links point to existing ids", () => {
  const ids = new Set([...index.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]));
  const targets = [...index.matchAll(/href="#([^"]+)"/g)].map((match) => match[1]);
  for (const target of targets) assert.ok(ids.has(target), `missing #${target}`);
});
