# Android Desktop Destination Strategy

## Decision

Android does **not** implement the iOS iPhone → Mac local-network destination in Phase 2. It is marked platform-specific N/A for Android parity.

## Rationale

- Android already exports through the Storage Access Framework (SAF), so users can choose any local folder or document-provider folder exposed by the device.
- Synced desktop workflows are supported by selecting a provider-backed folder (Google Drive, OneDrive, Syncthing, Obsidian Sync local folder, etc.) when that provider exposes SAF write access.
- Rebuilding the iOS local-network Mac bridge on Android would require a new cross-platform pairing/security model and a desktop listener that is outside the current Android app surface.

## Future option

A cross-platform desktop bridge can be revisited as a separate feature: QR pairing, local-network discovery, explicit device trust, encrypted payloads, and clear revocation UX. Until then, Android destination status is:

| Destination | Android status |
|---|---|
| Local device folder | Supported via SAF |
| Cloud/synced provider folder | Supported when provider exposes SAF |
| iOS/macOS local network Mac destination | Platform-specific N/A |
| Future cross-platform desktop bridge | Deferred |
