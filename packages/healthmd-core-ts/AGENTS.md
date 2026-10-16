# Portable candidate core

Read [README.md](README.md) for the candidate check pipeline. Before changing contracts, read the root instructions and the applicable frozen inventory/specification; this foundation does not replace current production authority.

Keep portable exports in `src` and inject effects through coarse capability services. Portable source uses ES-only types and explicit Effect imports; host APIs belong in adapters outside this package. Tests supply fake Layers across the same interfaces.

Use the pinned Node/npm from `.node-version` and `package.json`. Install dependencies with component-scoped `npm ci` when absent or when the lockfile changes; reuse the matching installation during iteration. Follow [the fast development lanes](../../scripts/typescript-dev/README.md) for Effect-aware static checks and selected or affected behavioral tests. Run component-scoped `npm run check` for stable acceptance, reusing passing evidence only while its relevant inputs remain unchanged. Execute emitted JavaScript, preserving the no-Rust tool graph. Keep the lockfile, generated output and mutable caches component-scoped. New public interfaces, dependency changes and frozen contracts need their own bounded review.
