import Combine
import Foundation
import SwiftUI

/// Device-local, non-security guard that prevents accidental in-app configuration changes.
///
/// The preference is intentionally separate from export settings and operation snapshots. It
/// controls interactive UI mutations only; existing schedules, shortcuts, direct requests, and
/// in-progress operations continue to use their saved configuration.
@MainActor
final class ConfigurationProtectionManager: ObservableObject {
    static let storageKey = "configurationProtection.preventAccidentalChanges"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var blockedChangeToastID: UUID?
    @Published private(set) var settingsNavigationRequestID: UUID?

    private let userDefaults: UserDefaults
    private var toastDismissTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isEnabled = userDefaults.bool(forKey: Self.storageKey)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        userDefaults.set(enabled, forKey: Self.storageKey)
        if !enabled {
            dismissBlockedChangeToast()
        }
    }

    /// Performs a user-initiated configuration mutation when protection is off. When protection
    /// is on, the mutation is rejected and the shared tappable toast is presented instead.
    @discardableResult
    func performConfigurationChange(_ change: () -> Void) -> Bool {
        guard !isEnabled else {
            presentBlockedChangeToast()
            return false
        }
        change()
        return true
    }

    /// Wraps a control binding so an editor that was already open cannot mutate configuration
    /// after protection is enabled. Local navigation and read-only interactions remain available.
    func protecting<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { [weak self] newValue in
                self?.performConfigurationChange {
                    binding.wrappedValue = newValue
                }
            }
        )
    }

    func presentBlockedChangeToast() {
        let toastID = UUID()
        blockedChangeToastID = toastID
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self?.blockedChangeToastID == toastID else { return }
            self?.blockedChangeToastID = nil
        }
    }

    func openProtectionSettingFromToast() {
        settingsNavigationRequestID = UUID()
        dismissBlockedChangeToast()
    }

    func consumeSettingsNavigationRequest(_ requestID: UUID) {
        guard settingsNavigationRequestID == requestID else { return }
        settingsNavigationRequestID = nil
    }

    func dismissBlockedChangeToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        blockedChangeToastID = nil
    }
}

/// Intercepts taps on a configuration region while protection is enabled. The content remains
/// visible so users can inspect their current setup, while the overlay turns an attempted edit
/// into the shared explanatory toast.
private struct ConfigurationChangesProtectedModifier: ViewModifier {
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    func body(content: Content) -> some View {
        content
            .disabled(configurationProtection.isEnabled)
            .overlay {
                if configurationProtection.isEnabled {
                    Button {
                        configurationProtection.presentBlockedChangeToast()
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.ConfigurationProtection.protectedRegion)
                    .accessibilityLabel("Settings are locked")
                    .accessibilityHint("Double tap to learn how to allow configuration changes")
                }
            }
    }
}

extension View {
    /// Marks a region as configuration-changing while preserving its read-only appearance.
    func configurationChangesProtected() -> some View {
        modifier(ConfigurationChangesProtectedModifier())
    }
}

struct ConfigurationProtectionToast: View {
    @ObservedObject var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        if configurationProtection.blockedChangeToastID != nil {
            Button {
                configurationProtection.openProtectionSettingFromToast()
            } label: {
                HStack(spacing: Spacing.s3) {
                    Image(systemName: "lock.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .frame(width: 32, height: 32)
                        .background(Color.accentSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings are locked")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.textPrimary)
                        Text("Turn off Prevent Accidental Changes in Settings to edit your configuration.")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Spacing.s2)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .accessibilityHidden(true)
                }
                .padding(Spacing.s3)
                .background(Color.bgPrimary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
                .contentShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.ConfigurationProtection.toast)
            .accessibilityLabel("Settings are locked")
            .accessibilityHint("Double tap to open Prevent Accidental Changes in Settings")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
