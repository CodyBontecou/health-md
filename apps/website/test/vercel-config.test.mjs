import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const config = JSON.parse(
  await readFile(new URL("../vercel.json", import.meta.url), "utf8"),
);

test("Vercel applies security headers to extensionless and directory routes", () => {
  const globalHeaders = config.headers.find((entry) => entry.source === "/(.*)");
  assert.ok(globalHeaders, "global headers must use Vercel's all-route pattern");

  const headers = new Map(
    globalHeaders.headers.map(({ key, value }) => [key.toLowerCase(), value]),
  );
  for (const required of [
    "content-security-policy",
    "permissions-policy",
    "referrer-policy",
    "x-content-type-options",
    "x-frame-options",
  ]) {
    assert.ok(headers.has(required), `missing ${required}`);
  }
});

test("Vercel preserves canonical directory redirects and immutable docs assets", () => {
  for (const route of ["/docs", "/blog", "/visualizations"]) {
    const redirect = config.redirects.find((entry) => entry.source === route);
    assert.deepEqual(redirect, {
      source: route,
      destination: `${route}/`,
      permanent: true,
    });
  }

  const docsAssets = config.headers.find(
    (entry) => entry.source === "/docs/_astro/(.*)",
  );
  assert.deepEqual(docsAssets?.headers, [
    {
      key: "Cache-Control",
      value: "public, max-age=31536000, immutable",
    },
  ]);
});
