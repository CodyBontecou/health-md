---
title: "Local agents and health context"
description: "Connect local agents to Health.md through scoped CLI commands or direct-iPhone MCP, and preserve evidence, coverage, and missingness."
---

Health.md gives local coding and automation agents two ways to work with Apple Health data:

- the `healthmd` CLI for explicit terminal commands and canonical extraction;
- `healthmd mcp serve` and its MCP App for typed tools, native visualizations, and approved generated-file exports.

The portable MCP server communicates directly with the foreground iPhone and does not require Health.md for Mac. The CLI can use the same direct channel for raw/canonical exports, or the Mac app's loopback API for Mac-index workflows. HealthKit reads always happen on iPhone, and `healthmd.health_data` v8 remains the public source contract.

```text
local agent -> healthmd mcp serve -> authenticated encrypted port 17647 -> foreground iPhone
local agent -> healthmd CLI -> direct iPhone or optional Mac loopback workflow
```

## What an agent can do

- check direct pairing and foreground iPhone readiness without reading health values;
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
- render metric, sleep, workout, comparison, coverage, and evidence views inside MCP Apps;
- run approved generated-file exports into an explicit existing desktop destination;
- inspect, resume, or cancel durable export jobs.

Health.md does not diagnose, recommend treatment, infer causation, or label a result as healthy, harmful, better, or worse.

## Set up the local helpers

<div class="availability preview">
<strong>Public preview · portable direct setup</strong>
<p>The cross-platform package is published as an explicitly unqualified preview. Use the exact matching mobile build named by release evidence; the signed Mac helper remains available through <a href="/docs/configuration/">Configure your agent</a>.</p>
</div>

1. On macOS or Linux, run `brew install CodyBontecou/tap/healthmd`, then verify `healthmd --version`.
2. Run `healthmd setup codex`; it configures Codex and opens pairing when an iPhone is not yet trusted.
3. Finish pairing under Direct CLI Access in Health.md on iPhone and keep the app foreground.
4. For Claude or manual host setup, configure the absolute `healthmd` path with arguments `mcp serve` using [Health.md MCP server and App](/docs/mcp/).
5. Restart the host when setup reports a changed configuration, then call `healthmd_doctor`.

The Health.md Mac app remains an optional installation and skill-distribution path for Mac users, not a portable MCP dependency.

Install the same consumer-facing skill from [skills.sh](https://skills.sh/CodyBontecou/health-md/healthmd-cli):

```bash
npx skills add CodyBontecou/health-md@healthmd-cli
```

This selects only `healthmd-cli`; the repository also contains contributor-focused development and QA skills. Installing the skill does not install the CLI, pair a phone, grant health-data access, or keep the skill updated automatically. Review it before use and run `npx skills update healthmd-cli` when you choose to adopt a later version.

The Mac app's skill installer creates `healthmd-cli/SKILL.md` in the directory you approve. It replaces only Health.md's own skill folder. The skill teaches bounded commands, structured result handling, privacy rules, model-provider disclosure boundaries, and safe recovery after unknown outcomes.

Use the setup prompt in the Mac app if you want an agent to create the symlinks. Health.md itself does not modify shell startup files or `/usr/local/bin` silently.

## Readiness first

For portable MCP clients, call `healthmd_doctor`. It checks local direct trust and the connected foreground iPhone without reading health values, and returns actionable health-free errors. Each typed MCP query is then an explicit fresh request to that iPhone: it captures only the requested scope, evaluates the typed query on-device, and returns bounded pages.

Mac-loopback CLI users can still run `healthmd doctor` for `healthmd.cli_doctor` v1 readiness, encrypted-context coverage, and next actions.

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

## Authorization boundaries

Portable MCP uses the paired direct protocol: native credential storage, mutual transcript authentication, encrypted packets, replay protection, and a foreground iPhone connection to the computer's explicit address. The optional Mac query API instead listens on IPv4 and IPv6 loopback only and validates the peer as loopback.

For the optional Mac loopback mode, any local process that can reach port `17645` while Health.md is open can issue the same query requests. Treat local machine access as query authority:

- do not bind or proxy the port to a LAN interface;
- do not tunnel it to another machine;
- do not place an HTTP reverse proxy in front of it;
- do not configure MCP with a non-loopback URL;
- review which local agents can execute the helper.

Former profile and activity routes return `410 removed_endpoint` for compatibility.

## Canonical data and derived views

Use `healthmd extract` when the agent needs source-shaped data or a large validated raw/canonical body:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Use query commands or MCP tools for derived views and in-host visualizations:

```bash
healthmd query --metric resting_heart_rate --last 30 --all-pages
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd training align --last 14 --workout running --sleep-window first:4h
```

The distinction is deliberate:

| Surface | Contract role |
|---|---|
| `healthmd.health_data` v8 | Public daily source document |
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
  <a href="/docs/mcp/"><span>Tool protocol</span>Codex and Claude setup, 21 released Mac tools, 19 portable preview tools, MCP App charts, exports, paging, and sandbox boundaries.</a>
  <a href="/docs/agent-api/"><span>Low level</span>Loopback query API: routes, direct request JSON, cursors, and durable acquisition jobs.</a>
  <a href="/docs/cli-extract/"><span>Source objects</span>Canonical extraction: selected schema-v8 documents, records, projections, and receipts.</a>
  <a href="/docs/reference/evidence-packets/"><span>Contracts</span>Compact queries and evidence packets: typed values, coverage, operations, and deterministic IDs.</a>
</div>
