---
title: "Local agents and health context"
description: "Connect local agents to Health.md through scoped CLI commands or MCP, acquire only requested Apple Health data, query an encrypted Mac index, and preserve evidence and missingness."
---

Health.md gives local coding and automation agents two ways to work with Apple Health data:

- the `healthmd` CLI for explicit terminal commands and canonical extraction;
- the `healthmd-mcp` stdio helper for typed local tools.

Both use the running Health.md Mac app for query and evidence work. HealthKit reads still happen on an open iPhone. Health.md stores a disposable encrypted query index on Mac and keeps `healthmd.health_data` v7 as the public source contract.

```text
local agent
  -> healthmd CLI or healthmd-mcp stdio
  -> http://127.0.0.1:17645/v1/agent/*
  -> Health.md Mac app and encrypted context
  -> open connected iPhone for fresh HealthKit acquisition
```

## What an agent can do

- check Mac, encrypted context, and iPhone readiness without reading health values;
- list canonical metric IDs and categories;
- acquire an exact metric, source, date, and detail scope from iPhone;
- extract canonical daily documents or source records;
- query typed metric series with evidence and coverage;
- build stable sleep sessions and fixed sleep windows;
- align workouts with preceding and following sleep;
- list workouts and inspect coverage;
- compare exact periods with explicit aggregation;
- create factual training evidence packets;
- page through an unbounded logical corpus using bounded requests;
- resume or cancel durable acquisition jobs.

Health.md does not diagnose, recommend treatment, infer causation, or label a result as healthy, harmful, better, or worse.

## Set up the local helpers

1. Install and open Health.md on Mac.
2. Open the **CLI** tab.
3. Install or symlink `healthmd` and `healthmd-mcp` from the paths shown there.
4. Optional: select **Install Agent Skill** and choose the skills directory used by your agent.
5. Open Health.md on iPhone and connect it to the Mac app.
6. Run `healthmd doctor`.

The app's skill installer creates `healthmd-cli/SKILL.md` in the directory you approve. It replaces only Health.md's own skill folder. The skill teaches bounded commands, structured result handling, privacy rules, and safe recovery after unknown outcomes.

Use the setup prompt in the Mac app if you want an agent to create the symlinks. Health.md itself does not modify shell startup files or `/usr/local/bin` silently.

## Readiness first

```bash
healthmd doctor
```

The response uses `healthmd.cli_doctor` v1 and can report:

- Mac app loopback reachability;
- connected iPhone state and fresh-acquisition capability;
- encrypted owner-date count and range;
- whether cached query context is available;
- concrete next actions;
- safe errors without health values.

For MCP clients, call `healthmd_doctor` first. Typed MCP query tools read encrypted Mac context and do not refresh iPhone implicitly. Call `healthmd_refresh` before them when current data is required. High-level CLI query commands combine fresh acquisition and query by default.

## Every request carries its own scope

Health.md does not use saved access profiles, caller registrations, grant records, or CLI credentials. Each request supplies the complete data scope it needs:

- metric IDs or categories;
- Apple Health and optional provider source selectors;
- exact dates or all available dates;
- summary or lossless detail;
- query operation;
- bounded page controls.

Fresh acquisition validates the scope against the current catalogs, persists it with the durable job, and applies it on iPhone without changing saved export preferences.

A request with no explicit acquisition selection is rejected rather than inheriting the user's normal export settings.

## Loopback is the authorization boundary

The Mac query API listens on IPv4 and IPv6 loopback only and validates the peer as loopback. There is no bearer token.

Any local process that can reach port `17645` while Health.md is open can issue the same query requests. Treat local machine access as query authority:

- do not bind or proxy the port to a LAN interface;
- do not tunnel it to another machine;
- do not place an HTTP reverse proxy in front of it;
- do not configure MCP with a non-loopback URL;
- review which local agents can execute the helper.

Former profile and activity routes return `410 removed_endpoint` for compatibility.

## Canonical data and derived views

Use `healthmd extract` when the agent needs source-shaped data:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Use query commands or MCP tools for derived views:

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

The distinction is deliberate:

| Surface | Contract role |
|---|---|
| `healthmd.health_data` v7 | Public daily source document |
| `healthmd.healthkit_records` v1 | Canonical source-record archive inside lossless daily documents |
| `healthmd.extract_receipt` | Extraction scope and completion metadata |
| `healthmd.query_context_day` v1 | Disposable encrypted index record |
| `healthmd.query_response` v1 | Typed paged derived result |
| `healthmd.evidence_packet` v1 | Factual packet linked to source evidence |
| Job and traversal receipts | Transport, durability, and completion metadata |

A projection or typed result never masquerades as a complete daily source document.

## Fresh acquisition

High-level queries acquire fresh data by default:

```bash
healthmd query --category Sleep --last 14
```

