import SwiftUI
import Combine

#if os(iOS)
import UIKit
import MessageUI
#elseif os(macOS)
import AppKit
#endif

/// Only observes app-side handoffs, never delivery or GitHub submission.
@MainActor
final class FeedbackReporter: ObservableObject {
    typealias Completion = @MainActor @Sendable (Bool) -> Void
    typealias Opener = @MainActor (URL, @escaping Completion) -> Void

    enum Route {
        case email, github
    }

    struct Failure: Identifiable {
        /// Which handoff failed; picks the sheet title.
        enum Kind { case generic, emailHandoff, mailQueue, githubHandoff }

        let id = UUID()
        let message: String
        let reportText: String
        var kind: Kind = .generic
    }

    @Published var failure: Failure?
    private var pendingMailFailure: Failure?
    private let opener: Opener
    private let strings: FeedbackFallbackCopy

    init(opener: @escaping Opener = FeedbackReporter.openURL, strings: FeedbackFallbackCopy? = nil) {
        self.opener = opener
        self.strings = strings ?? FeedbackFallbackCopy()
    }

    func open(_ route: Route) {
        let fallback = makeFailure(route, mailCompletion: false)
        let url = route == .email ? FeedbackHelper.mailtoURL() : FeedbackHelper.githubIssueURL()
        guard let url else {
            failure = fallback
            return
        }
        opener(url) { [weak self] opened in
            if !opened { self?.failure = fallback }
        }
    }

    #if os(iOS)
    /// Keep failure UI pending until SwiftUI has dismissed the compose sheet.
    /// Sent means queued by Mail, not confirmed delivery. Cancelled/saved are not failures.
    func completeMail(result: MFMailComposeResult, error: Error?) {
        pendingMailFailure = (result == .failed || error != nil)
            ? makeFailure(.email, mailCompletion: true) : nil
    }

    func mailSheetDismissed() {
        if let pendingMailFailure { failure = pendingMailFailure }
        pendingMailFailure = nil
    }
    #endif

    private func makeFailure(_ route: Route, mailCompletion: Bool) -> Failure {
        let message: String
        let kind: Failure.Kind
        if mailCompletion {
            message = strings.mailQueueFailure
            kind = .mailQueue
        } else if route == .email {
            message = strings.emailHandoffFailure
            kind = .emailHandoff
        } else {
            message = strings.githubHandoffFailure
            kind = .githubHandoff
        }
        // ReportFallbackG's template, then where the report goes, which the user still needs.
        let destination = route == .github
            ? "GitHub: https://github.com/\(FeedbackHelper.githubRepo)/issues/new"
            : "To: \(FeedbackHelper.supportEmail)"
        let text = Self.reportTemplate(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            platform: Self.platformDescription,
            strings: strings
        ) + "\n\n" + destination
        return Failure(message: message, reportText: text, kind: kind)
    }

    /// ReportFallbackG's prefilled report: a version line, three prompts and the reminder.
    static func reportTemplate(appVersion: String, platform: String, strings: FeedbackFallbackCopy) -> String {
        [
            "Health.md \(appVersion) · \(platform)",
            strings.problemPrompt,
            strings.expectedPrompt,
            strings.stepsPrompt,
            strings.privateDetailsReminder,
        ].joined(separator: "\n")
    }

    /// "iOS 26.1", "iPadOS 26.1" or "macOS 26.1". No device model or identifiers.
    static var platformDescription: String {
        #if os(iOS)
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #endif
    }

    private static func openURL(_ url: URL, completion: @escaping Completion) {
        #if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
        #elseif os(macOS)
        completion(NSWorkspace.shared.open(url))
        #endif
    }
}

/// Production recovery copy with an injectable resource/locale boundary for native tests.
struct FeedbackFallbackCopy {
    var bundle: Bundle = .main
    var locale: Locale = .current

