import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [BrowserProfile] = []
    var presentedError: PresentedError?
    var busyProfileID: UUID?

    let credentialVault: CredentialVault
    let websiteDataStores: WebsiteDataStoreManager

    private let profileRepository: ProfileRepository

    init(
        profileRepository: ProfileRepository = ProfileRepository(),
        credentialVault: CredentialVault = CredentialVault(),
        websiteDataStores: WebsiteDataStoreManager = WebsiteDataStoreManager()
    ) {
        self.profileRepository = profileRepository
        self.credentialVault = credentialVault
        self.websiteDataStores = websiteDataStores
        reloadProfiles()
    }

    var sortedProfiles: [BrowserProfile] {
        profiles.sorted { lhs, rhs in
            switch (lhs.lastOpenedAt, rhs.lastOpenedAt) {
            case let (left?, right?):
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    func addProfile(name: String, homePage: URL, userAgent: String, color: ProfileColor) throws {
        let profile = BrowserProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            userAgent: userAgent.trimmingCharacters(in: .whitespacesAndNewlines),
            homePage: homePage,
            color: color
        )
        profiles.append(profile)
        try persist()
    }

    func addImportedProfile(_ profile: BrowserProfile) throws {
        profiles.append(profile)
        try persist()
    }

    func updateProfile(_ updatedProfile: BrowserProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) else {
            throw ProfileError.notFound
        }
        var value = updatedProfile
        value.updatedAt = .now
        profiles[index] = value
        try persist()
    }

    func markOpened(_ profile: BrowserProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].lastOpenedAt = .now
        profiles[index].updatedAt = .now
        do {
            try persist()
        } catch {
            present(error)
        }
    }

    func clearWebsiteData(for profile: BrowserProfile) async {
        busyProfileID = profile.id
        await websiteDataStores.clearWebsiteData(for: profile)
        busyProfileID = nil
    }

    func deleteProfile(_ profile: BrowserProfile) async {
        busyProfileID = profile.id
        defer { busyProfileID = nil }

        do {
            try await websiteDataStores.deleteDataStore(for: profile)
            try credentialVault.deleteAll(profileID: profile.id)
            profiles.removeAll { $0.id == profile.id }
            try persist()
        } catch {
            present(error)
        }
    }

    func present(_ error: Error) {
        presentedError = PresentedError(message: error.localizedDescription)
    }

    private func reloadProfiles() {
        do {
            profiles = try profileRepository.load()
        } catch {
            present(error)
        }
    }

    private func persist() throws {
        try profileRepository.save(profiles)
    }
}

struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
}

enum ProfileError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "找不到这个浏览器环境。"
        }
    }
}
