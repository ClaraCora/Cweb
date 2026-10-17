import SwiftUI
import UIKit

@MainActor
struct BackupFilePicker: UIViewControllerRepresentable {
    let onSelection: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        Self.makeDocumentPicker(delegate: context.coordinator)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    static func makeDocumentPicker(delegate: UIDocumentPickerDelegate) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: BackupDocument.importableContentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = delegate
        return picker
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onSelection: (URL?) -> Void
        private var hasCompleted = false

        init(onSelection: @escaping (URL?) -> Void) {
            self.onSelection = onSelection
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            complete(with: urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            complete(with: nil)
        }

        private func complete(with url: URL?) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onSelection(url)
        }
    }
}
