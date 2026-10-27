# Agent Data gateway export

Send each exported artifact file — byte-for-byte the same file the folder destination
would write — to a self-hosted Agent Data ingestion gateway. The gateway is the reference
`healthmd data ingest-serve` listener or any server implementing the same
`healthmd.agent_data_ingest` v1 protocol. Health.md never re-encodes, wraps, or compresses
the artifact; the phone uploads exactly the folder-destination bytes.

The cross-platform contract is
[`packages/contracts/agent-data/v1/contract.md`](../../../../packages/contracts/agent-data/v1/contract.md)
(the ingestion sections), and the CLI reference gateway is documented in
[`apps/cli/docs/agent-data.md`](../../../../apps/cli/docs/agent-data.md).

## Configure

1. Open **Export** (or **Schedule**, or edit an export profile).
2. Under **Export Target**, select **Agent Data gateway**.
3. Enter the gateway's base `http://` or `https://` URL — for example
   `http://127.0.0.1:8791` for the loopback reference listener. Health.md appends
   `/v1/ingest` to the base URL. Keep API keys and other secrets out of the URL: query
   parameters are accepted for routing but are stripped from every displayed label and
   never appear in history or logs.

The URL is stored in private app preferences and on the export profile binding, mirroring
the API endpoint destination. There are no credentials: v1 ingestion is unauthenticated at
the phone-to-gateway boundary, and hosted gateways with accounts are a later contract
cycle. Fragments and embedded username/password values are rejected, exactly like the API
endpoint discipline.

Compatibility exports upload the per-day daily health-data JSON artifact; select **JSON**
in Formats (the gateway reports a health-free "JSON format required" failure otherwise).
Raw snapshot mode uploads the complete raw snapshot artifact as produced for the folder
destination.

## Upload protocol

One artifact per request:

```http
POST /v1/ingest HTTP/1.1
Content-Type: application/x-healthmd-agent-data-ingest
Content-Length: <exact>
```

The body is one `\n`-terminated JSON manifest line (`healthmd.agent_data_ingest` v1:
artifact kind, platform `android`, the artifact's own schema identity and version, owner
date, physical format, media type, byte count, SHA-256 of the exact uploaded bytes, and
completeness) followed immediately by exactly `byte_count` artifact bytes. The phone never
declares the optional informational `record_count`, never sends partial (unfinalized)
artifacts, and never uploads a raw artifact that is not complete.

Every answered upload is HTTP 2xx with a `healthmd.agent_ingest_response` v1 receipt.
Receipts and all errors are health-free: they carry only the outcome, a stable rejection
code when applicable, and no health values, account identity, or paths.

## Outcomes and retries

Each artifact's outcome is surfaced per artifact in the export result — **Uploaded**,
**Rejected** with the gateway's stable code (`truncated`, `checksum_invalid`,
`manifest_incomplete`, or `transient`), or **Upload failed** for transport failures.

Retry posture is fixed by the contract: transport failures and `transient` receipts are
retried a bounded number of times with backoff; the three fix-and-reupload codes
(`truncated`, `checksum_invalid`, `manifest_incomplete`) are never auto-retried and must be
surfaced to the user. A failed upload never blocks the remaining artifacts, and never
discards or corrupts the artifact outcome accounting. Re-uploading identical bytes is
idempotent at the gateway (byte-identical receipt).

## Schedules and automation

Gateway-targeted export profiles work everywhere the API endpoint destination works:
manual export, export-history retry, automation shortcuts referencing a profile, single
schedules, and per-profile scheduled runs. Scheduled gateway runs require a network
connection and validate the configured gateway URL (a one-way fingerprint in the frozen
settings snapshot) before capturing any health data; a changed URL fails closed rather
than uploading to a different destination.

Shared Setup v2 bundles never carry an Agent Data gateway destination: exporting a
gateway-targeted profile into a setup bundle fails closed, and importing a bundle can never
produce a gateway target. Rebind the destination on the receiving device instead.
