---
title: "Health.md CLI"
description: "Choose the Mac app or direct iPhone backend, install healthmd, inspect readiness, export files, extract canonical Apple Health data, run typed queries, and automate durable jobs."
---

The `healthmd` command has two operating modes. Use the Mac app backend when you want encrypted local queries, MCP tools, or the destination folder already selected in Health.md for Mac. Use the direct iPhone backend when you want raw data or generated files without running the Mac app.

<div class="callout">
<strong>HealthKit stays on iPhone.</strong>
<p style="margin-top:6px;">Neither CLI backend reads Apple Health from the computer. A current, open Health.md iPhone app performs each fresh HealthKit read. The CLI receives validated results or files.</p>
</div>

## Pick a backend

| Capability | Mac app backend | Direct iPhone backend |
|---|---|---|
| Default in the bundled Mac helper | Yes | No, select with `--backend direct` |
| Needs Health.md for Mac open | Yes | No |
| Needs Health.md on iPhone open for new data | Yes | Yes |
| File destination | Folder selected in the Mac app | Existing absolute `--destination` |
| Strict raw export | Yes | Yes |
| Canonical `healthmd extract` | Yes | Yes |
| Encrypted context, typed queries, and evidence | Yes | No |
| `healthmd-mcp` | Yes | No |
| Manual IP or Tailscale | Mac sync or explicit direct mode | Yes |
| Nearby direct transport | Bundled Swift helper only | Not in the portable Rust client |

Backend and transport choices never fall back silently. A direct command cannot switch to the Mac app to satisfy a query, and a failed Nearby connection cannot switch to Manual IP.

## Install the bundled Mac helpers

Health.md for Mac includes signed `healthmd` and `healthmd-mcp` helpers. Open the Mac app and select **CLI** to see the paths for your installed copy, setup commands, agent prompts, and the optional agent skill installer.

The normal app bundle paths are:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Use aliases for one shell session:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
alias healthmd-mcp="/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
```

Or create persistent symlinks in a user-owned bin directory:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" ~/.local/bin/healthmd-mcp
```

Add `~/.local/bin` to `PATH` if your shell does not already include it:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verify the CLI without starting the MCP stdio loop:

```bash
healthmd --help
healthmd doctor
```

`healthmd doctor` returns `healthmd.cli_doctor` JSON with Mac, encrypted context, and iPhone readiness. It does not print health values.

## Portable CLI status

A standalone Rust CLI is in `0.1.0-alpha.1` development. It runs on macOS, Linux, and Windows, uses direct Manual IP or Tailscale connections by default, and does not need the Mac app. Protocol compatibility and cross-language fixtures are implemented, but physical iPhone release QA and public packaging still need to finish before the first public release.

Until that release exists, use the bundled Mac helper. Do not rely on unpublished Homebrew, crates.io, GitHub installer, or download URLs.

The portable client will support raw export, canonical extraction, pairing, status, resume, and cancel on all three platforms. Generated-file destinations work on macOS and Linux. Protocol v1 rejects file destinations on Windows because it carries Unix absolute paths.

## Command map

| Command | Purpose | Backend |
|---|---|---|
| `healthmd status` | Inspect live readiness or one local durable job | Both |
| `healthmd doctor` | Explain Mac, encrypted context, and iPhone readiness | Mac app |
| `healthmd metrics list` | Return the canonical queryable metric catalog | Mac app |
| `healthmd extract` | Acquire selected canonical `healthmd.health_data` objects | Both |
| `healthmd query` | Acquire and query selected typed metrics | Mac app |
| `healthmd sleep sessions` | Return first-class sleep sessions and fixed windows | Mac app |
| `healthmd training align` | Align workouts with preceding and following sleep | Mac app |
| `healthmd workouts` | List typed workouts with evidence | Mac app |
| `healthmd coverage` | Inspect date and metric coverage or missingness | Mac app |
| `healthmd compare` | Compare exact periods with caller-selected aggregation | Mac app |
| `healthmd evidence training` | Build a factual training evidence packet | Mac app |
| `healthmd export` | Write generated files or return strict raw JSON | Both |
| `healthmd resume` | Resume an immutable durable export job | Both |
| `healthmd cancel` | Request explicit cancellation | Both |
| `healthmd agent ...` | Call the low-level loopback query and job API | Mac app |
| `healthmd direct ...` | Pair, list, and remove direct iPhone trust | Direct |

