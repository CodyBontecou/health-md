---
title: "healthmd direct"
description: "Pair Health.md phones and manage this CLI installation's local trust."
---

Pair the portable CLI with Health.md on iPhone or Android, list trusted phones, or remove local trust.

## Synopsis

```text
healthmd direct [pair|devices|unpair|reset-trust]
```

Running `healthmd direct` without a subcommand lists the available actions without starting a listener or changing trust.

## Subcommands

| Command | Description |
|---|---|
| `healthmd direct pair` | Pair this CLI installation with an open Health.md mobile app. |
| `healthmd direct devices` | List the local installation and trusted phones without network access. |
| `healthmd direct unpair [DEVICE_UUID]` | Remove local trust for one phone. |
| `healthmd direct reset-trust --confirm` | Remove all local direct trust. |

All subcommands accept the [global options](/docs/cli-reference/#global-options).

## `healthmd direct pair`

```text
healthmd direct pair [OPTIONS]
```

The command opens a bounded Manual IP listener and prints a universal QR code, shared 20-digit code, address, and port to stderr. Keep it running while completing the pairing action in Health.md.

| Option | Description | Default |
|---|---|---|
| `--timeout <SECONDS>` | Keep the pairing listener open. Range: 10–600. | `120` |
| `--shared-pairing-code <CODE>` | Override the shared 20-digit iOS/Android code encoded in the QR. | Generated securely. |
| `--pairing-code <CODE>` | Override the six-digit legacy Apple-v1 code. | Generated securely. |
| `--android-pairing-code <CODE>` | Deprecated compatibility name for the shared code. Conflicts with `--shared-pairing-code`. | — |

Normal pairing needs no options:

```bash
healthmd direct pair
```

On iPhone, open **Sync → Direct CLI Access**. On Android, open **Settings → Direct CLI**. Scan the QR code in the app, or enter the shown private-LAN/Tailscale address, port, and code.

The one-time codes are short-lived and are never persisted. Reconnect trust is stored in the operating system's native credential service.

## `healthmd direct devices`

```text
healthmd direct devices
```

Lists this CLI installation and locally trusted phones without opening credentials for a connection or contacting a phone.

Use a returned device UUID when routing would otherwise be ambiguous:

```bash
healthmd status --device 11111111-2222-4333-8444-555555555555
```

## `healthmd direct unpair`

```text
healthmd direct unpair [DEVICE_UUID]
```

Removes local trust for one phone. Omit `DEVICE_UUID` for non-mutating guidance.

```bash
healthmd direct unpair 11111111-2222-4333-8444-555555555555
```

Also forget the CLI from the mobile app before pairing again.

## `healthmd direct reset-trust`

```text
healthmd direct reset-trust [--confirm]
```

Without `--confirm`, the command only explains the action. With `--confirm`, it discards every local direct pairing for this CLI installation.

```bash
healthmd direct devices
healthmd direct reset-trust --confirm
```

Use reset only when all local trust is unusable or intentionally being removed. It does not cancel durable jobs or delete exported files.

## Transport

The portable CLI supports Manual IP over a local network or Tailscale. `--transport nearby` is retained for compatibility but returns `transport_unsupported`; the CLI never silently switches transport.
