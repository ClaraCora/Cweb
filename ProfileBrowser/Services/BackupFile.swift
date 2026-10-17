import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static let defaultFilename = "ProfileBrowser-backup.json"
    static var readableContentTypes: [UTType] { [.json, .data] }
    static var writableContentTypes: [UTType] { [.json] }

    // Old exports have no extension, so let the picker offer generic file items.
    static var importableContentTypes: [UTType] { [.item] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupError.invalidFormat
        }
        try BackupService.validateBackupData(data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupImportFile: Sendable {
    let filename: String
    let data: Data

    init(contentsOf url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var readResult: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            readResult = Result {
                let values = try readableURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { throw BackupError.invalidFormat }
                return try Data(contentsOf: readableURL)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw BackupError.invalidFormat }

        let data = try readResult.get()
        try BackupService.validateBackupData(data)
        self.filename = url.lastPathComponent
        self.data = data
    }
}
