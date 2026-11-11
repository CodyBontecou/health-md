# Scrawl development captures

The iOS Debug app links the official [ScrawlKit SDK](https://github.com/kitlangton/scrawl), pinned to `6d4fa333475ef5170c4df683e306480f8618b95a`. Debug builds require iOS 18; Release retains its existing deployment target and does not install Scrawl gestures or handle pairing links. ScrawlKit is inert until the owner pairs a device.

1. Run Scrawl on your Mac and complete its macOS permission prompts.
2. Build and install the iOS app with the Debug configuration.
3. Run `scrawl link --scheme healthmd` on the Mac and scan its QR code/open its link on that phone. The link includes a private pairing token; do not commit it.
4. Hold three fingers on the app for half a second to start or finish. Allow the microphone and Local Network prompts when recording/sending.
5. Use `scrawl inspect latest` on the Mac, or paste the capture into your agent with Option-Shift-V.

To unpair, open `healthmd://scrawl?reset=1`. For USB fallback, the Mac's Scrawl config lists this app under `usbApps`. A new Debug build must be installed before pairing works; the existing App Store app does not gain this SDK from a source change.

ScrawlKit captures the app's UI and narration only after the owner starts a capture. Treat recordings as potentially containing the data currently visible on screen. No export schema, product data grants or app automation contract changes. This is iOS-only developer tooling: ScrawlKit provides no Android SDK; Android can be captured through the Mac screen with an existing mirror. On macOS use Scrawl's global screen/window capture.
