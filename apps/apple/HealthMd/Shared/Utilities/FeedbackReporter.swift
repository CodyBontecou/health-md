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
        let id = UUID()
        let message: String
        let reportText: String
    }

    @Published var failure: Failure?
    private var pendingMailFailure: Failure?
    private let opener: Opener

    init(opener: @escaping Opener = FeedbackReporter.openURL) {
        self.opener = opener
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
        if mailCompletion {
            message = String(localized: "Mail could not queue your feedback. No delivery was confirmed. You can write and copy a report here. Text entered in Mail is not available to Health.md; re-enter it below if needed.")
        } else if route == .email {
            message = String(localized: "Health.md could not open your email app. You can write and copy a report here to send later or from another device.")
        } else {
            message = String(localized: "Health.md could not open the GitHub issue template. No issue was submitted. You can write and copy a report here to submit later or from another device.")
        }
        let body = route == .github ? FeedbackHelper.issueBody : "\n\n\(FeedbackHelper.diagnosticsBlock)"
        let text = "To: \(FeedbackHelper.supportEmail)\nGitHub: https://github.com/\(FeedbackHelper.githubRepo)/issues/new\nSubject: Health.md Feedback\n\n\(body)"
        return Failure(message: message, reportText: text)
    }

    private static func openURL(_ url: URL, completion: @escaping Completion) {
        #if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
        #elseif os(macOS)
        completion(NSWorkspace.shared.open(url))
        #endif
    }
}

/// Ephemeral editor state shared by the sheet and synthetic pasteboard tests.
struct FeedbackReportDraft {
    var reportText: String {
        didSet {
            if reportText != oldValue { copied = false }
        }
    }
    private(set) var copied = false

    mutating func copy(using write: (String) -> Bool) {
        copied = write(reportText)
    }

    var copyConfirmation: String { copied ? String(localized: "Copied") : "" }
    var copyAccessibilityLabel: String { copied ? String(localized: "Report copied") : "" }
}

/// An entirely local alternative: editable, selectable text plus an explicit copy action.
/// It does not try another external URL or send/store any report automatically.
struct FeedbackFailureView: View {
    let failure: FeedbackReporter.Failure
    @State private var draft: FeedbackReportDraft
    @Environment(\.dismiss) private var dismiss

    init(failure: FeedbackReporter.Failure) {
        self.failure = failure
        _draft = State(initialValue: FeedbackReportDraft(reportText: failure.reportText))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("Feedback Could Not Be Sent")
                .font(Typography.headline())
            Text(failure.message)
                .fixedSize(horizontal: false, vertical: true)
            Text("Edit the report, then copy it before closing. Nothing is sent automatically. Avoid including private health data.")
                .font(Typography.caption())
            TextEditor(text: $draft.reportText)
                .font(Typography.monoCaption())
                .accessibilityLabel("Feedback report")
                .frame(minHeight: 180)
            HStack {
                Button("Copy Report") {
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
                Text(draft.copyConfirmation)
                    .accessibilityLabel(draft.copyAccessibilityLabel)
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(Spacing.s4)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 440)
        #endif
    }
}

extension View {
    func feedbackFailureSheet(_ failure: Binding<FeedbackReporter.Failure?>) -> some View {
        sheet(item: failure) { FeedbackFailureView(failure: $0) }
    }
}
