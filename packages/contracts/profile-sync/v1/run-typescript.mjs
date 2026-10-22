// Run Node 24 --experimental-transform-types THROUGH an approved heavy-slot guard.
// No npm install/cache copy. Execution/transformation is not a full Cloud tsc/Vitest/Worker build.
import { fileURLToPath } from "node:url";
import * as codec from "../../../../apps/cloud/src/profile-sync-v1-contract.ts";
import { runConformance } from "./conformance.mjs";
const root = fileURLToPath(new URL("../../../../", import.meta.url));
console.log(JSON.stringify(await runConformance(codec, root)));
