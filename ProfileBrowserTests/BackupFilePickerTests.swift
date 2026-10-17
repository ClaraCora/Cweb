import Foundation
import Testing
import UIKit
@testable import ProfileBrowser

@MainActor
struct BackupFilePickerTests {
    @Test
    func copiesSelectedDocumentAndDeliversOneSelection() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ProfileBrowser-backup.json")
        var selections: [URL?] = []
        let picker = BackupFilePicker { selections.append($0) }
        let coordinator = picker.makeCoordinator()
        let controller = BackupFilePicker.makeDocumentPicker(delegate: coordinator)

        // Copy mode avoids requiring the file provider to support opening the source in place.
        #expect(controller.documentPickerMode == .import)
        #expect(!controller.allowsMultipleSelection)
        coordinator.documentPicker(controller, didPickDocumentsAt: [url])
        coordinator.documentPickerWasCancelled(controller)
        coordinator.documentPicker(controller, didPickDocumentsAt: [url])

        #expect(selections.count == 1)
        let selection = try #require(selections.first)
        #expect(selection == url)
    }

    @Test
    func cancellationCompletesWithoutStartingAnImport() throws {
        var selections: [URL?] = []
        let picker = BackupFilePicker { selections.append($0) }
        let coordinator = picker.makeCoordinator()
        let controller = BackupFilePicker.makeDocumentPicker(delegate: coordinator)

        coordinator.documentPickerWasCancelled(controller)
        coordinator.documentPickerWasCancelled(controller)

        #expect(selections.count == 1)
        let selection = try #require(selections.first)
        #expect(selection == nil)
    }

    @Test
    func canSelectAgainAfterCancellingPreviousPicker() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ProfileBrowser-backup")
        var selections: [URL?] = []
        let picker = BackupFilePicker { selections.append($0) }
        let firstCoordinator = picker.makeCoordinator()
        let firstController = BackupFilePicker.makeDocumentPicker(delegate: firstCoordinator)
        firstCoordinator.documentPickerWasCancelled(firstController)

        let nextCoordinator = picker.makeCoordinator()
        let nextController = BackupFilePicker.makeDocumentPicker(delegate: nextCoordinator)
        nextCoordinator.documentPicker(nextController, didPickDocumentsAt: [url])

        #expect(selections.count == 2)
        let selection = try #require(selections.last)
        #expect(selection == url)
    }
}
