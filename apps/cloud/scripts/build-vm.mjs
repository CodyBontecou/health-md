import { build } from "esbuild";

for (const [entry, name] of [
  ["vm/server.ts", "server"],
  ["vm/account-server.ts", "account-server"],
  ["vm/ingest-server.ts", "ingest-server"],
  ["vm/bootstrap-cli.ts", "bootstrap"],
  ["vm/bootstrap-generated.ts", "bootstrap-generated"],
  ["mcp/server.ts", "mcp-server"],
  ["mcp/admin.ts", "mcp-admin"],
]) {
  await build({
    entryPoints: [entry],
    outfile: `.wrangler/vm-build/${name}.mjs`,
    bundle: true,
    platform: "node",
    target: "node24",
    format: "esm",
    logLevel: "warning",
  });
}
