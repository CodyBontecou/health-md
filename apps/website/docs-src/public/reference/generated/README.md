# Generated export examples

These files are deterministic synthetic outputs produced by Health.md's production serializers and source definitions. They contain no real health information.

Do not edit generated files by hand. Run:

```bash
make generate-export-docs
make check-export-docs
```

Generated groups:

- `core/` — daily JSON/CSV/Markdown/Bases, canonical archives, data dictionary, metric catalog, field inventories, and manifests.
- `individual/` — source-backed and compatibility Individual Entry notes, filenames, and frontmatter fields.
- `rollups/` — weekly roll-up examples and aggregation rules.
- `automation/` — API Endpoint, local control, strict raw, sync, and connected-transfer messages.
- `cli/` — actual CLI requests, responses, diagnostics, and exit behavior.

See the [export reference](../index.md) for semantics and parser guidance.
