---
title: "The Health.md CLI connects your terminal — and your agents — directly to iPhone."
description: "A standalone healthmd CLI and MCP server now pair directly with your iPhone over your own network. No Mac app, no cloud, no account."
lead: "healthmd runs on your computer, pairs with the Health.md app on your iPhone in one scan, and gives Codex, Claude, or your shell exact, bounded access to your health data — without a Health.md cloud in the middle."
date: "2026-08-06T09:00:00.000Z"
updated: "2026-08-06T09:00:00.000Z"
category: "Product update"
# STAGED DRAFT — do not publish until the healthmd-cli/v0.1.0-alpha.1 release is public.
# Flip draft to false, set the real date, and confirm every link and version below against the
# published release before shipping. Version references assume 0.1.0-alpha.1 on macOS and Linux.
draft: false
tags:
  - healthmd
  - cli
  - mcp
  - agents
---

Health.md started on iPhone: your health data, exported into the files and formats you choose, with no account and no cloud. The Mac app added a desktop destination. Today the bridge extends to the terminal.

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

Exports are durable jobs. If the connection drops or you close the app mid-transfer, nothing is lost: `healthmd status --job` reports the job, `healthmd resume` picks it up with the exact same request, and the final result is digest-verified.

## Connect Codex or Claude in one command

The part we think you'll actually feel: agents.

```bash
healthmd setup codex     # or: healthmd setup claude
```

One command pairs your iPhone if needed and writes the MCP configuration — preserving your existing settings, pinning the same executable identity your credentials already trust. Restart the host, call `healthmd_doctor`, and ask real questions:

- *"Compare my average resting heart rate this week with last week."*
- *"Show sleep sessions around my running workouts."*
- *"Which days are missing sleep data?"*

The local MCP server exposes 19 fixed tools: metric catalog, typed queries, charts, sleep sessions, workouts, period comparison, coverage, evidence packets, and durable exports. Every query runs against the paired, foreground iPhone. Export, resume, and cancel tools require explicit approval. A read-only 13-tool profile exists for hosts that should have no export authority at all.

## What stays private

- **HealthKit stays on iPhone.** The CLI never reads Apple Health from your computer. The app on your phone performs every read.
- **No cloud.** The connection is device-to-device, outbound from your phone, over Manual IP or Tailscale.
- **No account.** Pairing trust lives in your OS keychain, not on a server.
- **Scoped by construction.** Agents see the exact metric, date range, and detail you request — never a dump of everything.

## The honest fine print

This first release is an **alpha** (`0.1.0-alpha.1`). Prebuilt, signed, notarized archives cover **macOS and Linux**; Windows works from source (`cargo install healthmd-cli --locked`) until Authenticode signing is provisioned. The Homebrew formula arrives with the first stable release. And iOS sets the rules we all live by: your iPhone must be unlocked with Health.md open for fresh reads — this is a bridge, not headless background automation.

## Get started

Install from the exact release tag (never the repository-wide "latest" pointer, which stays reserved for the iOS apps):

```bash
VERSION='0.1.0-alpha.1'
BASE="https://github.com/CodyBontecou/health-md/releases/download/healthmd-cli/v$VERSION"
curl -fLO "$BASE/healthmd-cli-installer.sh"
sh healthmd-cli-installer.sh
```

Each release publishes Sigstore-signed checksums; the [CLI docs](/docs/cli/) walk through verifying them before you run anything. Rust users can `cargo install healthmd-cli --locked`.

<div class="cta-row">
<a class="button" href="/docs/cli/">Read the CLI docs</a>
<a class="button secondary" href="/docs/guides/connect-agent/">Connect an agent</a>
</div>
