#if os(iOS)
import AVFoundation
import HealthMdConnectionCore
import SwiftUI
import Vision
import VisionKit

struct DirectCLIPairingScannerView: View {
    private enum CameraState: Equatable {
        case checking
        case ready
        case permissionDenied
        case unavailable
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let onPairingLink: (IPhoneDirectCLIPairingLink) -> Void
    /// Dismisses to the destination's manual code entry (ScannerG "Enter code instead").
    var onEnterCode: (() -> Void)? = nil

    @State private var cameraState: CameraState = .checking
    @State private var rejectedCode = false

    /// The scanner always renders over the camera, so it uses the dark palette.
    private var palette: GlassPalette { .dark }

    var body: some View {
        ZStack {
            Color.glassHex(0x1B1B20).ignoresSafeArea()

            scannerContent
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(palette.text)
                            .frame(width: 44, height: 44)
                            .glassSurface(in: Circle(), style: .strong, isInteractive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close QR scanner")
                    Spacer()
                    Text("Scan pairing QR")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }

                Spacer()

                if cameraState == .ready {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 250, height: 250)
                        .shadow(color: .black.opacity(0.45), radius: 8)
                        .accessibilityHidden(true)
                }

                Spacer()

                scannerMessage
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: GlassMetrics.dialogRadius, style: .strong)
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.vertical, Spacing.s4)
        }
        .environment(\.glassPalette, palette)
        .task {
            await prepareCamera()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await prepareCamera() }
            } else {
                cameraState = .checking
            }
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        switch cameraState {
        case .ready:
            DirectCLIPairingDataScanner(
                onPairingLink: { pairingLink in
                    dismiss()
                    onPairingLink(pairingLink)
                },
                onRejectedCode: {
                    rejectedCode = true
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "That is not a valid Health.md Direct CLI pairing QR code."
                    )
                },
                onFailure: {
                    cameraState = .unavailable
                }
            )
        case .checking:
            ProgressView()
                .tint(.white)
                .controlSize(.large)
        case .permissionDenied, .unavailable:
            Image(systemName: "camera.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var scannerMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch cameraState {
            case .checking:
                headline(Text("Preparing Camera"))
                caption("Health.md uses the camera only to recognize the pairing QR you choose.")
            case .ready:
                if rejectedCode {
                    headline(Text("That QR is not a valid Direct CLI pairing code. Scan the fresh QR shown by healthmd."), color: palette.coral)
                } else {
                    headline(Text("Start pairing from \(Text(verbatim: "healthmd").font(.system(size: 15, design: .monospaced))) or your MCP client, then point at its QR."))
                }
                caption("The camera only reads the code you choose. If it’s blocked, enable it in Settings or enter the code instead.")
            case .permissionDenied:
                headline(Text("Camera Access Required"))
                caption("Allow camera access in Settings to scan a Direct CLI pairing QR securely inside Health.md.")
                Button("Open Settings") {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(settingsURL)
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            case .unavailable:
                headline(Text("Camera Unavailable"))
                caption("Close other apps using the camera, then try again. Manual IP and pairing-code entry remain available.")
                Button("Try Again") {
                    Task { await prepareCamera() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
            if let onEnterCode {
                Button {
                    dismiss()
                    onEnterCode()
                } label: {
                    Text("Enter code instead")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(palette.surface2))
                        .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("directCLI.scanner.enterCode")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func headline(_ text: Text, color: Color? = nil) -> some View {
        text
            .font(.system(size: 15))
            .foregroundStyle(color ?? palette.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 13))
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @MainActor
    private func prepareCamera() async {
        rejectedCode = false
        cameraState = .checking
        guard DataScannerViewController.isSupported else {
            cameraState = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraState = DataScannerViewController.isAvailable ? .ready : .unavailable
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            cameraState = granted && DataScannerViewController.isAvailable
                ? .ready
                : (granted ? .unavailable : .permissionDenied)
        case .denied, .restricted:
            cameraState = .permissionDenied
        @unknown default:
            cameraState = .unavailable
        }
    }
}

private struct DirectCLIPairingDataScanner: UIViewControllerRepresentable {
    let onPairingLink: (IPhoneDirectCLIPairingLink) -> Void
    let onRejectedCode: () -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard !coordinator.isStopped else { return }
            do {
                try scanner.startScanning()
            } catch {
                coordinator.parent.onFailure()
            }
        }
        return scanner
    }

    func updateUIViewController(
        _ uiViewController: DataScannerViewController,
        context: Context
    ) {
        context.coordinator.parent = self
    }

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        coordinator.isStopped = true
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DirectCLIPairingDataScanner
        var isStopped = false
        private var acceptedCode = false
        private var lastRejection = Date.distantPast

        init(parent: DirectCLIPairingDataScanner) {
            self.parent = parent
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            guard !acceptedCode, !isStopped else { return }
            isStopped = true
            parent.onFailure()
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !acceptedCode, !isStopped else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue else { continue }
                guard let pairingLink = IPhoneDirectCLIPairingLink(scannedPayload: payload) else {
                    let now = Date()
                    if now.timeIntervalSince(lastRejection) >= 1 {
                        lastRejection = now
                        parent.onRejectedCode()
                    }
                    continue
                }
                acceptedCode = true
                dataScanner.stopScanning()
                parent.onPairingLink(pairingLink)
                return
            }
        }
    }
}
#endif
