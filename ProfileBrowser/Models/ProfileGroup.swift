import Foundation

/// A group projection used by the UI.  Group metadata is persisted alongside
/// each member in the existing profiles.json format, so no second store or
/// migration file is required.
///
/// Earlier releases derived groups directly from `BrowserProfile.groupName`
/// and therefore had no identity or per-group metadata.  The UUID and
/// optional code/emoji fields provide a stable identity for navigation while
/// remaining compatible with those legacy profiles.
struct ProfileGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var code: String?
    var emoji: String?
    var profiles: [BrowserProfile]

    /// Designated initializer used by AppModel's grouped projection.
    init(
        id: UUID,
        name: String,
        code: String? = nil,
        emoji: String? = nil,
        profiles: [BrowserProfile]
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.emoji = emoji
        self.profiles = profiles
    }

    /// Compatibility initializer for callers that still construct a group
    /// from a name and profile list.  New callers should pass the stable ID
    /// carried by member profiles.
    init(name: String, profiles: [BrowserProfile]) {
        self.init(id: UUID(), name: name, profiles: profiles)
    }

    /// The emoji shown on group cards.  A folder emoji keeps legacy groups
    /// visually identifiable until the user chooses a custom icon.
    var displayEmoji: String {
        let value = emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "📁" : value
    }

    /// A trimmed code suitable for compact labels; nil when no code exists.
    var displayCode: String? {
        let value = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var color: ProfileColor {
        profiles.first?.color ?? .indigo
    }
}
