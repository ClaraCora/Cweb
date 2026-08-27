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

    func addProfile(
        name: String,
        groupName: String? = nil,
        homePage: URL,
        userAgent: String,
        color: ProfileColor,
        autofillUsername: String? = nil,
        autofillPassword: String? = nil
    ) throws {
        let profile = BrowserProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            groupName: normalizedOptional(groupName),
            userAgent: userAgent.trimmingCharacters(in: .whitespacesAndNewlines),
            homePage: homePage,
            color: color
        )
        profiles.append(profile)
        try persist()
        try saveAutofillCredentialIfNeeded(
            profileID: profile.id,
            homePage: profile.homePage,
            username: autofillUsername,
            password: autofillPassword
        )
    }

    func addImportedProfile(_ profile: BrowserProfile) throws {
        profiles.append(profile)
        try persist()
    }

    func duplicateProfile(_ profile: BrowserProfile) throws {
        guard profiles.contains(where: { $0.id == profile.id }) else {
            throw ProfileError.notFound
        }

        let credentials = try credentialVault.credentials(profileID: profile.id)
        let duplicate = BrowserProfile(
            name: nextDuplicateName(for: profile.name),
            groupName: profile.groupName,
            userAgent: profile.userAgent,
            homePage: profile.homePage,
            color: profile.color,
            cachedBalance: profile.cachedBalance
        )

        profiles.append(duplicate)
        do {
            try persist()
            for credential in credentials {
                try credentialVault.save(
                    StoredCredential(
                        profileID: duplicate.id,
                        origin: credential.origin,
                        username: credential.username,
                        password: credential.password,
                        label: credential.label,
                        createdAt: credential.createdAt,
                        updatedAt: credential.updatedAt
                    )
                )
            }
        } catch {
            profiles.removeAll { $0.id == duplicate.id }
            try? persist()
            try? credentialVault.deleteAll(profileID: duplicate.id)
            throw error
        }
    }

    func balance(for profile: BrowserProfile) -> String? {
        profile.cachedBalance
    }

    func refreshBalance(for session: BrowserSession) async {
        for _ in 0..<24 {
            guard !Task.isCancelled else { return }
            if let value = try? await session.readAccountBalance(), !value.isEmpty {
                saveCachedBalance(value, for: session.profile.id)
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    func updateProfile(
        _ updatedProfile: BrowserProfile,
        autofillUsername: String? = nil,
        autofillPassword: String? = nil
    ) throws {
        guard let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) else {
            throw ProfileError.notFound
        }
        var value = updatedProfile
        value.groupName = normalizedOptional(value.groupName)
        value.updatedAt = .now
        profiles[index] = value
        try persist()
        try saveAutofillCredentialIfNeeded(
            profileID: value.id,
            homePage: value.homePage,
            username: autofillUsername,
            password: autofillPassword
        )
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

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nextDuplicateName(for name: String) -> String {
        let baseName = "\(name) 副本"
        let existingNames = Set(profiles.map(\.name))
        guard existingNames.contains(baseName) else { return baseName }

        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)") {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    private func saveCachedBalance(_ balance: String, for profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        guard profiles[index].cachedBalance != balance else { return }
        profiles[index].cachedBalance = balance
        do {
            try profileRepository.save(profiles)
        } catch {
            present(error)
        }
    }

    private func saveAutofillCredentialIfNeeded(
        profileID: UUID,
        homePage: URL,
        username: String?,
        password: String?
    ) throws {
        let normalizedUsername = normalizedOptional(username)
        let normalizedPassword = password?.isEmpty == false ? password : nil
        guard normalizedUsername != nil || normalizedPassword != nil else { return }
        guard let normalizedUsername, let normalizedPassword else {
            throw ProfileError.autofillCredentialsIncomplete
        }
        guard let origin = WebOrigin(url: homePage) else {
            throw ProfileError.invalidAutofillOrigin
        }

        let existing = try credentialVault.credentials(profileID: profileID, origin: origin).first
        let credential = StoredCredential(
            id: existing?.id ?? UUID(),
            profileID: profileID,
            origin: origin,
            username: normalizedUsername,
            password: normalizedPassword,
            label: existing?.label ?? "自动填充",
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
        try credentialVault.save(credential)
    }
}

struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
}

enum ProfileError: LocalizedError {
    case notFound
    case autofillCredentialsIncomplete
    case invalidAutofillOrigin

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "找不到这个浏览器环境。"
        case .autofillCredentialsIncomplete:
            return "自动填充账号和密码需要同时填写，或都留空。"
        case .invalidAutofillOrigin:
            return "主页网址无法用于保存自动填充凭据。"
        }
    }
}
