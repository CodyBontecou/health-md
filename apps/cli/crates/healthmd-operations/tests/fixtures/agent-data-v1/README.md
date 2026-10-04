# Packaged synthetic agent-data fixtures

`grant-explicit.json` and `query-records.json` are byte-identical copies from `packages/contracts/agent-data/v1/fixtures/`. Published crate tests need these files without a monorepo checkout.

Repository tests check byte parity with the reviewed contract fixtures. The packaged-crate smoke checks archive inclusion and executes the runtime decoding tests. Do not edit these mirrors independently of the contract sources. This repair changes no schema, protocol, registry authority, or fixture content.
