---
title: "CLI Setup"
description: "Install the healthmd command, check Mac and iPhone readiness, trigger iPhone-sourced exports from Terminal, and troubleshoot CLI JSON responses."
---

<p>The Health.md CLI is a small Terminal client for the running Mac app. It lets you check readiness, start iPhone-sourced exports, and request strict canonical Apple Health JSON for scripts or coding agents.</p>

<div class="callout">
<strong>The CLI does not read Apple Health directly.</strong>
<p style="margin-top:6px;">HealthKit access stays on iPhone. The command talks to the local Mac app, the Mac app talks to the open iPhone app, and the iPhone reads HealthKit.</p>
</div>

## How it works

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Health.md CLI export flow">
    <span><strong>Terminal</strong>Runs <code>healthmd</code> commands.</span>
    <span><strong>Mac app</strong>Listens on localhost and owns folder access.</span>
    <span><strong>iPhone app</strong>Reads HealthKit and applies export settings.</span>
    <span><strong>Destination</strong>Mac folder receives Markdown, Bases, JSON, or CSV files.</span>
  </div>
</div>

## Requirements

<ul>
<li>Health.md for Mac installed and open.</li>
<li>Health.md for iPhone installed, unlocked, open, and connected to the Mac app for export commands.</li>
<li>A selected writable Mac destination folder for file-writing exports.</li>
<li>No destination folder required when using <code>--raw</code> to return JSON without writing files.</li>
</ul>

## Install the command

Open Health.md on Mac, then go to the <strong>CLI</strong> tab. The app shows the exact bundled helper path for your install, usually:

```bash
/Applications/Health.md.app/Contents/Helpers/healthmd
```

### Option 1: alias for the current shell

Use this when you only need the command in the current Terminal session:

```bash
alias healthmd="/Applications/Health.md.app/Contents/Helpers/healthmd"
```

### Option 2: persistent symlink

Use this when you want <code>healthmd</code> to work from future Terminal sessions:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd" ~/.local/bin/healthmd
```

If <code>~/.local/bin</code> is not on your <code>PATH</code>, add this to your shell config:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then verify the command:

```bash
healthmd --help
```

## Check readiness

Run status before triggering an export:

```bash
healthmd status
```

The response is JSON. Key fields to check:

<div class="options">
<div class="option"><strong><code>mac_app</code></strong><p>Should be <code>running</code>. If not, open Health.md on Mac.</p></div>
<div class="option"><strong><code>iphone.connected</code></strong><p>Should be <code>true</code> for exports. If false, unlock iPhone, open Health.md, and wait for the Mac connection.</p></div>
<div class="option"><strong><code>iphone.can_trigger_exports</code></strong><p>Should be <code>true</code> for file-writing exports.</p></div>
<div class="option"><strong><code>iphone.can_trigger_raw_exports</code></strong><p>Should be <code>true</code> for <code>--raw</code> JSON exports.</p></div>
<div class="option"><strong><code>destination.selected</code> / <code>destination.writable</code></strong><p>Both should be <code>true</code> when writing files to the Mac.</p></div>
<div class="option"><strong><code>active_export</code></strong><p>Should be <code>null</code> before starting another export.</p></div>
</div>

## Export from Terminal

```bash
# Export yesterday to the selected Mac folder
healthmd export --iphone --yesterday

# Export the last 7 complete days ending yesterday
healthmd export --iphone --last 7

# Export an inclusive date range
healthmd export --iphone --from 2026-06-01 --to 2026-06-07

# Return strict canonical JSON without writing files
healthmd export --iphone --yesterday --raw

# Use the iPhone app's saved export settings exactly, including roll-ups
healthmd export --iphone --yesterday --use-iphone-settings
```

By default, CLI exports use your iPhone's saved formats, metrics, templates, filenames, and write behavior, but skip weekly, monthly, and yearly roll-up summaries for that one request. Add `--use-iphone-settings` when you want the saved iPhone settings exactly.

Strict <code>--raw</code> temporarily forces canonical Apple Health source capture without changing the saved preference, writes no files, and rejects partial capture unless <code>--allow-partial</code> is explicit. It currently does not fetch provider sidecars. Date ranges are capped at 366 days.

<p>Executed commands return machine-readable JSON. Help and argument/usage errors are plain terminal text. See the <a href="/docs/reference/api-and-cli/">API and CLI contract</a> and generated <a href="/docs/reference/generated/cli/exit-codes/">exit-code reference</a> before automating result handling.</p>

## Safe commands for scripts and agents

When running from a script or coding agent, make commands non-interactive and bounded:

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd status </dev/null
NO_COLOR=1 TERM=dumb timeout 180 healthmd export --iphone --yesterday </dev/null
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --last 7 </dev/null
```

Use longer shell timeouts for larger exports because HealthKit reads and Mac transfers can take time.

## Agent skill setup

The Mac app also includes a user-facing Health.md CLI agent skill. In the Mac app's <strong>CLI</strong> tab, use <strong>Install Agent Skill</strong> to copy the skill into your agent's skills directory, or copy the manual command and set <code>SKILLS_DIR</code> to the folder your agent reads.

The skill teaches an agent how to install <code>healthmd</code>, run bounded commands, interpret readiness JSON, avoid leaking raw health data, and explain next steps instead of blindly retrying failed exports.

## Troubleshooting

| JSON/error | What it usually means | Next action |
|---|---|---|
| <code>mac_app_unreachable</code> | The Mac app is not running or the localhost server is unreachable. | Open Health.md on Mac and run <code>healthmd status</code> again. |
| <code>iphone_not_connected</code> | The iPhone app is not connected to the Mac app. | Unlock iPhone, open Health.md, and wait for Mac Destination connection. |
| <code>unsupported_iphone</code> | The iPhone app version does not support CLI-triggered exports. | Update Health.md on iPhone. |
| `mac_destination_unavailable` | No selected or writable Mac folder for file exports. | Reselect the Mac destination folder, or use `--raw` if you only need JSON. |
| <code>export_limit_reached</code> | The free export quota is exhausted. | Unlock Full Access on iPhone. |
| <code>healthKitNotAuthorized</code> / <code>healthKitFetchFailed</code> | Health permission, iPhone lock-state, or HealthKit fetch issue. | Unlock iPhone and verify Health permissions. |
| <code>timed_out</code> | The export took longer than the wait window. | Check status and Mac app history before retrying; use a longer timeout for large ranges. |

<div class="callout">
<strong>Privacy note.</strong>
<p style="margin-top:6px;">Raw mode can return health samples directly in Terminal. Do not paste raw output into chats, logs, or bug reports unless you intentionally want to share that data.</p>
</div>

## Related

<div class="related">
  <a href="/docs/macos/"><span>Desktop</span>macOS App — destination setup, history, menu bar, and CLI tab.</a>
  <a href="/docs/sync/"><span>Connection</span>Mac Sync — pair iPhone and Mac for local exports.</a>
  <a href="/docs/shortcuts/"><span>Automation</span>Shortcuts — run iPhone-native export actions without Terminal.</a>
  <a href="/docs/reference/api-and-cli/"><span>Contract</span>API and CLI Reference — localhost requests, strict raw validation, responses, and exit behavior.</a>
</div>
