import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const index = await readFile(path.join(ROOT, "index.html"), "utf8");
const styles = await readFile(path.join(ROOT, "assets/landing.css"), "utf8");
const script = await readFile(path.join(ROOT, "assets/landing.js"), "utf8");

test("landing page makes the health-data automation bridge the primary message", () => {
  assert.match(index, /The Private Bridge Between Health Data and Automation/);
  assert.match(index, /Health data<br><em>in motion\.<\/em>/);
  assert.match(index, /A private bridge from Apple Health and Health Connect to your files, scripts, and agents/);
  assert.match(index, /data-strand-canvas/);
  assert.match(index, /HEALTH\.MD \/ ROUTING MATRIX/);
});

test("hero keeps the first viewport focused and minimal", () => {
  assert.match(index, /class="hero hero-minimal"/);
  assert.doesNotMatch(index, /hero-telemetry/);
  assert.doesNotMatch(index, /marquee-band/);
  assert.match(styles, /\.hero\.hero-minimal\s*{[\s\S]*?height:\s*100svh/);
  assert.match(styles, /\.minimal-hero-copy\s*{[\s\S]*?backdrop-filter:\s*none/);
  assert.match(script, /full:\s*true/);
  assert.match(script, /colorA:\s*"#d4d4d0"/);
});

test("hero DNA uses projected depth and B-DNA-inspired geometry", () => {
  assert.match(script, /fullGeometry/);
  assert.match(script, /grooveOffset:\s*Math\.PI \* 0\.86/);
  assert.match(script, /geometry\.pitch \/ 10\.5/);
  assert.match(script, /items\.sort/);
  assert.match(script, /kind:\s*"rung"/);
  assert.match(script, /kind:\s*"backbone"/);
});

test("landing page is a deliberate light-mode instrument design", () => {
  assert.match(styles, /color-scheme:\s*light/);
  assert.match(styles, /--paper:\s*#f2f1ec/);
  assert.match(styles, /--orange:\s*#ff4f22/);
  assert.doesNotMatch(index, /data-theme-option/);
});

test("landing interactions include motion safeguards and keyboard-operable tabs", () => {
  assert.match(script, /prefers-reduced-motion: reduce/);
  assert.match(script, /requestAnimationFrame/);
  assert.match(script, /IntersectionObserver/);
  assert.match(script, /ArrowRight/);
  assert.match(script, /ArrowLeft/);
  assert.match(index, /role="tablist"/);
  assert.match(index, /role="tabpanel"/);
});

test("landing page JSON-LD blocks remain valid JSON", () => {
  const blocks = [...index.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
  assert.equal(blocks.length, 2);
  for (const [, source] of blocks) assert.doesNotThrow(() => JSON.parse(source));
});

test("landing page asset references resolve in the website source", async () => {
  const references = new Set(
    [...index.matchAll(/(?:href|src)="(assets\/[^"]+)"/g)].map((match) => match[1]),
  );
  assert.ok(references.size > 0);
  await Promise.all([...references].map((reference) => access(path.join(ROOT, reference))));
});

test("same-page landing links point to existing section ids", () => {
  const ids = new Set([...index.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]));
  const targets = [...index.matchAll(/href="#([^"]+)"/g)].map((match) => match[1]);
  for (const target of targets) assert.ok(ids.has(target), `missing #${target}`);
});
