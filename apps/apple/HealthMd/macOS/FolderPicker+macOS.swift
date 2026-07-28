#if os(macOS)
import AppKit

/// macOS folder picker using NSOpenPanel.
/// Much simpler than iOS — no UIViewControllerRepresentable needed.
struct MacFolderPicker {

    /// Shows an NSOpenPanel to pick a directory.
    /// Calls the completion handler with the selected URL on the main thread.
    static func show(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Export Folder"
        panel.prompt = "Choose"
        panel.message = "Select the folder where Health.md will export your health data (e.g. your Obsidian vault)"

        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}

#endif