    var mailQueueFailure: String {
        String(localized: "Mail could not queue your feedback. No delivery was confirmed. You can write and copy a report here. Text entered in Mail is not available to Health.md; re-enter it below if needed.", bundle: bundle, locale: locale)
    }
    var emailHandoffFailure: String {
        String(localized: "Health.md could not open your email app. You can write and copy a report here to send later or from another device.", bundle: bundle, locale: locale)
    }
    var githubHandoffFailure: String {
        String(localized: "Health.md could not open the GitHub issue template. No issue was submitted. You can write and copy a report here to submit later or from another device.", bundle: bundle, locale: locale)
    }
    var title: String {
        String(localized: "Feedback Could Not Be Sent", bundle: bundle, locale: locale)
    }
    var instructions: String {
        String(localized: "Edit the report, then copy it before closing. Nothing is sent automatically. Avoid including private health data.", bundle: bundle, locale: locale)
    }
    /// ReportFallbackG sheet title for the handoff that failed.
    func title(for kind: FeedbackReporter.Failure.Kind) -> String {
        switch kind {
        case .generic: return title
        case .emailHandoff: return String(localized: "Couldn’t open Mail", bundle: bundle, locale: locale)
        case .mailQueue: return String(localized: "Mail couldn’t send", bundle: bundle, locale: locale)
        case .githubHandoff: return String(localized: "Couldn’t open GitHub", bundle: bundle, locale: locale)
        }
    }
    var localOnly: String {
        #if os(macOS)
        String(localized: "Your report wasn’t sent. Copy it into any app, or edit it first — nothing leaves this Mac until you share it.", bundle: bundle, locale: locale)
        #else
        String(localized: "Your report wasn’t sent. Copy it into any app, or edit it first — nothing leaves this iPhone until you share it.", bundle: bundle, locale: locale)
        #endif
    }
    var problemPrompt: String { String(localized: "Problem:", bundle: bundle, locale: locale) }
    var expectedPrompt: String { String(localized: "What I expected:", bundle: bundle, locale: locale) }
    var stepsPrompt: String { String(localized: "Steps to reproduce:", bundle: bundle, locale: locale) }
    var privateDetailsReminder: String {
        String(localized: "(Remove any private folder or server details before sharing.)", bundle: bundle, locale: locale)
    }
    var attachDiagnostics: String { String(localized: "Attach diagnostics summary", bundle: bundle, locale: locale) }
    var attachDiagnosticsCaption: String { String(localized: "No health values, paths or credentials", bundle: bundle, locale: locale) }
    var share: String { String(localized: "Share…", bundle: bundle, locale: locale) }
    /// ReportFallbackG names the editor "Report text".
    var reportLabel: String { String(localized: "Report text", bundle: bundle, locale: locale) }
    var copyReport: String { String(localized: "Copy report", bundle: bundle, locale: locale) }
    var copied: String { String(localized: "Copied", bundle: bundle, locale: locale) }
    var reportCopied: String { String(localized: "Report copied", bundle: bundle, locale: locale) }
}

/// Ephemeral editor state shared by the sheet and synthetic pasteboard tests.
struct FeedbackReportDraft {
    var reportText: String {
        didSet {
            if reportText != oldValue { copied = false }
        }
    }
    private(set) var copied = false
    let strings: FeedbackFallbackCopy

    init(reportText: String, strings: FeedbackFallbackCopy = .init()) {
        self.reportText = reportText
        self.strings = strings
    }

    mutating func copy(using write: (String) -> Bool) {
        copied = write(reportText)
    }

    var copyConfirmation: String { copied ? strings.copied : "" }
    var copyAccessibilityLabel: String { copied ? strings.reportCopied : "" }
}

/// An entirely local alternative: editable, selectable text plus an explicit copy action.
/// It does not try another external URL or send/store any report automatically.
struct FeedbackFailureView: View {
    let failure: FeedbackReporter.Failure
    let strings: FeedbackFallbackCopy
    @State private var draft: FeedbackReportDraft
    @Environment(\.dismiss) private var dismiss

