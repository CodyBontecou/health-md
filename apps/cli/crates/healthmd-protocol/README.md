# healthmd-protocol

Wire models, canonical encoding, cryptography, request fingerprints, and bounded transfer frames for
the Health.md direct mobile-source protocols.

This crate is an interoperability component of the standalone
[Health.md CLI](https://github.com/CodyBontecou/health-md/tree/main/apps/cli). It does not read HealthKit, perform
networking, or log health data. Application protocol v1 mirrors the deployed Swift implementation;
application protocol v2 supports Android with shared Rust/Kotlin interoperability fixtures.

Licensed AGPL-3.0-only.
