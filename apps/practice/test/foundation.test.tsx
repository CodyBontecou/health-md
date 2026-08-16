import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import {
  assertRelativeApiPath,
  PRACTICE_INSTRUCTION_VERSION,
  PRACTICE_PROTOCOL_VERSION,
  practiceApiPaths,
} from "../src/contracts/api";
import {
  parsePracticeEnvironment,
  PracticeConfigurationError,
} from "../src/environment";
import { contentSecurityPolicy, jsonResponse } from "../src/http/security";
import { syntheticCatalog, syntheticMeta } from "../src/synthetic/catalog";
import { App } from "../src/web/App";
import { assertSafeRouteManifest, portalRoutes } from "../src/web/routes";

describe("synthetic foundation", () => {
  it("accepts only the exact synthetic runtime mode", () => {
    expect(parsePracticeEnvironment({ PRACTICE_RUNTIME_MODE: "synthetic" })).toEqual({
      mode: "synthetic",
    });
    for (const value of [undefined, "", "production", "Synthetic", "synthetic "]) {
      expect(() => parsePracticeEnvironment({ PRACTICE_RUNTIME_MODE: value })).toThrow(
        PracticeConfigurationError,
      );
    }
  });

  it("pins the governed drafts and cannot report production enabled", () => {
    expect(syntheticMeta.protocolVersion).toBe(PRACTICE_PROTOCOL_VERSION);
    expect(syntheticMeta.protocolVersion).toBe("1.0-draft.4");
    expect(syntheticMeta.instructionVersion).toBe(PRACTICE_INSTRUCTION_VERSION);
    expect(syntheticMeta.productionEnabled).toBe(false);
    expect(syntheticMeta.label).toContain("no real patient data");
    expect(syntheticCatalog.users.every((user) => user.displayName.includes("fictional"))).toBe(true);
    expect(syntheticCatalog.practices.every((practice) => practice.displayName.startsWith("Fictional"))).toBe(true);

    const practicesById = new Map(syntheticCatalog.practices.map((practice) => [practice.id, practice]));
    const requestsById = new Map(syntheticCatalog.requests.map((request) => [request.id, request]));
    expect(practicesById.size).toBe(syntheticCatalog.practices.length);
    expect(requestsById.size).toBe(syntheticCatalog.requests.length);
    for (const user of syntheticCatalog.users) expect(practicesById.has(user.practiceId)).toBe(true);
    for (const request of syntheticCatalog.requests) expect(practicesById.has(request.practiceId)).toBe(true);
    for (const packet of syntheticCatalog.packets) {
      const request = requestsById.get(packet.requestId);
      expect(request).toBeDefined();
      expect(request?.practiceId).toBe(packet.practiceId);
    }
  });

  it("uses only fixed, identifier-free browser and API paths", () => {
    expect(() => assertSafeRouteManifest()).not.toThrow();
    expect(new Set(portalRoutes).size).toBe(portalRoutes.length);
    for (const path of portalRoutes) {
      expect(path).not.toContain("?");
      expect(path).not.toMatch(/:[A-Za-z]|\[[^\]]+\]|\{[^}]+\}/);
    }
    for (const path of Object.values(practiceApiPaths)) {
      expect(() => assertRelativeApiPath(path)).not.toThrow();
    }
    for (const path of ["https://example.invalid/api", "//example.invalid", "/api?v=1", "api/v1"]) {
      expect(() => assertRelativeApiPath(path)).toThrow();
    }
  });

  it("applies restrictive no-store headers without CORS", () => {
    const response = jsonResponse({ ok: true });
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.headers.get("Content-Security-Policy")).toBe(contentSecurityPolicy);
    expect(response.headers.get("Referrer-Policy")).toBe("no-referrer");
    expect(response.headers.get("Strict-Transport-Security")).toBe("max-age=31536000; includeSubDomains");
    expect(response.headers.get("X-Frame-Options")).toBe("DENY");
    expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(response.headers.has("Access-Control-Allow-Origin")).toBe(false);
    expect(contentSecurityPolicy).toContain("default-src 'none'");
    expect(contentSecurityPolicy).toContain("connect-src 'self'");
    expect(contentSecurityPolicy).not.toContain("unsafe-inline");
    expect(contentSecurityPolicy).not.toContain("unsafe-eval");
  });

  it("escapes hostile fictional content and keeps boundary copy visible", () => {
    const markup = renderToStaticMarkup(
      <App initialPath="/portal" initialCatalog={syntheticCatalog} />,
    );
    expect(markup).toContain("Synthetic demo — no real patient data");
    expect(markup).toContain("exchanges documents only");
    expect(markup).toContain("&lt;img src=x onerror=alert(1)&gt;");
    expect(markup).not.toContain("<img src=x");
    expect(markup).not.toContain("dangerouslySetInnerHTML");
  });

  it("ships no inline script or externally hosted asset", async () => {
    const html = await readFile(resolve(import.meta.dirname, "../static/index.html"), "utf8");
    expect(html).not.toMatch(/<script(?![^>]*\bsrc=)/i);
    expect(html).not.toMatch(/(?:src|href)=["'](?:https?:)?\/\//i);
    expect(html).toContain('src="/assets/app.js"');
    expect(html).toContain('href="/styles.css"');
  });
});
