# Synthetic qualification evidence v1

These machine-readable files provide **structural traceability** for only the resettable local synthetic Practice runtime. They index normalized AST hashes for exact executable `it`/`test`/`it.each`/`test.each` declarations and their concrete assertion observables; they are not execution attestations, proof of passing commands, TODO completion attestations, or production qualification. No child TODO, epic, or decomposed parent completion is attested while backend, compliance, BAA, external-security, mobile, manual assistive-technology, and pilot gates remain open.

Criterion semantics are strict:

- `partial` means one or more cited exact executable declarations materially assert only the described `observableId`/`observableDescription`; `missingFacets` and a criterion-specific `gap` state what remains. `direct-automated` means browser/UI or final HTTP response observables. `proxy/service-only` means unit, domain, service, handler, or static-analysis proxy evidence; ownership still identifies the criterion owner rather than the test layer.
- `pending` means no qualifying executable evidence is claimed. Its evidence level is `not-evidenced`, evidence is empty, and `missingFacets` plus `gap` identify the explicit criterion-specific blocker.
- No criterion may be `satisfied`. A declaration index never implies that its command ran or passed.
- Mixed accessibility rows cite only the automated observables actually asserted and retain actual 400% browser zoom, manual screen-reader traversal, manual contrast where applicable, and native PDF inspection as explicit manual gaps.

- `security-inventory.json`: exact fixed-route/all-34-operation classification and denial traceability.
- `assertions.json`: shared versioned catalog of unique cited declarations, normalized declaration/assertion AST SHA-256 values, explicit evidence layers, permitted commands, concise excerpts, and source lines.
- `requirements.json`: immutable exact criterion-level Work/Acceptance traceability for the 13 portal children, portal epic, and two decomposed parent TODOs, with criterion-scoped observable IDs referencing the shared assertion catalog, missing facets, status, and criterion-specific gaps.
- `supported-state-matrix.json`: automated browser/context/fixture support and explicit manual/external gaps.
- `production-gate.json`: configured synthetic commands plus every mandatory production approval held pending/false.
- `scanner-fields.synthetic.json`: fictional representative URL/title/network/log/error/audit fields scanned with other artifacts.

`npm run build:provenance` writes ignored `qualification/generated/provenance.json`, containing truthful HEAD/dirty/untracked state, deterministic current-tree source/config/test/qualification hashes, tool versions, lock digest, and nonempty built-asset hashes. Qualification verification writes deterministic ignored `qualification/generated/assertion-audit.json`, mapping every criterion to only its selected catalog assertion excerpts and lines. Migration, rollback, authoritative restore, and purge are marked `not_implemented`; no evidence is fabricated.
