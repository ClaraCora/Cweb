import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [BrowserProfile] = []
    var presentedError: PresentedError?
    var busyProfileID: UUID?
    var busyGroupName: String?

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
        // The persisted array is the user's explicit order. Opening an environment
        // updates its metadata, but must never move it in the list.
        profiles
    }

    var profileGroups: [ProfileGroup] {
        var groupedProfiles: [String: [BrowserProfile]] = [:]
        var groupOrder: [String] = []

        for profile in sortedProfiles {
            let groupName = profile.displayGroupName
            if groupedProfiles[groupName] == nil {
                groupOrder.append(groupName)
            }
            groupedProfiles[groupName, default: []].append(profile)
        }

        return groupOrder.compactMap { name in
            guard let profiles = groupedProfiles[name] else { return nil }
            return ProfileGroup(name: name, profiles: profiles)
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

    func resetCachedBalance(for profile: BrowserProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileError.notFound
        }
        guard profiles[index].cachedBalance != "$0.00" else { return }

        profiles[index].cachedBalance = "$0.00"
        profiles[index].updatedAt = .now
        try persist()
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

    func moveProfiles(_ profileIDs: [UUID], fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        guard !offsets.isEmpty else { return }

        let profileIDSet = Set(profileIDs)
        guard profileIDSet.count == profileIDs.count,
              profileIDs.allSatisfy({ profileID in profiles.contains(where: { $0.id == profileID }) }) else {
            throw ProfileError.notFound
        }

        let oldProfiles = profiles
        let movingIDs = offsets.sorted().compactMap { profileIDs[safe: $0] }
        guard movingIDs.count == offsets.count else { return }

        var remainingIDs = profileIDs.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        let insertionIndex = max(0, min(remainingIDs.count, destination - removedBeforeDestination))
        remainingIDs.insert(contentsOf: movingIDs, at: insertionIndex)

        let profilesByID = Dictionary(uniqueKeysWithValues: oldProfiles.map { ($0.id, $0) })
        var reordered = profiles
        var replacementIndex = 0
        for index in reordered.indices where profileIDSet.contains(reordered[index].id) {
            guard replacementIndex < remainingIDs.count,
                  let replacement = profilesByID[remainingIDs[replacementIndex]] else { continue }
            reordered[index] = replacement
            replacementIndex += 1
        }

        profiles = reordered
        do {
            try persist()
        } catch {
            profiles = oldProfiles
            throw error
        }
    }

    func clearWebsiteData(for profile: BrowserProfile) async {
        busyProfileID = profile.id
        await websiteDataStores.clearWebsiteData(for: profile)
        busyProfileID = nil
    }

    func deleteProfile(_ profile: BrowserProfile) async {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }

        busyProfileID = profile.id
        defer { busyProfileID = nil }

        do {
            try credentialVault.deleteAll(profileID: profile.id)
            profiles.removeAll { $0.id == profile.id }
            try persist()

            // Do not call WKWebsiteDataStore.remove(forIdentifier:) here. WebKit
            // can still retain the store while SwiftUI dismisses its UI, which
            // has caused an application crash. Clearing existing site data is
            // safe and the store is no longer reachable after this point.
            await websiteDataStores.clearExistingWebsiteData(for: profile)
        } catch {
            present(error)
        }
    }

    func deleteProfiles(inGroupNamed groupName: String) async {
        let profilesToDelete = profiles.filter { $0.displayGroupName == groupName }
        guard !profilesToDelete.isEmpty else { return }

        busyGroupName = groupName
        defer { busyGroupName = nil }

        do {
            for profile in profilesToDelete {
                try credentialVault.deleteAll(profileID: profile.id)
            }
            let profileIDs = Set(profilesToDelete.map(\.id))
            profiles.removeAll { profileIDs.contains($0.id) }
            try persist()

            // Keep the same WebKit-safe cleanup path as single-profile deletion.
            // The stores are no longer reachable once their profiles are removed.
            for profile in profilesToDelete {
                await websiteDataStores.clearExistingWebsiteData(for: profile)
            }
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
