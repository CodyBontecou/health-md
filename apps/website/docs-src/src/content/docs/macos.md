---
title: "macOS App"
description: "Use Health.md for Mac as an iPhone export destination, local CLI and MCP host, encrypted health-context store, history viewer, and folder authority."
---

Health.md for Mac has two local roles:

1. it receives iPhone export jobs and writes files to a folder you choose;
2. it hosts the loopback CLI, query API, encrypted health context, and MCP adapter used by local agents.

Apple Health remains on iPhone. The Mac app does not read HealthKit directly.

## Main areas

<div class="options">
<div class="option"><strong>Sync</strong><p>Shows whether the Mac is discoverable and ready for iPhone export jobs.</p></div>
<div class="option"><strong>Destination folder</strong><p>Stores a security-scoped bookmark for Markdown, JSON, CSV, Bases, roll-up, ZIP, and Daily Note outputs.</p></div>
<div class="option"><strong>Schedule</strong><p>Keeps Mac-side schedule and readiness visible. The iPhone still supplies HealthKit data.</p></div>
<div class="option"><strong>History</strong><p>Tracks export outcomes, durable progress, errors, and retry context for desktop-written files.</p></div>
<div class="option"><strong>Settings</strong><p>Shows destination health, encrypted context retention controls, and local CLI configuration.</p></div>
<div class="option"><strong>Menu bar</strong><p>Provides quick status, settings, and app access while Health.md stays available locally.</p></div>
<div class="option"><strong>CLI</strong><p>Installs the bundled <code>healthmd</code> and <code>healthmd-mcp</code> helpers, copies setup prompts, installs the optional agent skill, and shows tested commands.</p></div>
</div>

## Set up a Mac destination

1. Install and open Health.md on Mac.
2. Pick a destination folder on local disk, iCloud Drive, or inside an Obsidian vault.
3. On iPhone, enable Mac connectivity from the Sync tab.
4. On iPhone, choose Connected Mac as the export target.
5. Configure the export and tap Export.

The iPhone captures HealthKit data and the effective settings snapshot. Current peers transfer bounded checksum-validated partitions. The Mac uses the production exporters and writes the requested files.

<div class="callout">
<strong>HealthKit limitation.</strong>
<p style="margin-top:6px;">The Mac cannot query Apple Health on its own. Fresh exports and agent context require the open connected iPhone app. Cached encrypted queries can run without a fresh iPhone connection when stored coverage is sufficient.</p>
</div>

## CLI and agent setup

Open the Mac app's **CLI** area to:

- view the exact signed helper paths in this app bundle;
- copy aliases or `~/.local/bin` symlink commands;
- copy an agent-assisted setup prompt;
- install the optional `healthmd-cli` skill into a directory you choose;
- see current status, doctor, extraction, query, sleep, training, workout, coverage, and export commands;
- review common readiness errors.

The app never edits shell startup files or installs into a system directory without your action.

Start with:

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

See [Health.md CLI](/docs/cli/) for backend selection and [Local agents](/docs/agents/) for query architecture.

## Encrypted health context

Fresh query and evidence requests use a dedicated context-acquisition mode. The iPhone reads the exact requested metric, source, date, and detail scope. It does not create export files or change saved export preferences.

The Mac stores each compact owner day in an independently authenticated AES-256-GCM blob. A this-device-only, when-unlocked Keychain item holds the random encryption key. Filenames are random and do not reveal dates or metric names.

Settings reports the encrypted owner-day count and date range. Two independent actions control retention:

- **Delete Older Context** removes owner days strictly before the chosen boundary;
- **Delete All Encrypted Context** removes all context files and the dedicated Keychain key.

Context retention never deletes Apple Health data, export files, Mac destination bookmarks, or connected-provider credentials.

## Loopback API boundary

The Mac app listens on `127.0.0.1` and `::1` at port `17645` for local status, export, query, evidence, refresh, and durable job routes.

There is no bearer token or agent registration. Any local process can call the API while the app is open. Never expose, proxy, or tunnel the port to another machine.

The sandboxed `healthmd-mcp` helper accepts only canonical HTTP loopback endpoints and provides tools without shell, arbitrary files, SQL, URL fetch, resources, prompts, roots, or sampling.

## Direct CLI access is separate

The iPhone's **Direct CLI Access** setting creates a separate trust relationship between a direct-capable CLI and the iPhone. It can bypass the Mac app for raw export, canonical extraction, generated files, status, resume, and cancel.

Direct mode does not use the Mac app's encrypted query context or MCP. See [Direct iPhone CLI](/docs/cli-direct/) for pairing and platform support.

## Related

<div class="related">
  <a href="/docs/sync/"><span>Destination</span>Mac Sync: pair iPhone and Mac for local file exports.</a>
  <a href="/docs/cli/"><span>Terminal</span>Health.md CLI: install helpers, select a backend, and operate commands.</a>
  <a href="/docs/agents/"><span>Local context</span>Agents: scoped acquisition, encrypted storage, evidence, and retention.</a>
  <a href="/docs/mcp/"><span>Tools</span>Local MCP server: setup, tool catalog, and sandbox boundaries.</a>
  <a href="/docs/scheduling/"><span>Workflow</span>Scheduling: automate recurring exports.</a>
</div>
