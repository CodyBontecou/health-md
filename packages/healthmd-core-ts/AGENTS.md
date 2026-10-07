# Portable candidate core

Read [README.md](README.md) for the candidate check pipeline. Before changing contracts, read the root instructions and the applicable frozen inventory/specification; this foundation does not replace current production authority.

Keep portable exports in `src` and inject effects through coarse capability services. Portable source uses ES-only types and explicit Effect imports; host APIs belong in adapters outside this package. Tests supply fake Layers across the same interfaces.

Use the pinned Node/npm from `.node-version` and `package.json`; run component-scoped `npm ci` then `npm run check`. Execute emitted JavaScript, preserving the no-Rust tool graph. Keep the lockfile, generated output and mutable caches component-scoped. New public interfaces, dependency changes and frozen contracts need their own bounded review.
