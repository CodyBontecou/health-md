import SwiftUI

#if os(iOS)
import UIKit
import MessageUI
#elseif os(macOS)
import AppKit
#endif

// MARK: - Feedback Helper

/// Serverless feedback: pre-filled email or GitHub issue with device diagnostics.
enum FeedbackHelper {

    static let supportEmail = "cody@isolated.tech"
    static let githubRepo = "CodyBontecou/health-md"

    // MARK: - Diagnostics

    /// Gathers non-identifying device/app info for bug reports.
    static var diagnosticsBlock: String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        #if os(iOS)
        let device = UIDevice.current.model          // "iPhone", "iPad"
        let platform = "iOS"
        #elseif os(macOS)
        let device = "Mac"
        let platform = "macOS"
        #endif

        return """
        ---
        App: Health.md \(appVersion) (\(buildNumber))
        Platform: \(platform) \(osVersion)
        Device: \(device)
        """
    }

    // MARK: - Email

    /// Builds a mailto URL with pre-filled subject and diagnostics body.
    static func mailtoURL(subject: String = "Health.md Feedback") -> URL? {
        let body = "\n\n\(diagnosticsBlock)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    #if os(iOS)
    /// Whether the device can present the in-app mail compose sheet.
    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    /// Configures an `MFMailComposeViewController` for feedback.
    static func makeMailCompose() -> MFMailComposeViewController {
        let mc = MFMailComposeViewController()
        mc.setToRecipients([supportEmail])
        mc.setSubject("Health.md Feedback")
        mc.setMessageBody("\n\n\(diagnosticsBlock)", isHTML: false)
        return mc
    }
    #endif

    #if os(macOS)
    /// Opens the default email client via mailto URL.
    static func openMailClient() {
        guard let url = mailtoURL() else { return }
        NSWorkspace.shared.open(url)
    }
    #endif

    // MARK: - GitHub Issue

    /// Opens a pre-filled GitHub issue in the browser.
    static func openGitHubIssue() {
        let body = """
        **Describe the issue**
        <!-- A clear description of what happened -->

        **Steps to reproduce**
        1.
        2.
        3.

        **Expected behavior**
        <!-- What you expected to happen -->

        \(diagnosticsBlock)
        """

        var components = URLComponents(string: "https://github.com/\(githubRepo)/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: ""),
            URLQueryItem(name: "body", value: body),
        ]

        guard let url = components.url else { return }

        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}

// MARK: - iOS Mail Compose Wrapper

#if os(iOS)

/// SwiftUI wrapper for `MFMailComposeViewController`.
struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mc = FeedbackHelper.makeMailCompose()
        mc.mailComposeDelegate = context.coordinator
        return mc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        init(_ parent: MailComposeView) { self.parent = parent }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            parent.dismiss()
        }
    }
}
#endif
