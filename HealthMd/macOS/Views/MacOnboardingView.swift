#if os(macOS)
import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import MultipeerConnectivity

// MARK: - macOS Onboarding
// A 4-step companion-app intro: welcome → how it works → install iPhone app → connect.
// Sets `hasCompletedMacOnboarding` in UserDefaults via the host view's @AppStorage binding.

struct MacOnboardingView: View {
    @EnvironmentObject var syncService: SyncService
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var animateIn = false

    private let totalSteps = 4
    private let appStoreURL = URL(string: "https://apps.apple.com/us/app/health-md/id6757763969")!

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                progressBar
                    .padding(.top, 14)
                    .padding(.horizontal, 24)

                Spacer(minLength: 24)

                Group {
                    switch currentStep {
                    case 0:
                        WelcomeStep(animateIn: animateIn)
                    case 1:
                        HowItWorksStep(animateIn: animateIn)
                    case 2:
                        GetIPhoneAppStep(animateIn: animateIn, appStoreURL: appStoreURL)
                    case 3:
                        ConnectStep(animateIn: animateIn)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: 580)
                .padding(.horizontal, 32)

                Spacer(minLength: 24)

                navigationFooter
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !animateIn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { animateIn = true }
                }
            }
            syncService.startBrowsing()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .font(.title3)
                .foregroundStyle(Color.accent)
            Text("health.md")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Skip") { onComplete() }
                    .buttonStyle(.plain)
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
                    .accessibilityLabel("Skip onboarding")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= currentStep ? Color.accent : Color.borderDefault)
                    .frame(height: 3)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentStep)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
    }

    // MARK: - Footer

    private var navigationFooter: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button(action: back) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(BrandTypography.bodyMedium())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
                .brandGlassButton()
            }

            Spacer()

            Button(action: advance) {
                HStack(spacing: 8) {
                    Text(currentStep == totalSteps - 1 ? "Get Started" : "Continue")
                    Image(systemName: currentStep == totalSteps - 1 ? "arrow.right" : "chevron.right")
                }
                .font(BrandTypography.bodyMedium())
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textPrimary)
            .brandGlassButton()
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
    }

    // MARK: - Step Transitions

    private func advance() {
        guard currentStep < totalSteps - 1 else {
            onComplete()
            return
        }
        animateIn = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                currentStep += 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { animateIn = true }
            }
        }
    }

    private func back() {
        guard currentStep > 0 else { return }
        animateIn = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                currentStep -= 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { animateIn = true }
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    let animateIn: Bool

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 112, height: 112)
                    .blur(radius: 28)
                    .opacity(0.5)
                    .accessibilityHidden(true)

                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.accent.opacity(0.4), radius: 24, y: 12)
            }
            .scaleEffect(animateIn ? 1.0 : 0.6)
            .opacity(animateIn ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.65), value: animateIn)

            VStack(spacing: 10) {
                Text("Health.md for Mac")
                    .font(BrandTypography.heading())
                    .foregroundStyle(Color.textPrimary)

                Text("The companion app to Health.md on iPhone")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .staggerIn(animateIn, index: 1)

            VStack(spacing: 10) {
                MacFeatureRow(icon: "iphone.gen3", text: "Sync from iPhone over local Wi-Fi")
                    .staggerIn(animateIn, index: 2)
                MacFeatureRow(icon: "arrow.up.doc.fill", text: "Export to any folder on your Mac")
                    .staggerIn(animateIn, index: 3)
                MacFeatureRow(icon: "calendar.badge.clock", text: "Schedule automatic exports")
                    .staggerIn(animateIn, index: 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandGlassCard()
        }
    }
}

// MARK: - Step 2: How It Works

