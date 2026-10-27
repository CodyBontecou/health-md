---
title: "Apple Health CLI: export from iPhone to macOS, Linux or Windows"
description: "Use the standalone Health.md CLI preview to pair a phone, verify readiness, export one day and resume a durable job. Apple Health typed queries require iPhone."
lead: "Export one day from an open, paired phone and check the saved result. The standalone healthmd CLI runs on macOS, Linux and Windows; its direct-phone workflow remains an unqualified preview."
date: "2026-08-06T09:00:00.000Z"
updated: "2026-10-26"
verified: "2026-10-26"
verified_by: "Codex (agent)"
verified_method: traced
category: "Workflow guide"
related:
  - query-apple-health-with-claude-or-codex
  - resumable-multi-day-health-exports
  - local-first-health-data-architecture
draft: false
tags:
  - healthmd
  - cli
  - mcp
  - agents
---

Health.md started with a simple boundary: read health data on the phone, then put the result in files the user controls. The standalone **`healthmd` CLI** extends that boundary to macOS, Linux, and Windows without routing through the Health.md Mac app or a Health.md cloud service.

The paired app performs each Apple Health or Health Connect read. The CLI receives authenticated, encrypted, validated results over Manual IP or Tailscale.

## Choose the standalone preview

This guide uses the separate portable CLI, not the signed helper inside Health.md for Mac. If you already use the Mac app, follow the [bundled Mac agent setup](/docs/guides/connect-agent/). If you only need a spreadsheet or a file upload, start with [Apple Health to CSV](/apple-health-to-csv/). The [AI workflow comparison](/health-data-for-ai/) explains the three paths.

The standalone CLI is an **unqualified public preview**. Availability checked October 26, 2026: [alpha.6](https://github.com/CodyBontecou/health-md/releases/tag/healthmd-cli/v0.1.0-alpha.6) is published with installers, desktop archives and checksum/signature assets. Alpha.7 remains a draft with no assets and is not an install target. Read [release status and compatibility](/docs/release-status/) and use a matching mobile build; package publication or a successful connection does not qualify a CLI/mobile pair for stable use.

Install on macOS or Linux using the [CLI installation instructions](/docs/cli/), then inspect the installed version and commands:

```bash
brew install CodyBontecou/tap/healthmd
healthmd --version
healthmd --help
```

Windows uses the exact version's archive or PowerShell installer. Verify release checksums and signatures before execution. Do not use the repository-wide latest-release pointer, which is reserved for Apple app releases. The published preview and development source can expose different operations; check your installed build instead of assuming every tool in current source is available.

## Pair once

```bash
healthmd direct pair
```

The current universal flow displays a QR code and a high-entropy pairing code. Open **Health.md → Direct CLI Access** on iPhone or Android, scan or enter the handoff, verify the computer, and keep the app open while new work begins. Reconnect trust is stored in the operating system credential service.

Start with one completed day. These examples use a macOS/Linux shell; on Windows, use an existing absolute writable destination and the syntax of your shell:

```bash
healthmd status
healthmd export --yesterday --raw --output yesterday.json
mkdir -p "$HOME/Documents/HealthVault"
healthmd export --yesterday --destination "$HOME/Documents/HealthVault"
```

For the raw command, inspect the saved JSON's dates, coverage, warnings and partial outcomes. For generated files, inspect the command result and actual destination. A successful process exit or a created file is not proof that every requested measurement exists. See the [export format reference](/docs/reference/export-formats/) before interpreting values.

An iPhone source also supports canonical extraction and typed queries. Inspect the installed operation's schema before running an explicit seven-day request. Replace the example dates with dates you want to inspect:

```bash
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd query healthmd_sleep_sessions
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-10-12","end_date":"2026-10-18"}},"all_pages":true}'
```

Android supports direct raw and generated-file exports, but typed queries and canonical extraction here require iPhone. Android keeps provider-native Health Connect snapshots; it does not turn them into HealthKit documents. Follow the [Health Connect export guide](/health-connect-export/) for an Android file workflow.

## Durable rather than disposable

A terminal timeout or network drop does not silently turn accepted work into failure. Direct exports are seven-day durable jobs:

```bash
# Inspect a retained job
healthmd status --job JOB_UUID

# Resume a paused raw/extract artifact when this output option is permitted
healthmd resume JOB_UUID --timeout 300 --output recovered.json

# Request cancellation only when you intend to stop that job
healthmd cancel JOB_UUID
```

Use the actual job UUID from the result. For generated-file jobs, keep the original destination; the `--output` example above is for a raw or extraction artifact when permitted. [Resume](/docs/cli-reference/resume/) retains the immutable source, dates, scope, destination, request fingerprint, and committed partition frontier. Cancellation becomes terminal only after the phone acknowledges it.

## Connect an agent

After checking the terminal path, use the [standalone Apple Health query walkthrough](/blog/query-apple-health-with-claude-or-codex/) to connect an MCP host. Configure the absolute standalone `healthmd` executable with arguments `mcp serve`; do not substitute the bundled Mac helper path.

For a combined Codex configuration and pairing flow, `healthmd setup codex` is an alternative to doing those setup steps separately. Check the selected executable and device afterward. Readiness, capability discovery and an exact date scope still come before health queries.

## What stays private

- The phone performs platform health reads.
- There is no Health.md health-data cloud hop or account.
- Pairing and transport are authenticated and encrypted.
- Query requests carry explicit dates, metrics, sources, and detail.
- Large raw bodies go to validated files or a private durable spool, not automatically into a model conversation.
- Coverage, partial outcomes, missing dates, and unsupported types stay visible.

Local transport does not make a remote model local. Any results passed into your agent are subject to that host and model provider's handling. The separate opt-in Health.md Cloud pilot is not used by this direct-phone path; see the [privacy policy](/privacy-policy.html#retention) for its distinct terms.

This is factual data access, not medical advice. Agents should preserve units, evidence, missingness, and limitations rather than diagnosing or calling a direction better or worse.

<div class="cta-row">
<a class="button" href="/docs/cli/">Read the CLI docs</a>
<a class="button secondary" href="/blog/query-apple-health-with-claude-or-codex/">Run a bounded agent query</a>
<a class="button secondary" href="/docs/release-status/">Check release status</a>
</div>
