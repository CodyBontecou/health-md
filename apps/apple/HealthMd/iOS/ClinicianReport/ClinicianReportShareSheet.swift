import SwiftUI
import UIKit

/// Retains the artifact lease for the complete lifetime of UIActivityViewController.
struct ClinicianReportShareSheet: UIViewControllerRepresentable {
    let artifact: ExportArtifactFile
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [artifact.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async(execute: onComplete)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