Health.md creates a dedicated encrypted-context request. It does not write export files or consume file-export quota. The iPhone reads the explicit scope, builds deterministic compact owner days, and sends bounded resumable partitions. The Mac commits each encrypted day before acknowledging it.

Fresh completion checks every requested metric, source or provider, and owner day against blobs replaced after that refresh began. Older cached values and data from another provider cannot hide a failed acquisition.

Provider-only requests can skip HealthKit. Provider history traversal follows provider-native cursors instead of imposing a fixed total-result limit.

## Encrypted Mac context

The Mac stores one independently encrypted generation per owner day. A random 256-bit key lives in Keychain as a this-device-only, when-unlocked item.

- day blobs and the manifest use AES-256-GCM;
- filenames are random UUIDs, not dates or metric names;
- owner dates and index entries are encrypted;
- files have owner-only permissions and backup exclusion;
- commits write a new immutable generation before replacing the encrypted manifest;
- reads fail closed on missing keys, failed authentication, malformed dates, or manifest mismatch.

The store has no configured total metric, day, history, or result cap. Commands stay bounded because they decrypt one day at a time and page results.

The index is disposable. Canonical exports remain the source of truth.

## Retention and deletion

Health.md does not delete query context on an implicit retention schedule. On Mac, Settings shows the stored owner-day count and date range.

Use:

- **Delete Older Context** to remove owner dates strictly before a selected boundary;
- **Delete All Encrypted Context** to remove every encrypted generation and the dedicated Keychain key.

Full deletion remains available even if the key or ciphertext is damaged. Removing the key provides crypto-erasure for any undeleted ciphertext remnants.

Deleting query context does not delete export files, connected-provider credentials, or Apple Health data.

## Typed values and missingness

Query values are tagged. A result can carry a quantity and canonical unit, duration, signed count, string, category, Boolean, UTC timestamp, calendar date, nested array, or an unknown future typed payload.

Missing data stays explicit:

- `complete_empty` means the represented scope had no matching observations;
- `partial` means only part of the requested scope completed;
- `failed`, `unsupported`, `skipped`, and `cancelled` retain their meanings;
- `not_requested`, `legacy_unavailable`, `redacted`, and `not_synchronized` remain distinct.

Health.md never converts an absent value to numeric zero. A real zero is encoded as an available typed value.

## Evidence and neutral language

Results link facts to source evidence such as:

- daily summary keys;
- canonical HealthKit UUIDs;
- external identities;
- query-manifest outcomes;
- integrity warnings;
- partial failures.

Evidence resolution checks the evidence ID, locator, source schema, source version, and source digest together.

Period comparison direction is limited to `increased`, `decreased`, `unchanged`, or `not_comparable`. Training alignment reports timestamps and gaps, not causal effects. Evidence packets report stored observations and coverage, not medical conclusions.

An agent should preserve those limits in its own answer. It should say when data is missing, avoid turning correlation into cause, and direct medical questions to a qualified clinician.

## Bounded pages, complete logical access

Query pages use `max_items`, `max_bytes`, and an opaque `next_cursor`. There is no contract-level cap on total stored days, workouts, metrics, or result items.

A cursor is integrity protected and bound to the semantic query and encrypted corpus revision. Health.md rejects:

- a modified cursor;
- a cursor used with another query;
- a cursor issued before the corpus changed;
- a repeated cursor during automatic traversal.

Use `--all-pages` or MCP `all_pages: true` for bounded automatic traversal. Narrow the scope or page manually if one invocation reaches its aggregate safety ceiling.

## Agent reporting checklist

When summarizing a result, report:

- command or tool used;
- exact requested dates, metrics, source, and detail;
- fresh, cached, or reused-coverage mode;
- requested-scope status and corpus status separately;
- page or traversal completion;
- units and source evidence for any stated value;
- missing intervals, limitations, and unrelated skips;
- job ID when work is paused or resumable.

Do not include raw records, routes, clinical text, medication details, mood entries, or attachments unless the user explicitly requests those values and understands the disclosure.

## Choose an integration

<div class="related">
  <a href="/docs/agent-queries/"><span>CLI cookbook</span>Typed agent queries: metrics, sleep sessions, training alignment, workouts, coverage, comparison, and evidence.</a>
  <a href="/docs/mcp/"><span>Tool protocol</span>Local MCP helper: client configuration, 16 tools, paging, and its sandbox boundary.</a>
  <a href="/docs/agent-api/"><span>Low level</span>Loopback query API: routes, direct request JSON, cursors, and durable acquisition jobs.</a>
  <a href="/docs/cli-extract/"><span>Source objects</span>Canonical extraction: selected schema-v7 documents, records, projections, and receipts.</a>
  <a href="/docs/reference/evidence-packets/"><span>Contracts</span>Compact queries and evidence packets: typed values, coverage, operations, and deterministic IDs.</a>
</div>
