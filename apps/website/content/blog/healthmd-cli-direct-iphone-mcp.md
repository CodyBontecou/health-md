---
title: "The Health.md CLI connects your terminal — and your agents — directly to iPhone."
description: "A standalone healthmd CLI and MCP server now pair directly with your iPhone over your own network. No Mac app, no Health.md cloud, no account."
lead: "healthmd runs on your computer, pairs with the Health.md app on your iPhone in one scan, and gives Codex, Claude, or your shell exact, bounded access to your health data — without a Health.md cloud in the middle."
date: "2026-08-06T09:00:00.000Z"
updated: "2026-08-30T19:55:43.000Z"
category: "Product update"
draft: false
tags:
  - healthmd
  - cli
  - mcp
  - agents
---

Health.md started on iPhone: your health data, exported into the files and formats you choose, with no account and no Health.md cloud. The Mac app added a desktop destination. Today the bridge extends to the terminal.

The standalone **`healthmd` CLI** runs on macOS, Linux, and Windows and connects directly to the Health.md app on your iPhone over your own network — your LAN or your Tailscale tailnet. No Mac app required. No Health.md server in the middle. Your iPhone keeps doing every HealthKit read; the CLI receives validated results and files.

## One scan, and you're paired

```bash
healthmd direct pair
```

The CLI displays a QR code. On iPhone, open Health.md → **Sync → Direct CLI Access** and tap **Scan Pairing QR**. The scan itself is the consent — the authenticated, encrypted connection starts immediately. Pairing is one-time; later commands reconnect without a code.

From there:

```bash
healthmd status              # exact readiness, no health values
healthmd export --last 7 --raw --output week.json
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --yesterday --destination ~/Documents/HealthVault
```

Exports are durable jobs. If the connection drops or you close the app mid-transfer, nothing is lost: `healthmd status --job JOB_UUID` reports the job, `healthmd resume JOB_UUID` picks it up with the exact same request, and the final result is digest-verified.

## Connect Codex in one command — or configure Claude

The part we think you'll actually feel: agents.

```bash
healthmd setup codex
```

For Codex, one command pairs your iPhone if needed and writes the MCP configuration — preserving your existing settings and pinning the same executable identity your credentials already trust. For Claude or another local MCP host, configure the absolute `healthmd` executable with arguments `mcp serve`; the [MCP guide](/docs/mcp/) explains the tool and security boundaries. Restart the host, call `healthmd_doctor`, and ask real questions:

- *"Compare my average resting heart rate this week with last week."*
- *"Show sleep sessions around my running workouts."*
- *"Which days are missing sleep data?"*

The local MCP server exposes 19 fixed tools: metric catalog, typed queries, charts, sleep sessions, workouts, period comparison, coverage, evidence packets, and durable exports. Every query runs against the paired, foreground iPhone. Export, resume, and cancel tools require explicit approval. A read-only 13-tool profile exists for hosts that should have no export authority at all.

## What stays private

- **HealthKit stays on iPhone.** The CLI never reads Apple Health from your computer. The app on your phone performs every read.
- **No Health.md cloud.** The connection is device-to-device, outbound from your phone, over Manual IP or Tailscale.
- **No account.** Pairing trust lives in your OS keychain, not on a server.
- **Explicit scope.** Agents receive the metric, date range, detail level, or complete-corpus operation you explicitly request; export, resume, and cancel tools require approval.

## The honest fine print

This release is an explicitly unqualified **public preview** (`0.1.0-alpha.3`). Prebuilt, signed, notarized archives cover macOS, and the Homebrew/Linuxbrew tap installs the matching release binaries. Windows artifacts remain Authenticode-unsigned until the signing ledger records a qualified publisher, so verify them through the Sigstore-signed checksum closure. Your iPhone must be unlocked with Health.md open for fresh reads — this is a bridge, not headless background automation.

## Get started

Install the preview from the project tap:

```bash
brew install CodyBontecou/tap/healthmd
healthmd --version
```

For direct downloads, use the exact `healthmd-cli/v0.1.0-alpha.3` release rather than the repository-wide "latest" pointer, which stays reserved for the Apple apps. Each release publishes Sigstore-signed checksums; the [CLI docs](/docs/cli/) walk through verifying them before you run anything.

<div class="cta-row">
<a class="button" href="/docs/cli/">Read the CLI docs</a>
<a class="button secondary" href="/docs/guides/connect-agent/">Connect an agent</a>
</div>