## First Mac app workflow

1. Open Health.md on Mac and select a destination folder if you plan to write files.
2. Open Health.md on the paired iPhone and wait for Mac connectivity.
3. Check readiness.
4. Run a small command before requesting a large history.

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --metric sleep_total --yesterday
```

Fresh queries acquire only the supplied metrics, sources, dates, and summary or lossless detail. They do not change saved iPhone export settings.

## File and raw exports

```bash
# Use the Mac app's selected destination
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all

# Return strict lossless canonical JSON without writing export files
healthmd export --iphone --yesterday --raw --output yesterday.json
healthmd export --iphone --all --raw --output complete-health-corpus.json

# Replace saved metric scope for this one file job
healthmd export --iphone --last 7 --category Sleep --detail summary

# Mirror saved iPhone settings, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings
```

There is no current calendar-day cap. `--all` asks the iPhone to discover the earliest available selected source record, pins the resolved range, and processes it through bounded partitions. Available storage and one unusually dense day remain practical limits.

`--raw` temporarily requests canonical lossless source records without changing the iPhone preference. It writes no generated files and does not include connected-provider sidecars.

## Canonical extraction or derived query?

Use `extract` when you need source-shaped data:

```bash
healthmd extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

Use a query command when you need a typed, evidence-linked view:

```bash
healthmd sleep sessions --last-nights 14 --window first:4h
healthmd compare --metric steps:sum \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

`healthmd.health_data` v7 is the public source contract. Query, evidence, job, and receipt schemas describe transport or derived views. They do not replace the source schema.

## Machine-readable behavior

Commands use versioned JSON on stdout or at the explicit `--output` path by default. Canonical extraction can opt into JSONL, and high-level queries can opt into a deliberately lossy table. Health-free progress may use stderr. `--help` is plain text. Argument failures before a command starts are plain text on stderr with exit code 2.

A successful process exit is not enough to prove complete health data. Check:

- the outer status;
- requested-scope status;
- per-day and per-query outcomes;
- missing intervals;
- `next_cursor` or traversal receipt;
- source schema and version;
- limitations and warnings.

A complete-empty result means Health.md represented the requested scope and found no observations. It is not the same as zero, missing, failed, skipped, or unsupported.

## Safe automation

Use your automation host's process timeout and keep stdin closed for commands that should not prompt. On systems with GNU `timeout`:

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd doctor </dev/null
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null
```

Timeout, Ctrl-C, process exit, network loss, and exhausted iOS background time do not cancel a durable job. Inspect the job ID and resume it instead of starting a duplicate.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
healthmd cancel JOB_UUID
```

Only an iPhone acknowledgement makes cancellation terminal.

## Privacy rules

Raw and lossless output can contain exact timestamps, routes, clinical records, medications, mood entries, ECG values, provenance, and attachments. Prefer an output file over terminal output. Do not paste payloads into issue reports, agent transcripts, CI logs, or shell traces.

The local query API has no bearer token, registration, access profile, or grant database. Loopback reachability is its complete access boundary. Any local process can use it while the Mac app is open, so never proxy or expose port `17645` to another machine.

## Next guides

<div class="related">
  <a href="/docs/cli-direct/"><span>No Mac app</span>Direct iPhone CLI: pairing, transports, raw and file exports, background behavior, and platform support.</a>
  <a href="/docs/cli-extract/"><span>Source data</span>Canonical extraction: select metrics, objects, detail, JSON Pointers, JSONL, and receipts.</a>
  <a href="/docs/cli-jobs/"><span>Automation</span>Durable jobs: timeouts, resume, cancellation, partial results, and safe scripting.</a>
  <a href="/docs/agents/"><span>Agents</span>Local agent workflows: encrypted context, direct scope, typed commands, and evidence.</a>
  <a href="/docs/mcp/"><span>MCP</span>Configure the sandboxed stdio helper and review its tool boundary.</a>
  <a href="/docs/reference/api-and-cli/"><span>Contract</span>API and CLI reference: exact routes, schemas, responses, and generated fixtures.</a>
</div>
