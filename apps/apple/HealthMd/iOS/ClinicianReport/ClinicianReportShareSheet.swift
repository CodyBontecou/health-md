import SwiftUI
import UIKit

/// Retains the artifact lease for the complete lifetime of UIActivityViewController.
struct ClinicianReportShareSheet: UIViewControllerRepresentable {
    let artifact: ExportArtifactFile
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [artifact.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async {
                onComplete(completed)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
