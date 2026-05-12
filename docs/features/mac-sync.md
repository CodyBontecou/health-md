# Mac Sync

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** iPhone → Sync; Mac → Sync
- **Source files:** `HealthMd/iOS/Views/SyncSettingsView.swift`, `HealthMd/Shared/Sync/SyncService.swift`, `HealthMd/Shared/Sync/SyncPayload.swift`, `README.md`

## What it does

Mac Sync sends Apple Health data from your iPhone to Health.md for macOS over the local network. The Mac cannot read HealthKit directly, so the iPhone acts as the health data source and the Mac receives cached records that can be exported to an Obsidian vault or any folder.

Sync uses Apple Multipeer Connectivity over local Wi-Fi and Bluetooth. It is direct device-to-device sync: no HealthKit samples, Markdown files, or vault contents are uploaded to a Health.md server.

## Who it is for

- Users who keep their Obsidian vault on a Mac.
- Users who want macOS exports, menu bar access, and keyboard shortcuts.
- Users who prefer exporting from a desktop folder instead of iOS Files.
- Users who want a local-first iPhone-to-Mac companion workflow.

If you only export from iPhone to Files or iCloud Drive, Mac Sync is optional.

## Where to find it

On iPhone:

1. Open Health.md.
2. Tap **Sync**.
3. Enable **Sync to Mac**.

On Mac:

1. Open Health.md for macOS.
2. Go to **Sync**.
3. Wait for the iPhone to appear or connect automatically.
4. Request/sync health data, then export from the Mac.

## Prerequisites

- Health.md installed on both iPhone and Mac.
- HealthKit permission granted on iPhone.
- Both devices on the same Wi-Fi network or within Bluetooth range.
- Local network/Bluetooth permissions allowed if iOS/macOS asks.
- Health.md open on the Mac when connecting.
- A Mac export folder selected before exporting from macOS.

## Setup

1. Install or open Health.md on the Mac.
2. On iPhone, open **Sync** and turn on **Sync to Mac**.
3. Keep both devices nearby.
4. Wait for the status to change from **Waiting for Mac** to **Connected to [Mac name]**.
5. Optionally enable **Auto-sync after export** when connected.
6. Tap **Sync Last 7 Days Now** to send recent health records to the Mac.
7. On Mac, choose an export folder and export the synced records.

## Sync behavior

The iPhone can send:

- specific dates requested by the Mac;
- the last 7 days from the iPhone Sync screen;
- larger all-time payloads used by the Mac sync flow;
- progress updates for large syncs.

Large payloads over 100 KB use Multipeer resource transfer for reliability. During active sync, the iPhone keeps the device awake and requests background execution time so the transfer can finish if the app is briefly backgrounded.

## Example cache/path

On macOS, synced health records are cached locally before export:

```text
~/Library/Application Support/Health.md/
```

Exports from the Mac then use the same shared export engine and can write files such as:

```text
ObsidianVault/Health/2026-05-12.md
ObsidianVault/Health/2026-05-12.json
ObsidianVault/Health/2026-05-12-bases.md
```

## Tips

- Keep both apps open during first sync.
- Use **Sync Last 7 Days Now** after travel or after not opening the Mac app for a while.
- Enable **Auto-sync after export** if your normal workflow starts on iPhone but ends on Mac.
- For scheduled macOS exports, sync the iPhone regularly so the Mac cache has fresh records.
- If discovery is unreliable, put both devices on the same Wi-Fi network and bring them close together.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| iPhone says Waiting for Mac | Mac app is closed or not browsing | Open Health.md on Mac and go to Sync. |
| Mac cannot find iPhone | Different networks, Bluetooth off, or local network permission denied | Put devices on same Wi-Fi, enable Bluetooth, and allow local network access. |
| Sync button says no connected device | Multipeer session is disconnected | Toggle Sync to Mac off/on and reopen the Mac app. |
| Transfer fails for a large range | Connection dropped mid-transfer | Keep apps foregrounded and retry with devices nearby. |
| Mac export has old data | iPhone has not synced recent records | Run **Sync Last 7 Days Now** or request a fresh sync from Mac. |
| Health data missing on Mac | iPhone lacks HealthKit permission or no samples exist for dates | Check Health permissions and Apple Health data on iPhone. |

## Video outline

- **Suggested title:** Sync Apple Health from iPhone to Mac for Obsidian
- **Hook:** “Your Mac cannot read Apple Health, but Health.md can securely send data from your iPhone to your Mac over your local network.”
- **Demo flow:**
  1. Show the Mac app waiting for an iPhone.
  2. Open iPhone → Sync and enable Sync to Mac.
  3. Show connection status changing to connected.
  4. Tap Sync Last 7 Days Now.
  5. Show synced records on Mac.
  6. Export from Mac to an Obsidian vault.
- **Key screenshot/recording moments:** iPhone Sync toggle, connection status, manual sync button, Mac recent syncs/cache, exported Markdown file.
- **CTA / next video:** “Next, we’ll schedule exports from the Mac menu bar.”

## Implementation notes

- `SyncService` wraps Multipeer Connectivity with `MCNearbyServiceAdvertiser` on iOS and `MCNearbyServiceBrowser` on macOS.
- The service type is `healthmd-sync`; sessions use required encryption.
- `SyncMessage` supports `requestData(dates:)`, `requestAllData`, `healthData`, `syncProgress`, `ping`, and `pong`.
- `SyncPayload` contains the source device name, sync timestamp, and one `HealthData` record per date.
- `SyncSettingsView` stores `syncEnabled` and `autoSyncAfterExport` in app storage.
- `sendLargePayload` switches to `MCSession.sendResource` for payloads larger than 100 KB.
