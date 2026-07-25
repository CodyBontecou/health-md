import SwiftUI
import UniformTypeIdentifiers

struct ExportFolderBrowser: UIViewControllerRepresentable {
    let initialDirectoryURL: URL
    let onFileSelected: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = Self.makeDocumentPicker(initialDirectoryURL: initialDirectoryURL)
        picker.delegate = context.coordinator
        return picker
    }

    static func makeDocumentPicker(
        initialDirectoryURL: URL
    ) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data],
            asCopy: false
        )
        picker.directoryURL = initialDirectoryURL
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFileSelected: onFileSelected, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFileSelected: (URL) -> Void
        let onCancel: () -> Void

        init(onFileSelected: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onFileSelected = onFileSelected
            self.onCancel = onCancel
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onFileSelected(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let onFolderSelected: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Use open-in-place so third-party File Provider locations (e.g. Google Drive)
        // can offer folder selection instead of being shown as unavailable.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFolderSelected: onFolderSelected)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFolderSelected: (URL) -> Void

        init(onFolderSelected: @escaping (URL) -> Void) {
            self.onFolderSelected = onFolderSelected
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onFolderSelected(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // User cancelled - do nothing
        }
    }
}
