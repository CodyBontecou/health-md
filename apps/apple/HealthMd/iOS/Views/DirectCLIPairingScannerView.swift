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

    @State private var cameraState: CameraState = .checking
    @State private var rejectedCode = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            scannerContent
                .ignoresSafeArea()

            VStack(spacing: Spacing.s4) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                    .accessibilityLabel("Close QR scanner")
                }

                Spacer()

                if cameraState == .ready {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 264, height: 264)
                        .shadow(color: .black.opacity(0.45), radius: 8)
                        .accessibilityHidden(true)
                }

                Spacer()

                scannerMessage
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s4)
        }
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            switch cameraState {
            case .checking:
                Label("Preparing Camera", systemImage: "camera")
                    .font(.headline)
                Text("Health.md uses the camera only to recognize the pairing QR you choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .ready:
                Label("Scan Direct CLI QR", systemImage: "qrcode.viewfinder")
                    .font(.headline)
                Text(
                    rejectedCode
                        ? "That QR is not a valid Direct CLI pairing code. Scan the fresh QR shown by healthmd."
                        : "Point the camera at the QR shown by healthmd. A valid private-network code starts pairing immediately."
                )
                .font(.footnote)
                .foregroundStyle(rejectedCode ? Color.warning : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            case .permissionDenied:
                Label("Camera Access Required", systemImage: "camera.fill")
                    .font(.headline)
                Text("Allow camera access in Settings to scan a Direct CLI pairing QR securely inside Health.md.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(settingsURL)
                }
                .buttonStyle(.borderedProminent)
            case .unavailable:
                Label("Camera Unavailable", systemImage: "camera.fill")
                    .font(.headline)
                Text("Close other apps using the camera, then try again. Manual IP and pairing-code entry remain available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") {
                    Task { await prepareCamera() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
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
