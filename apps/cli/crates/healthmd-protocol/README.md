# healthmd-protocol

Wire models, canonical encoding, cryptography, request fingerprints, and bounded transfer frames for
the Health.md direct-iPhone protocol.

This crate is an interoperability component of the standalone
[Health.md CLI](https://github.com/CodyBontecou/healthmd-cli). It does not read HealthKit, perform
networking, or log health data. Protocol v1 mirrors the deployed Swift implementation and is
covered by byte-for-byte Swift-generated fixtures.

Licensed AGPL-3.0-only.
