# Raw snapshot v1 validation/import test matrix

This file records what the executable tests prove and where the pinned SDK prevents a normal app-created fixture. It is not a restore claim.

## Ordinary Health Connect records

`HealthConnectRawMappingTest.everyCatalogClassUsesARealSdkConstructorThenMapsAndTypedDecodes` invokes the real Kotlin primary constructor for every one of the 42 catalog `Record` classes. No relaxed record mock is used. Each value traverses SDK record -> explicit mapper -> canonical JSON -> exhaustive typed decoder. Required temporal values, nullable offsets, real SDK quantity objects, metadata, enum integers, and the record-specific decoder branch are exercised.

Dedicated real-constructor tests add values that an empty minimal constructor cannot prove:

- heart-rate nanoseconds, nullable offsets, ordered samples, and client metadata;
- sleep stage times/order/raw stage;
- all nine planned completion goals and all eight performance targets, including quantities and durations, in provider order;
- every nullable nutrition member populated through the real constructor (42 nutrient fields);
- marker, instant, interval, scalar, enum, quantity, and sample record shapes through the 42-record constructor matrix.

Route-state decoding validates `data`, `no_data`, and `consent_required` as distinct shapes. Only a data route is insertable by an app constructor. `ConsentRequired` is a read-result state produced by Health Connect authorization and is therefore validated as an independent wire fixture/shape rather than described as insertable.

## PHR and cloud limitations

The alpha PHR API returns provider-created `MedicalResource`, `MedicalResourceId`, `FhirResource`, and `MedicalDataSource` values; it does not provide a stable app insert constructor equivalent to ordinary `Record` constructors. Mapper getter coverage therefore uses strict (non-relaxed) SDK interface/value mocks, while `app/src/test/resources/raw-export/v1/medical-exact-fhir-record.json` is an independent checked-in consumer golden. It proves exact FHIR whitespace/numeric spelling and UTF-8 checksum through the typed medical DTO. PHR output is never called a Health Connect record restore.

Cloud pages are not Health Connect records. `CloudNativeRawSnapshotTest` captures real transport bytes and verifies provider adapter -> canonical record -> typed provider DTO, exact base64-decoded bytes, exact text, charset, byte SHA-256, identity, and credential/header exclusion.

## Stream and corruption coverage

`RawSnapshotValidatorTest` covers both physical formats, exact artifact/sidecar verification, record/issue/type counts, logical and manifest checksums, truncation, absent manifest, content after an NDJSON manifest, unsupported major version, exact integer strings/nanos, enum shape, unknown additive field retention, and an 8,000-record incremental NDJSON callback run. Restart tests leave installation-private spool debris, start a new run, and prove debris/partials are deleted and never promoted.

The decoder separates `RestorableClientMetadata` from `NonRestorableMetadata`. Tests compare the former as potential insert input and retain the latter only as provenance. No test asserts that server-assigned ID, data origin, or last-modified time can be restored.
