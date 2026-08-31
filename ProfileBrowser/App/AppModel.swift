import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [BrowserProfile] = []
    private(set) var socksProxies: [SocksProxy] = []
    private(set) var proxyPresets: [SocksProxyPreset] = []
    var presentedError: PresentedError?
    var busyProfileID: UUID?
    var busyGroupName: String?

    let credentialVault: CredentialVault
    let websiteDataStores: WebsiteDataStoreManager

    private let profileRepository: ProfileRepository
    private let socksProxyRepository: SocksProxyRepository
    private let socksProxyImportService: SocksProxyImportService
    private let socksProxyValidationService: SocksProxyValidationService

    init(
        profileRepository: ProfileRepository = ProfileRepository(),
        credentialVault: CredentialVault = CredentialVault(),
        websiteDataStores: WebsiteDataStoreManager = WebsiteDataStoreManager(),
        socksProxyRepository: SocksProxyRepository = SocksProxyRepository(),
        socksProxyImportService: SocksProxyImportService = SocksProxyImportService(),
        socksProxyValidationService: SocksProxyValidationService = SocksProxyValidationService()
    ) {
        self.profileRepository = profileRepository
        self.credentialVault = credentialVault
        self.websiteDataStores = websiteDataStores
        self.socksProxyRepository = socksProxyRepository
        self.socksProxyImportService = socksProxyImportService
        self.socksProxyValidationService = socksProxyValidationService
        reloadProfiles()
        reloadSocksProxies()
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
        socksProxyNumber: Int? = nil,
        autofillUsername: String? = nil,
        autofillPassword: String? = nil
    ) throws {
        let profile = BrowserProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            groupName: normalizedOptional(groupName),
            userAgent: userAgent.trimmingCharacters(in: .whitespacesAndNewlines),
            homePage: homePage,
            color: color,
            socksProxyNumber: normalizedProxyNumber(socksProxyNumber)
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
            cachedBalance: profile.cachedBalance,
            socksProxyNumber: profile.socksProxyNumber
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
        value.socksProxyNumber = normalizedProxyNumber(value.socksProxyNumber)
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

    // MARK: - SOCKS proxies

    /// Returns the proxy currently occupying a profile's volatile display
    /// number. A profile deliberately stores the number, not this record's ID.
    func socksProxy(for profile: BrowserProfile) -> SocksProxy? {
        guard let number = profile.socksProxyNumber else { return nil }
        return SocksProxyValidationService.proxy(forDisplayNumber: number, in: socksProxies)
    }

    func addSocksProxy(_ proxy: SocksProxy) throws {
        socksProxies = try socksProxyRepository.appendUnique([proxy])
    }

    func updateSocksProxy(_ proxy: SocksProxy) throws {
        guard let existing = socksProxies.first(where: { $0.id == proxy.id }) else {
            throw SocksProxyError.notFound
        }

        var value = proxy
        // Any endpoint or credential change invalidates the previous probe.
        // `identityKey` intentionally omits the password so feed refreshes can
        // retain a record ID when credentials rotate; editing a password here
        // must still force a fresh validation before the proxy is considered
        // usable again.
        let contentChanged = existing.identityKey != proxy.identityKey
            || existing.scheme != proxy.scheme
            || existing.password != proxy.password
        if contentChanged {
            value.latencyMilliseconds = nil
            value.status = .untested
            value.lastCheckedAt = nil
            value.validationMessage = nil
        }
        socksProxies = try socksProxyRepository.upsert(value)
    }

    func deleteSocksProxy(_ proxy: SocksProxy) throws {
        guard socksProxies.contains(where: { $0.id == proxy.id }) else {
            throw SocksProxyError.notFound
        }
        try socksProxyRepository.delete(proxyID: proxy.id)
        socksProxies.removeAll { $0.id == proxy.id }
    }

    func clearSocksProxies() throws {
        try socksProxyRepository.removeAll()
        socksProxies = []
    }

    func importSocksProxies(from url: URL) async throws {
        let imported = try await socksProxyImportService.fetch(from: url)
        guard !imported.isEmpty else { return }
        socksProxies = try socksProxyRepository.appendUnique(imported)
    }

    func validateSocksProxies() async throws {
        guard !socksProxies.isEmpty else { return }
        let validated = await socksProxyValidationService.validateAndSort(socksProxies)
        // Keep only proxies that completed the real SOCKS CONNECT probe, then
        // bound the ranked list so stale feed entries cannot grow the app's
        // proxy store indefinitely. Display numbers are recalculated from this
        // retained list after every batch validation.
        let retained = Array(validated.filter { $0.status == .available }.prefix(30))
        try socksProxyRepository.save(retained)
        socksProxies = retained
    }

    func validateSocksProxy(_ proxy: SocksProxy) async throws {
        guard socksProxies.contains(where: { $0.id == proxy.id }) else {
            throw SocksProxyError.notFound
        }

        let result = await socksProxyValidationService.validate(proxy)
        let updated = socksProxies.map { $0.applying(result) }
        let ranked = SocksProxyValidationService.sort(updated)
        try socksProxyRepository.save(ranked)
        socksProxies = ranked
    }

    func updateOrAddProxyPreset(_ preset: SocksProxyPreset) throws {
        proxyPresets = try socksProxyRepository.upsertPreset(preset)
    }

    func updateProxyPreset(_ preset: SocksProxyPreset) throws {
        guard proxyPresets.contains(where: { $0.id == preset.id }) else {
            throw SocksProxyError.presetNotFound
        }
        proxyPresets = try socksProxyRepository.upsertPreset(preset)
    }

    func deleteProxyPreset(_ preset: SocksProxyPreset) throws {
        guard proxyPresets.contains(where: { $0.id == preset.id }) else {
            throw SocksProxyError.presetNotFound
        }
        try socksProxyRepository.delete(presetID: preset.id)
        proxyPresets.removeAll { $0.id == preset.id }
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
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        guard !isDestructiveOperationInProgress else { return }

        busyProfileID = profile.id
        defer { busyProfileID = nil }
        await websiteDataStores.clearWebsiteData(for: profile)
    }

    func deleteProfile(_ profile: BrowserProfile) async {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        guard !isDestructiveOperationInProgress else { return }

        busyProfileID = profile.id
        defer { busyProfileID = nil }

        do {
            // Do not access WKWebsiteDataStore during deletion. WebKit can keep
            // a page's store alive while SwiftUI tears down the destination,
            // and native failures here cannot be recovered with do/catch. The
            // deleted store ID is never reused, so its data is no longer
            // reachable by this app or by a newly created environment.
            try deleteProfilesAtomically([profile])
        } catch {
            present(error)
        }
    }

    func deleteProfiles(inGroupNamed groupName: String) async {
        let profilesToDelete = profiles.filter { $0.displayGroupName == groupName }
        guard !profilesToDelete.isEmpty else { return }
        guard !isDestructiveOperationInProgress else { return }

        busyGroupName = groupName
        defer { busyGroupName = nil }

        do {
            // Keep deletion independent from WebKit lifecycle teardown. Each
            // removed profile has a unique store ID that will never be reused.
            try deleteProfilesAtomically(profilesToDelete)
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

    private func reloadSocksProxies() {
        do {
            socksProxies = try socksProxyRepository.load()
            proxyPresets = try socksProxyRepository.loadPresets()
        } catch {
            present(error)
        }
    }

    private func persist() throws {
        try profileRepository.save(profiles)
    }

    private var isDestructiveOperationInProgress: Bool {
        busyProfileID != nil || busyGroupName != nil
    }

    private func deleteProfilesAtomically(_ profilesToDelete: [BrowserProfile]) throws {
        guard !profilesToDelete.isEmpty else { return }

        let oldProfiles = profiles
        let credentials = try profilesToDelete.reduce(into: [StoredCredential]()) { result, profile in
            result.append(contentsOf: try credentialVault.credentials(profileID: profile.id))
        }
        let profileIDs = Set(profilesToDelete.map(\.id))

        profiles.removeAll { profileIDs.contains($0.id) }
        do {
            try persist()
        } catch {
            profiles = oldProfiles
            throw error
        }

        do {
            for profile in profilesToDelete {
                try credentialVault.deleteAll(profileID: profile.id)
            }
        } catch {
            profiles = oldProfiles
            try? persist()
            for credential in credentials {
                try? credentialVault.save(credential)
            }
            throw error
        }
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedProxyNumber(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
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

enum SocksProxyError: LocalizedError {
    case notFound
    case presetNotFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "找不到这个 SOCKS 代理。"
        case .presetNotFound:
            return "找不到这个代理预设链接。"
        }
    }
}
