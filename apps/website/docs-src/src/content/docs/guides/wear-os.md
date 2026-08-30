---
title: Wear OS Companion
description: Health.md for Wear OS adds activity and recovery tiles plus ten health complications to your watch, with the phone remaining the Health Connect authority.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Android · Wear OS</p>
  <p>Health.md ships a Wear OS companion under the same Google Play listing as the phone app. Add glanceable health surfaces to your watch while your phone stays the single Health Connect authority.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Get on Google Play</a>
    <a class="docs-button-secondary" href="/docs/android/">Android App Guide</a>
  </div>
</div>

## What the watch shows

| Surface | What you get |
|---|---|
| Daily Activity tile | Today's activity summary as a watch-face tile |
| Recovery tile | Today's recovery summary as a watch-face tile |
| Complications (10) | Activity, Recovery, Steps, Move, Exercise, Sleep, Resting Heart Rate, Average Heart Rate, HRV, and Blood Oxygen as watch-face complications |

Complications can be added to most watch faces from the face editor, and tiles appear in the watch's tile carousel.

## How it works

- The watch app is delivered through the same Play listing and signing identity as the phone app.
- Health data flows phone → watch over the Wear OS data layer as a private aggregate snapshot. The watch has **no direct Health Connect or Health Services sensing**; the phone remains authoritative for every metric.
- Watch surfaces refresh from the latest snapshot pushed by the phone app — no accounts, no cloud, and no health data leaves your devices.

## Requirements

- An Android phone with Health.md installed and paired to a Wear OS watch.
- Health Connect data on the phone for the metrics you want to see.
- Install Health.md on the watch from the Play Store on the watch, or from the companion phone's Play Store listing.

## Setup

1. Open the Play Store on your watch (or the watch section of the phone's Play Store) and install Health.md.
2. Open the phone app once so a snapshot can sync.
3. Long-press your watch face → **Customize** → add a Health.md complication, or swipe to the tile carousel and pin a Health.md tile.

## Privacy and validation

The companion uses a pure private aggregate transport contract, so no raw records are transmitted to the watch. Release quality is gated on emulator suites plus physical paired-device battery and OEM QA evidence before Wear OS artifacts ship. See the [Wear OS implementation checklist](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/wear-os-implementation.md) for the full runbook.