    init(failure: FeedbackReporter.Failure, strings: FeedbackFallbackCopy = .init()) {
        self.failure = failure
        self.strings = strings
        _draft = State(initialValue: FeedbackReportDraft(reportText: failure.reportText, strings: strings))
    }

    /// ReportFallbackG. Still local only: edit, copy or share, done.
    var body: some View {
        GlassReportFallbackContent(
            strings: strings,
            title: strings.title(for: failure.kind),
            message: failure.message,
            draft: $draft,
            onCopy: copyReport,
            onDone: { dismiss() }
        )
        .glassTheme()
    }

    private func copyReport() {
        draft.copy { text in
            #if os(iOS)
            UIPasteboard.general.string = text
            return true
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
            #endif
        }
    }
}

/// Adds or removes the diagnostics summary block in the editable report, so what is
/// copied or shared is always exactly what the editor shows.
enum FeedbackDiagnosticsAttachment {
    static func attaching(_ summary: String, to report: String) -> String {
        report.contains(summary) ? report : report + "\n\n" + summary
    }

    static func detaching(_ summary: String, from report: String) -> String {
        if let range = report.range(of: "\n\n" + summary) ?? report.range(of: summary) {
            var result = report
            result.removeSubrange(range)
            return result
        }
        return report
    }
}

private struct GlassReportFallbackContent: View {
    let strings: FeedbackFallbackCopy
    let title: String
    let message: String
    @Binding var draft: FeedbackReportDraft
    let onCopy: () -> Void
    let onDone: () -> Void

    @Environment(\.glassPalette) private var palette
    @State private var attachSummary = false
    @State private var attachedSummary: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(String(localized: "Close"), action: onDone)
                    .foregroundStyle(palette.sec)
                    .frame(minWidth: 70, minHeight: GlassMetrics.touchTarget, alignment: .leading)
                Spacer(minLength: 8)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Color.clear.frame(width: 70, height: 1)
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    Text(strings.localOnly)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    TextEditor(text: $draft.reportText)
                        .glassFont(.monoBody)
                        .foregroundStyle(palette.text)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 260)
                        .glassSurface()
                        .accessibilityLabel(strings.reportLabel)
                    GlassPanel {
                        Toggle(isOn: $attachSummary) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(strings.attachDiagnostics).glassFont(.body).foregroundStyle(palette.text)
                                Text(strings.attachDiagnosticsCaption).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                            }
                        }
                        .toggleStyle(GlassToggleStyle())
                        .padding(.horizontal, GlassMetrics.panelPadding)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("feedback.attachDiagnostics")
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.vertical, 8)
            }

            VStack(spacing: 8) {
                Button(strings.copyReport, action: onCopy).buttonStyle(GlassPrimaryButtonStyle())
                ShareLink(item: draft.reportText) {
                    Text(strings.share)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(palette.surface2))
                        .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Text(draft.copyConfirmation)
                    .glassFont(.caption)
                    .foregroundStyle(palette.ok)
                    .accessibilityLabel(draft.copyAccessibilityLabel)
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background { Color.clear.glassSurface(in: Rectangle()).ignoresSafeArea(edges: .bottom) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bg.ignoresSafeArea())
        .onChange(of: attachSummary) { _, attach in updateSummary(attach) }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private func updateSummary(_ attach: Bool) {
        if attach {
            Task {
                let summary = await Task.detached { DiagnosticSummary.current() }.value
                guard attachSummary else { return }
                attachedSummary = summary
                draft.reportText = FeedbackDiagnosticsAttachment.attaching(summary, to: draft.reportText)
            }
        } else if let summary = attachedSummary {
            draft.reportText = FeedbackDiagnosticsAttachment.detaching(summary, from: draft.reportText)
            attachedSummary = nil
        }
    }
}

extension View {
    func feedbackFailureSheet(_ failure: Binding<FeedbackReporter.Failure?>) -> some View {
        sheet(item: failure) { FeedbackFailureView(failure: $0) }
    }
}
