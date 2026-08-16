import { build } from "esbuild";
import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dist = resolve(root, "dist");

await rm(dist, { recursive: true, force: true });
await mkdir(resolve(dist, "assets"), { recursive: true });
await build({
  entryPoints: [resolve(root, "src/web/main.tsx")],
  outfile: resolve(dist, "assets/app.js"),
  bundle: true,
  format: "esm",
  platform: "browser",
  target: ["chrome120", "firefox121", "safari17.2", "edge120"],
  jsx: "automatic",
  minify: true,
  sourcemap: false,
  legalComments: "none",
  logLevel: "info",
});
await cp(resolve(root, "static/index.html"), resolve(dist, "index.html"));
await cp(resolve(root, "static/styles.css"), resolve(dist, "styles.css"));

const index = await readFile(resolve(dist, "index.html"), "utf8");
if (/<script(?![^>]*\bsrc=)/i.test(index) || /\son\w+\s*=/i.test(index)) {
  throw new Error("Built HTML contains an inline executable path");
}
await writeFile(
  resolve(dist, "asset-manifest.json"),
  `${JSON.stringify({ mode: "synthetic", entries: ["/assets/app.js", "/styles.css"] }, null, 2)}\n`,
);