private struct HowItWorksStep: View {
    let animateIn: Bool

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 18) {
                deviceIcon("iphone.gen3", label: "iPhone")
                    .scaleEffect(animateIn ? 1 : 0.7)
                    .opacity(animateIn ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.05), value: animateIn)

                Image(systemName: "chevron.right.2")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .opacity(animateIn ? 0.9 : 0)
                    .offset(x: animateIn ? 0 : -8)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: animateIn)

                deviceIcon("desktopcomputer", label: "Mac")
                    .scaleEffect(animateIn ? 1 : 0.7)
                    .opacity(animateIn ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: animateIn)
            }

            VStack(spacing: 10) {
                Text("How it works")
                    .font(BrandTypography.heading())
                    .foregroundStyle(Color.textPrimary)

                Text("Health.md on iPhone reads your Apple Health data. Your Mac receives a copy over the local network — nothing is uploaded to the cloud.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .staggerIn(animateIn, index: 1)

            VStack(spacing: 0) {
                MacStepRow(
                    number: "1",
                    title: "iPhone reads Health data",
                    detail: "Apple Health is the source of truth"
                )
                .staggerIn(animateIn, index: 2)

                Divider()
                    .background(Color.borderSubtle)
                    .padding(.horizontal, 16)

                MacStepRow(
                    number: "2",
                    title: "Sync to your Mac",
                    detail: "Encrypted, peer-to-peer over Wi-Fi"
                )
                .staggerIn(animateIn, index: 3)

                Divider()
                    .background(Color.borderSubtle)
                    .padding(.horizontal, 16)

                MacStepRow(
                    number: "3",
                    title: "Export anywhere",
                    detail: "Markdown, CSV, JSON — your folder, your rules"
                )
                .staggerIn(animateIn, index: 4)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .brandGlassCard()
        }
    }

    private func deviceIcon(_ symbol: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Color.accentSubtle))
                .overlay(Circle().strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))

            Text(label.uppercased())
                .font(.caption2.weight(.medium).monospaced())
                .foregroundStyle(Color.textMuted)
                .kerning(1.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

// MARK: - Step 3: Get iPhone App

private struct GetIPhoneAppStep: View {
    let animateIn: Bool
    let appStoreURL: URL

    @State private var copied = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .blur(radius: 22)
                    .opacity(0.6)
                    .accessibilityHidden(true)

                Image(systemName: "iphone.gen3")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 96, height: 96)
            .background(Circle().fill(Color.accentSubtle))
            .overlay(Circle().strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))
            .scaleEffect(animateIn ? 1 : 0.7)
            .opacity(animateIn ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.65), value: animateIn)

            VStack(spacing: 10) {
                Text("Get Health.md on iPhone")
                    .font(BrandTypography.heading())
                    .foregroundStyle(Color.textPrimary)

                Text("This Mac app needs the iPhone app to read your Apple Health data. Without it, there's nothing to sync.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .staggerIn(animateIn, index: 1)

            HStack(alignment: .top, spacing: 20) {
                if let qrImage = QRCodeGenerator.image(for: appStoreURL.absoluteString, size: 140) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 140, height: 140)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("App Store QR code")
                        .accessibilityHint("Scan with your iPhone camera to open Health.md in the App Store")
                }

                VStack(alignment: .leading, spacing: 12) {
                    BrandLabel("Scan with iPhone")

                    Text("Point your iPhone camera at the code to open Health.md in the App Store.")
                        .font(BrandTypography.detail())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appStoreURL.absoluteString, forType: .string)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied!" : "Copy Link")
                        }
                        .font(BrandTypography.detail())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textPrimary)
                    .brandGlassButton()
                    .accessibilityLabel(copied ? "Link copied" : "Copy App Store link")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .brandGlassCard()
            .staggerIn(animateIn, index: 2)

            Text("Already have it on your iPhone? Continue to connect.")
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textMuted)
                .staggerIn(animateIn, index: 3)
        }
    }
}

// MARK: - Step 4: Connect

