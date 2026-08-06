# Practice pilot document-ingest test fixture

Use [`synthetic-ingest-test-v1.pdf`](synthetic-ingest-test-v1.pdf) to verify each selected pilot
practice portal, EHR attachment path, or document-import workflow without exposing patient data.

## Fixture identity

- **Document ID:** `practice-ingest-test-v1`
- **Media type:** `application/pdf`
- **Byte count:** `1085`
- **SHA-256:** `53b5033914f2a451e094bc6432f5bebbfeb75aca51d914f2a6e2afb87ff5aebc`
- **Generator:** [`generate_synthetic_ingest_pdf.py`](generate_synthetic_ingest_pdf.py)

The PDF contains only a fixed safety label, fixture ID, purpose, and expected result. It contains no
patient identity, health value, health date, practice identity, credential, or production URL.

## Verify before use

From the repository root:

```bash
python3 docs/product/practice/fixtures/generate_synthetic_ingest_pdf.py --check
```

The command validates the expected deterministic bytes, basic PDF structure, committed file, byte
count through exact equality, and SHA-256. The fixture is intentionally generated with the Python
standard library and no network or platform PDF renderer.

## Practice test procedure

For each document path selected for the pilot:

1. Verify the fixture with `--check` and record the exact document ID and SHA-256.
2. Use a fictional/non-production patient or test chart approved by the practice. Do not attach the
   fixture to a real patient's record.
3. Before testing, define the path-specific required transfer actions and acceptance evidence. Then
   perform each applicable action—such as upload, import, download, send, attach, or structured
   write—with the unchanged fixture through the exact proposed path.
4. Confirm that the expected authorized role completes every required locate, open, read, download,
   attach, import, or other use action defined for that path.
5. Confirm that the expected unauthorized role cannot retrieve it.
6. Record the predefined system acceptance receipt or equivalent acceptance evidence without
   including a patient or production object identifier.
7. Complete test-document cleanup according to the practice's approved test-data procedure and
   record the cleanup evidence. If the system retains an immutable test record, use its approved
   archival/test-data disposition rather than falsely claiming deletion.
8. Record the result in
   [`../pilot-practice-discovery-and-approval.md`](../pilot-practice-discovery-and-approval.md).

A path passes only when every predefined required transfer and retrieval/use action succeeded,
unauthorized retrieval was denied, predefined acceptance evidence was recorded, any required
structured import passed, and approved test-document cleanup completed. Any required step not run,
unexpected access, missing acceptance evidence, failed cleanup, or unresolved unknown makes the path
non-passing and blocks or rejects it. Every care context retained in pilot scope needs at least one
mapped, selected path that meets this complete rule; zero selected paths cannot pass.

A practice attestation may supplement this test but cannot replace it. A successful test verifies
only the document path; it does not validate Health.md authentication, tenant authorization, packet
semantics, PHI controls, or production readiness.

## Regeneration policy

Run the generator without `--check` only after intentionally changing the fixture source. Review the
rendered bytes and safety content, update the pinned hash/byte count, and version the document ID and
filename if meaning changes. Never replace this fixture with an exported or redacted patient report.
