import Foundation

struct ProfileRepository {
    private let fileManager: FileManager
    private let fileURL: URL
    private let readData: (URL) throws -> Data
    private let writeData: (Data, URL) throws -> Void

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        writeData: @escaping (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        },
        readData: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.fileManager = fileManager
        self.readData = readData
        self.writeData = writeData

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = baseURL
                .appending(path: "ProfileBrowser", directoryHint: .isDirectory)
                .appending(path: "profiles.json", directoryHint: .notDirectory)
        }
    }

    func load() throws -> [BrowserProfile] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try readData(fileURL)
        return try Self.makeDecoder().decode([BrowserProfile].self, from: data)
    }

    func save(_ profiles: [BrowserProfile]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(profiles)
        try writeData(data, fileURL)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