private struct ConnectStep: View {
    @EnvironmentObject var syncService: SyncService
    let animateIn: Bool

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Image(systemName: heroIcon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(heroColor)
                    .blur(radius: 22)
                    .opacity(0.55)
                    .accessibilityHidden(true)

                Image(systemName: heroIcon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(heroColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 96, height: 96)
            .background(Circle().fill(Color.accentSubtle))
            .overlay(Circle().strokeBorder(heroColor.opacity(0.3), lineWidth: 1))
            .scaleEffect(animateIn ? 1 : 0.7)
            .opacity(animateIn ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.65), value: animateIn)

            VStack(spacing: 10) {
                Text("Connect to your iPhone")
                    .font(BrandTypography.heading())
                    .foregroundStyle(Color.textPrimary)

                Text("Open Health.md on your iPhone, go to Settings → Sync to Mac, and turn the toggle on. Make sure both devices are on the same Wi-Fi.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .staggerIn(animateIn, index: 1)

            VStack(alignment: .leading, spacing: 12) {
                BrandLabel("Status")

                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(BrandTypography.bodyMedium())
                            .foregroundStyle(Color.textPrimary)
                        Text(statusSubtitle)
                            .font(BrandTypography.detail())
                            .foregroundStyle(Color.textMuted)
                    }

                    Spacer()

                    if syncService.connectionState == .connecting {
                        ProgressView().controlSize(.small)
                    } else if syncService.connectionState == .disconnected {
                        Button {
                            syncService.stopBrowsing()
                            syncService.startBrowsing()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textMuted)
                        .accessibilityLabel("Refresh search")
                    }
                }

                if !syncService.discoveredPeers.isEmpty && syncService.connectionState != .connected {
                    Divider().background(Color.borderSubtle)
                    ForEach(syncService.discoveredPeers, id: \.displayName) { peer in
                        HStack {
                            Image(systemName: "iphone.gen3")
                                .foregroundStyle(Color.accent)
                            Text(peer.displayName)
                                .font(BrandTypography.bodyMedium())
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Button("Connect") {
                                syncService.connectToPeer(peer)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.accent)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brandGlassCard()
            .staggerIn(animateIn, index: 2)

            Text("You can finish connecting later from the Sync tab — no need to do it now.")
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .staggerIn(animateIn, index: 3)
        }
    }

    private var heroIcon: String {
        syncService.connectionState == .connected ? "checkmark.circle.fill" : "wifi"
    }

    private var heroColor: Color {
        syncService.connectionState == .connected ? Color.success : Color.accent
    }

    private var statusColor: Color {
        switch syncService.connectionState {
        case .connected: return Color.success
        case .connecting: return Color.warning
        case .disconnected:
            return syncService.discoveredPeers.isEmpty ? Color.textMuted : Color.accent
        }
    }

    private var statusTitle: String {
        switch syncService.connectionState {
        case .connected:
            return "Connected to \(syncService.connectedPeerName ?? "iPhone")"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return syncService.discoveredPeers.isEmpty
                ? "Searching for nearby iPhones…"
                : "iPhone found nearby"
        }
    }

    private var statusSubtitle: String {
        switch syncService.connectionState {
        case .connected: return "Ready to sync your health data"
        case .connecting: return "Establishing secure connection"
        case .disconnected:
            return syncService.discoveredPeers.isEmpty
                ? "Make sure Health.md is open on your iPhone with sync enabled"
                : "Click Connect to pair this Mac"
        }
    }
}

// MARK: - Supporting Rows

private struct MacFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentSubtle))

            Text(text)
                .font(BrandTypography.body())
                .foregroundStyle(Color.textPrimary)

            Spacer()
        }
    }
}

private struct MacStepRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Text(number)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentSubtle))
                .overlay(Circle().strokeBorder(Color.accent.opacity(0.3), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BrandTypography.bodyMedium())
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(BrandTypography.detail())
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Stagger animation modifier

private struct StaggeredItem: ViewModifier {
    let animateIn: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 14)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(index) * 0.07),
                value: animateIn
            )
    }
}

private extension View {
    func staggerIn(_ animateIn: Bool, index: Int) -> some View {
        modifier(StaggeredItem(animateIn: animateIn, index: index))
    }
}

// MARK: - QR Code

private enum QRCodeGenerator {
    static func image(for string: String, size: CGFloat) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaleFactor = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

#endif
