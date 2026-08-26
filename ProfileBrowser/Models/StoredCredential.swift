import Foundation

struct StoredCredential: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let profileID: UUID
    var origin: WebOrigin
    var username: String
    var password: String
    var label: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        profileID: UUID,
        origin: WebOrigin,
        username: String,
        password: String,
        label: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.profileID = profileID
        self.origin = origin
        self.username = username
        self.password = password
        self.label = label
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
