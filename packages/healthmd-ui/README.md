# Candidate UI foundation

This independently locked package exposes a React-free readiness model and immutable component-facing props. It is candidate code for U01/U13. Current Swift/Kotlin/Rust products, public exports, native permissions and installed state retain authority. The accepted [native reconciliation](../../docs/migration/effect-refactor/inventories/native.json) defines the platform/channel and future-source limits.

Use Node **24.21.0**, npm **11.19.0**, TypeScript **7.0.2**, esbuild **0.28.2**, `@types/node` **24.19.1**, and overridden `undici-types` **7.24.6**. From this directory run `npm ci --engine-strict --no-audit --no-fund` then `npm run check`. A fresh scoped install also works with a populated cache and `--offline`. No repository workspace or native renderer graph is installed. TypeScript/esbuild use the accepted Go tool binaries; compiled JavaScript runs with Node's built-in test runner, without TypeScript runtime stripping, Rust parsers, Vite/Vitest, or native Node addons.

`npm run check` verifies exact runtime/lock identity, strict ES-only model and separate Node-test types, emits ESM/declarations and a neutral model bundle, recursively discovers sorted `.test.ts` / emitted `.test.js` entries and runs fourteen compiled-JS cases, and checks source/bundle/locked tooling boundaries. `npm run build` produces the same component-props/model checks' inputs; `npm test` consumes that existing build. These checks cover the headless component-facing projection, not rendered React components, screens, accessibility, browsers or native execution. `dist` and `node_modules` are scoped ignored outputs.

## Injected operation and lifecycle

`createReadinessModel` takes one `ReadinessOperation.read(scope)` capability. It has no core/Effect/React import and cannot capture data, write profiles, change grants, persist state, start timers or register native services. Source descriptors retain independent capture/display/query/export statuses supplied by the operation. Initial sources are empty; `ready` means the projection loaded, not that a native source is available. Selecting `health`, `location`, `usage` or `all` filters props without invoking an operation or enabling a domain.

A future adapter invokes the actual common operation through its owning host. It must preserve caller/source/purpose scope and register owned cleanup before suspension through `scope.addFinalizer`. It must cooperate with `scope.isCancelled`, including interrupting the underlying Effect fiber when applicable. Finalizers run once on success, error, cancellation or disposal; asynchronous cleanup is awaited. Pending-close ownership remains visible until acknowledgment, so superseding refresh/cancel/dispose and a third refresh await the same cleanup before acquiring successors. Superseded/late results cannot publish state, repeated disposal waits for the same cleanup, and raw errors become fixed content-free codes. The model does not force a noncooperative external promise to settle. Source results are defensively copied/frozen, limited to64 descriptors with128-character stable IDs and validated status/domain identities.

A component subscribes with `model.subscribe`, reads `model.getSnapshot`, and consumes `projectReadiness`. It calls `refresh` as an authorized read action and releases its subscription plus awaits owner-level `dispose` on teardown. A React host may later adapt this seam through its own subscription hook, after its module identity and lifecycle tests. Tests use synthetic sources and fake operations only; no native availability or grant is claimed. Location/usage/cloud interfaces remain proposed under their separate admission tasks.

## Exact optional candidate peers

Optional peers declare supported candidate tuples without npm auto-installing a renderer graph into this package. Every host chooses **one** tuple, supplies one compatible React identity to its renderer and consumers, and supplies one Effect4.0.1 identity to its core/adapters. Phone and Mac RN versions are separate graphs; they cannot coexist as different renderer/React identities inside one host. Effect is not installed/bundled here. There is no file dependency or linked copy of `@healthmd/core-ts`; adapter injection avoids duplicating its Effect runtime. Installed singleton/module resolution for any host is **unqualified** and must be checked from that host's actual lock, resolver, release bundle and SDK graph.

| Candidate host | Exact tuple | Source compatibility evidence | Qualification |
| --- | --- | --- | --- |
| iOS/Android phone | React19.2.3 + RN0.87.1 + Effect4.0.1 | RN peer React^19.2.3; official Fabric renderer version19.2.3; RN Node^22.13.0 / ^24.3.0 / >=26 | Native RN/Hermes Release/offline/cold/channel graph not installed or executed |
| Browser | React19.2.3 + ReactDOM19.2.3 + RNW0.21.3 + Effect4.0.1 | ReactDOM peer^19.2.3; RNW React/ReactDOM^18 or^19; RNW uses ReactDOM | Browser rendering, accessibility and actual module identity unrun |
| macOS candidate | React19.2.0 + RN0.83.10 + RNmacOS0.83.0 + Effect4.0.1 | RNmacOS exact RN0.83.10 peer; both React^19.2.0; official RN/macOS Fabric renderer version19.2.0 | Separate signed App Store/Developer ID feasibility, helper/sandbox/minimum OS and native module identity unqualified |

