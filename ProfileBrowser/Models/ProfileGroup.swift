import Foundation

struct ProfileGroup: Identifiable, Hashable, Sendable {
    let name: String
    let profiles: [BrowserProfile]

    var id: String { name }

    var color: ProfileColor {
        profiles.first?.color ?? .indigo
    }
}
