---
title: "What local-first health-data architecture actually means."
description: "A concrete look at Health.md's phone reads, user-controlled destinations, direct transport, credentials, optional providers, and cloud boundaries."
lead: "Local-first is an architectural boundary, not a slogan: know where health records are read, where they travel, and who controls every destination."
date: "2026-09-22T13:50:00.000Z"
updated: "2026-10-04"
category: "Engineering"
draft: false
tags:
  - healthmd
  - privacy
  - local-first
  - architecture
---

“Local-first” should be testable. It should tell you where data originates, which process can read it, what network hop is optional, and where the resulting file lives.

For Health.md, the primary source boundary is the phone. The iPhone reads Apple Health through HealthKit. Android reads Health Connect through the on-device API. The user selects permissions, metrics, dates, and a destination.

## The ordinary file path

The simplest workflow has no Health.md health-data server:

1. the phone reads an authorized platform API;
2. Health.md builds the selected output on-device;
3. it writes into a folder the user chose.

That folder may be local, in an Obsidian vault, or exposed by a sync provider. If the user chooses iCloud Drive, Google Drive, OneDrive, Syncthing, or Obsidian Sync, that provider's own network and privacy model applies. The local folder workflow has no Health.md server hop, but a user-selected destination can still sync.

## Direct computer access

The standalone CLI pairs with an open iPhone or Android device over Manual IP or Tailscale. Pairing and transport are authenticated and encrypted. The phone still performs the platform health read; the CLI receives the explicitly requested result.

Trust material belongs in the operating system credential service. Large health-bearing bodies go to validated files or a private durable spool rather than being copied automatically into an agent conversation. Job status is designed to expose health-free progress fields such as IDs, counts, bytes, and safe errors.

## The Mac path

The Apple apps can also prepare files for a connected Mac over the local network. The Mac is a destination and automation surface, not a replacement HealthKit source. Encrypted context and direct export paths keep version, coverage, and compatibility boundaries explicit.

The bundled Mac MCP server is a production component of the Mac app. The standalone cross-platform CLI/MCP package is versioned and qualified separately; a successful Mac workflow does not certify every Linux, Windows, Android, LAN, or Tailscale combination.

## Intentional network destinations

Local-first does not ban networks. It makes remote movement explicit.

The iPhone API Endpoint target POSTs selected JSON to a URL the user configures. Android raw snapshots can be sent to an explicitly selected HTTPS endpoint under stricter redirect and checksum rules. Connected provider features contact the provider the user chose. These are disclosed destinations, not a hidden Health.md relay.

### Separate optional cloud pilot

The optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. There is no public signup and no automatic device sync. Local folder exports and direct CLI queries do not automatically create a copy there. A separately authorized read-only cloud MCP endpoint can return retained fields to an agent; agent hosts and model providers may process or retain those values under their own policies.

The pilot retains original API-export JSON envelopes, including historical revisions and embedded source data, without an age cutoff, subject to its quota. It runs on an unbacked VM: disk, key, or VM loss can permanently destroy exports. Account deletion disables access immediately; background erasure is not instantaneous. It is not a generally available multi-user service. See the [privacy policy](/privacy-policy.html#retention) for the full boundaries.

## Analytics and billing boundaries

Product analytics must not contain health values, metric names, health dates, exported files, private paths, credentials, or user-entered text. Store purchases are handled by Apple or Google. The F-Droid Android build excludes billing and Health.md telemetry code entirely.

## Questions to ask any health-data tool

- Which device or service performs the read?
- Is the requested scope visible before access?
- Where are credentials stored?
- Can the tool distinguish empty from unavailable?
- Does a timeout cancel work or leave an unknown outcome?
- Which cloud or sync provider receives the result?
- Can a user delete trust and exported files independently?

A local-first design is strongest when those answers are part of the public contract, not assumptions left to a privacy-policy summary.

<div class="cta-row">
<a class="button" href="/docs/">Read the product docs</a>
<a class="button secondary" href="/privacy-policy/">Review the privacy policy</a>
</div>
