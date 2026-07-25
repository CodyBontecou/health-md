# Manual IP / Tailscale Mac Destination

Health.md normally connects iPhone to Mac with Apple Multipeer Connectivity. That works well on the same Wi‑Fi network or nearby Bluetooth, but it does not reliably work across Tailscale because Bonjour/mDNS discovery is not carried like a normal LAN broadcast.

Manual IP / Tailscale mode is an opt-in fallback that lets the iPhone connect directly to the Mac by address.

## Requirements

- Health.md open on both iPhone and Mac. Update both apps to the current version to save and restore trusted connections.
- Mac Destination configured with a writable destination folder.
- Both devices on a trusted private network, such as the same Tailscale tailnet.
- A firewall path from iPhone to the Mac on TCP port `17646`.

## Mac setup

1. Open Health.md on Mac.
2. Go to **Mac Destination**.
3. In **Manual IP / Tailscale**, enable **Allow Manual IP Connections**.
4. Copy the Tailscale address shown in the card. Tailscale addresses are usually in the `100.x.y.z` range and are labeled `Tailscale` when detected.
5. Click **Generate Code**. The pairing code expires after about 10 minutes.

## iPhone setup

1. Open Health.md on iPhone.
2. Go to **Mac Destination**.
3. In **Connect by IP Address**, enter:
   - the Mac Tailscale IP or hostname;
   - port `17646` unless you are using a custom build;
   - the pairing code shown on the Mac.
4. Tap **Connect**. The keyboard closes while Health.md connects.
5. Return to **Export** and choose **Connected Mac**.

After the first successful connection, Health.md saves this Mac as a trusted connection. The iPhone reconnects when the app opens or returns to the foreground, so the temporary pairing code is no longer required. Enter a newly generated code only when pairing a different Mac or repairing a connection whose trust was reset.

## Security model

Manual IP mode is disabled by default. When enabled, the Mac listens on TCP port `17646` and requires a pairing code before accepting sync messages.

The pairing code itself is not sent over the network or saved. The iPhone proves it knows the code with a verifier derived from the code, an ephemeral Curve25519 public key, and a nonce. After pairing succeeds, both devices derive a per-connection symmetric key and encrypt sync messages with CryptoKit `ChaChaPoly`.

Current app versions also issue a random 256-bit reconnect secret inside that encrypted connection and store it in each device's local Keychain. Future connections use mutual HMAC proofs with fresh Curve25519 keys and nonces. The short-lived six-digit code is never reused as a long-term credential.

Health.md still does not upload health data to a Health.md server. The transfer is direct from iPhone to Mac.

## Troubleshooting

| Problem | Fix |
|---|---|
| iPhone cannot connect | Confirm Tailscale is enabled on both devices and the Mac address is reachable. |
| Pairing code rejected | Generate a new code on Mac and re-enter it on iPhone. |
| Pairing code expired | Generate a fresh code. |
| Pairing code field is empty after connecting | This is expected after the Mac is saved. Tap **Connect** without a code; Health.md uses the Keychain credential. |
| Manual IP protocol version is incompatible | Update Health.md on both iPhone and Mac, then pair again. |
| Saved connection is no longer trusted | Generate a fresh code on Mac and enter it on iPhone to repair the saved connection. |
| Connected but export disabled | Choose or re-select the Mac destination folder. |
| Mac address list is empty | Confirm Wi‑Fi or Tailscale is active, then click **Refresh**. |
| macOS firewall blocks the connection | Allow incoming connections for Health.md or permit TCP port `17646`. |

## Implementation notes

- Default nearby sync still uses Multipeer Connectivity.
- Manual IP sync reuses the existing `SyncMessage` protocol and `MacExportJobExecutor` write path.
- The iPhone still reads HealthKit and builds `MacExportJob` payloads; the Mac still only writes files to the selected destination folder.
