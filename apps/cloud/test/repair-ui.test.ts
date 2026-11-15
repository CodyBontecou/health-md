import { expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { runInNewContext } from "node:vm";

const publicDir = resolve(import.meta.dirname, "../public");
const asset = (name: string) => readFileSync(resolve(publicDir, name), "utf8");

it("uses one first-party planner in dashboard, explorer and standalone view, without a launch link", () => {
  const panel = asset("repair-panel.html");
  expect(panel).toContain('id="repair-form"');
  expect(panel).toContain('id="repair-drafts"');
  expect(panel).toContain('id="repair-provenance-results"');
  expect(panel).toContain('id="repair-read-provenance"');
  expect(panel).not.toMatch(/<script|<iframe|onload=|javascript:/iu);
  const ids = [...panel.matchAll(/\bid="([^"]+)"/gu)].map((match) => match[1]);
  expect(new Set(ids).size).toBe(ids.length);
  const labels = [...panel.matchAll(/\bfor="([^"]+)"/gu)].map((match) => match[1]);
  expect(labels.every((label) => ids.includes(label))).toBe(true);
  for (const name of ["dashboard.html", "explore.html", "repair.html"]) {
    const page = asset(name);
    expect(page).toContain('id="repair-mount"');
    expect(page).toContain('src="/repair.js"');
    expect(page).not.toContain('id="repair-form"');
    expect(page).not.toMatch(/healthmd:\/\//iu);
    if (name !== "repair.html") expect(page).toContain('href="#repair-planner"');
  }
  const script = asset("repair.js");
  expect(script).toContain('fetch("/repair-panel"');
  expect(script).toContain('new DOMParser()');
  expect(script).toContain('healthmd:repair-select');
  expect(script).toContain('healthmd:repair-provenance');
  expect(script).toContain('api("/api/repair/supplements", { date, offset })');
  expect(script).not.toMatch(/localStorage|sessionStorage|document\.cookie|healthmd:\/\//u);
  for (const name of ["dashboard.js", "explore.js"]) {
    expect(asset(name)).toContain('new CustomEvent("healthmd:repair-select"');
    expect(asset(name)).toContain('new CustomEvent("healthmd:repair-provenance"');
    // Both deferred scripts execute in one browser global scope. The shared
    // planner must not redeclare the dashboard/explorer's top-level bindings.
    expect(() => runInNewContext(`${asset(name)}\n${script}`, {
      document: { body: { dataset: { page: "none" } }, getElementById: () => null },
    })).not.toThrow();
  }
});