Current registry `latest` observations were React19.3.0, RN0.87.1, RNW0.21.3 and RNmacOS0.83.0. React19.3.0 is not selected: broader peer ranges alone do not establish renderer compatibility. RN0.87.1 declares Hermes compiler250829098.0.17; RN0.83.10/RNmacOS0.83.0 declare0.14.1. These are metadata facts, not an admitted Hermes engine/SDK/minimum-OS/bridge pin. No mobile/watch/extension/runtime is enabled here. F-Droid still requires separate native/JS graph exclusions and licensing/reproducibility proof; generic API exports and optional future hosted admission remain distinct.

## Independently inspected primary evidence

Registry hashes below are SHA-256 of raw HTTPS response bytes for the exact version endpoint, inspected2026-10-07. Tarball integrity stays metadata evidence; native tarballs were not installed. Official renderer hashes use raw commit/tag-pinned source bytes. No mutable latest URL is a selected pin.

| Primary metadata source | Raw SHA-256 |
| --- | --- |
| [React19.2.3](https://registry.npmjs.org/react/19.2.3) | `fe2d29ecc007f985e0ae64bdef2e77782befea8f44f417b9350ec86b77e4bbb9` |
| [React19.2.0](https://registry.npmjs.org/react/19.2.0) | `92f5f5ad38cd697c78ff7fafe03e670739b2bebc9f4317705dfdc6161d2d9157` |
| [ReactDOM19.2.3](https://registry.npmjs.org/react-dom/19.2.3) | `6c824706d5fe3a14284ac35ab0676c0cd26f61a9026a2e0a6f2ef1c1febf57d7` |
| [RN0.87.1](https://registry.npmjs.org/react-native/0.87.1) | `3c2153f7c8f56a7377cf9c4fbd55b3c9fe4675d84950f2c43bb1274a69279818` |
| [RN0.83.10](https://registry.npmjs.org/react-native/0.83.10) | `ea8c82da6412265cc6ced637bd2e3667c6d67e4995ca72a3c7b433a312b66dad` |
| [RNW0.21.3](https://registry.npmjs.org/react-native-web/0.21.3) | `9667f8edc4f963c41465b9df381effd2a450b006eb03e6ab43c6646391fd40b3` |
| [RNmacOS0.83.0](https://registry.npmjs.org/react-native-macos/0.83.0) | `24d75841a7507321d6b4ed78231534aab97056f1c3d7ecc35e1b8f35e10c0ca3` |
| [Phone Fabric source](https://raw.githubusercontent.com/facebook/react-native/v0.87.1/packages/react-native/Libraries/Renderer/implementations/ReactFabric-dev.js) | `873ef19f4dfbb385f43ad6ec510e2ab00168289f72becba703111652008ddf94` |
| [RN0.83.10 Fabric source](https://raw.githubusercontent.com/facebook/react-native/v0.83.10/packages/react-native/Libraries/Renderer/implementations/ReactFabric-dev.js) | `6fce932c458ee63cc016d3092d1402b6b412bcb151b3cc4e4835a3b4e082be81` |
| [Mac Fabric source at published gitHead](https://raw.githubusercontent.com/microsoft/react-native-macos/19f618c032c9f07967281ed5c462dc3259e8e7e1/packages/react-native/Libraries/Renderer/implementations/ReactFabric-dev.js) | `6fce932c458ee63cc016d3092d1402b6b412bcb151b3cc4e4835a3b4e082be81` |

[React's duplicate-module guidance](https://react.dev/warnings/invalid-hook-call-warning) requires renderer and component React imports to resolve to the same object. [RNW's primary documentation](https://necolas.github.io/react-native-web/docs/) establishes its ReactDOM boundary. These support the host identity obligations, not execution claims. The native host packet must independently inspect actual renderer/engine source, dependency graph, licensing, F-Droid exclusions, packaged offline start/expiry/cancel/backpressure/teardown and signed permissions.

## Remaining consumers and proof

Future React/RN/Web/Mac presentation consumers and common-operation adapters use this seam only through bounded reviewed tasks. Native SDK/capture, background/intent/Worker/widget/watch/report/store/provider adapters retain authority; watch independence and deferred Wear remain unchanged. Portable core/CLI/MCP, frozen public contracts, website/Obsidian and Practice/Wake boundaries are unaffected by this package's synthetic checks. Parent U01/U13/F03/F06, native accessibility, physical/signed/store/runtime and retirement gates remain open. Reverting this candidate package/receipt restores the prior source graph without changing launchers or installed data.
