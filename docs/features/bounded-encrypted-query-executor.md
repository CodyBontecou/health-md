# Bounded encrypted query execution

`EncryptedHealthContextQueryExecutor` is the macOS production executor for the encrypted context store. It conforms to `HealthMdAgentQueryExecuting` but is intentionally not wired into an app surface by this change.

## Memory and traversal

The encrypted manifest is authenticated once per page and copied as metadata only. Its canonical digest is the immutable dataset revision. Query handlers then load one independently encrypted `HealthMdCompactContextDay` at a time. A page retains only its bounded results, page-local coverage metadata, provenance, and exact limitations. It never creates an all-history day or result array.

Cursors store an absolute manifest index plus an in-day index. Dense days therefore continue at the next metric, workout, packet fact, or evidence value rather than stopping at an internal fixed count. Period comparisons stream one descriptor at a time with scalar aggregation state. Workout deduplication uses bounded rescans instead of an unbounded all-history ID set. There are no total day, history, result, metric, source, or provider caps.

Coverage is page-local while `requested_range` and `available_range` retain query/dataset context. Adjacent missing days with the same status and reason are compressed losslessly. Missing values remain nil and keep their availability status; they are never converted to zero. Pagination accounts for both primary records and missing intervals. Exact metadata is not truncated.

## Page bounds and indivisible values

`max_items` bounds each primary page collection and the missing-interval collection. `max_bytes` bounds the combined canonical bytes of primary records and missing intervals. Related source descriptors and evidence references are retained for page data. If one indivisible item, exact comparison, or evidence value exceeds `max_bytes`, execution throws `singleItemExceedsPageBytes`; it never drops that value. Clients can raise `max_bytes` up to the public v1 maximum.

## Cursors and mutation safety

Cursor plaintext contains the request fingerprint, manifest revision, and traversal position. The fingerprint includes every request field except `page.cursor`, including page bounds and agent detail level. Cursor plaintext is sealed with AES-GCM and fixed domain AAD. Its 256-bit key is derived via HKDF-SHA256 from the Keychain-backed store key with cursor-only salt/info; neither store nor cursor keys are persisted in plaintext.

Tampering fails as `invalidCursor`, using a cursor with another request fails as `cursorDoesNotMatchQuery`, and any committed store mutation changes the manifest revision and fails as `staleCursor`. A query interrupted by concurrent blob replacement fails closed through the store's authenticated snapshot entry checks.

## Source evidence and authorization

Query request v1 now has an optional `sources` selector. Old v1 JSON without it decodes as `all_available`. `source_record_listing` pages complete `HealthMdContextEvidence` values, including canonical Apple records and provider-native payloads. References carry stable `source_id` and optional `provider_id`; legacy context blobs infer these fields when possible.

The projector labels Apple, Health.md summary, diagnostic, and provider-native evidence without changing the daily export schema. Metric links are retained on evidence values. The executor intersects metric, detail, workout, source, provider, evidence-value, and detail-level authorization with `HealthMdEvidenceScope`; source-record values require individual or lossless record detail. Derived packets remain factual and include the medical-neutral limitation.
