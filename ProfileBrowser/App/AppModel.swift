import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [BrowserProfile] = []
    private(set) var socksProxies: [SocksProxy] = []
    private(set) var proxyPresets: [SocksProxyPreset] = []
    private(set) var socksProxyValidationSettings: SocksProxyValidationSettings = .defaults
    private(set) var isLoadingProfiles = true
    private(set) var isProfileStoreAvailable = false
    var presentedError: PresentedError?
    var busyProfileID: UUID?
    var busyGroupName: String?

    let credentialVault: CredentialVault
    let websiteDataStores: WebsiteDataStoreManager

    private let profileRepository: ProfileRepository
    private let socksProxyRepository: SocksProxyRepository
    private let socksProxyImportService: SocksProxyImportService
    private let socksProxyValidationServiceOverride: SocksProxyValidationService?

    init(
        profileRepository: ProfileRepository = ProfileRepository(),
        credentialVault: CredentialVault = CredentialVault(),
        websiteDataStores: WebsiteDataStoreManager = WebsiteDataStoreManager(),
        socksProxyRepository: SocksProxyRepository = SocksProxyRepository(),
        socksProxyImportService: SocksProxyImportService = SocksProxyImportService(),
        socksProxyValidationService: SocksProxyValidationService? = nil
    ) {
        self.profileRepository = profileRepository
        self.credentialVault = credentialVault
        self.websiteDataStores = websiteDataStores
        self.socksProxyRepository = socksProxyRepository
        self.socksProxyImportService = socksProxyImportService
        self.socksProxyValidationServiceOverride = socksProxyValidationService
        reloadProfiles()
        if isProfileStoreAvailable {
            migrateGroupMetadataIfNeeded()
        }
        reloadSocksProxyValidationSettings()
        reloadSocksProxies()
    }

    var sortedProfiles: [BrowserProfile] {
        // The persisted array is the user's explicit order. Opening an environment
        // updates its metadata, but must never move it in the list.
        profiles
    }

    /// Retries a transient startup read without ever treating a failed read as
    /// an empty store.  The first retry is immediate; later retries cover the
    /// short window in which iOS can still be restoring protected file access.
    func retryLoadingProfiles() async {
        guard !isProfileStoreAvailable else { return }
        isLoadingProfiles = true

        var lastError: Error?
        for delay in [UInt64(0), 150_000_000, 350_000_000, 700_000_000] {
            guard !Task.isCancelled else {
                isLoadingProfiles = false
                return
            }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else {
                    isLoadingProfiles = false
                    return
                }
            }

            do {
                profiles = try profileRepository.load()
                isProfileStoreAvailable = true
                isLoadingProfiles = false
                migrateGroupMetadataIfNeeded()
                return
            } catch {
                lastError = error
            }
        }

        isLoadingProfiles = false
        let detail = lastError?.localizedDescription ?? "未知错误"
        presentedError = PresentedError(
            message: "环境数据暂时无法读取，App 已停止写入以保护原文件。请稍后重试。\n\n原因：\(detail)"
        )
    }

    var profileGroups: [ProfileGroup] {
        // Group identity is persisted on every profile so a rename does not
        // invalidate a navigation destination that is already on screen.
        // The fallback key keeps this projection safe for a profile loaded
        // from an older file before migration has completed.
        var groupedProfiles: [String: [BrowserProfile]] = [:]
        var groupOrder: [String] = []

        for profile in sortedProfiles {
            let key = profile.groupID.map { "id:\($0.uuidString)" }
                ?? "name:\(profile.displayGroupName)"
            if groupedProfiles[key] == nil {
                groupOrder.append(key)
            }
            groupedProfiles[key, default: []].append(profile)
        }

        return groupOrder.compactMap { key in
            guard let profiles = groupedProfiles[key], let first = profiles.first else {
                return nil
            }
            return ProfileGroup(
                // A legacy profile that could not be migrated still gets a
                // deterministic in-memory identity for this projection.
                id: first.groupID ?? first.id,
                name: first.displayGroupName,
                code: first.groupCode,
                emoji: first.groupEmoji,
                profiles: profiles
            )
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
        let normalizedGroupName = normalizedOptional(groupName)
        let group = groupMetadata(named: normalizedGroupName)
        let profile = BrowserProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            groupName: normalizedGroupName,
            groupID: group?.id ?? UUID(),
            groupCode: group?.code,
            groupEmoji: group?.emoji,
            userAgent: userAgent.trimmingCharacters(in: .whitespacesAndNewlines),
            homePage: homePage,
            color: color,
            socksProxyNumber: normalizedProxyNumber(socksProxyNumber)
        )
        let oldProfiles = profiles
        profiles.append(profile)
        do {
            try persist()
        } catch {
            profiles = oldProfiles
            throw error
        }
        try saveAutofillCredentialIfNeeded(
            profileID: profile.id,
            homePage: profile.homePage,
            username: autofillUsername,
            password: autofillPassword
        )
    }

    func addImportedProfile(_ profile: BrowserProfile) throws {
        var value = profile
        assignGroupMetadata(to: &value)
        let oldProfiles = profiles
        profiles.append(value)
        do {
            try persist()
        } catch {
            profiles = oldProfiles
            throw error
        }
    }

    func duplicateProfile(_ profile: BrowserProfile) throws {
        guard profiles.contains(where: { $0.id == profile.id }) else {
            throw ProfileError.notFound
        }

        let credentials = try credentialVault.credentials(profileID: profile.id)
        let duplicate = BrowserProfile(
            name: nextDuplicateName(for: profile.name),
            groupName: profile.groupName,
            groupID: profile.groupID,
            groupCode: profile.groupCode,
            groupEmoji: profile.groupEmoji,
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

    /// Updates the metadata shared by a group and keeps every member attached
    /// to the same stable group identity.  Profile names that were derived
    /// from the old group name are updated as well; custom names are left
    /// untouched so a group rename cannot erase deliberate labels.
    func updateGroup(
        id: UUID,
        name: String,
        code: String? = nil,
        emoji: String? = nil
    ) throws {
        guard let existingGroup = profileGroups.first(where: { $0.id == id }) else {
            throw ProfileError.groupNotFound
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ProfileError.groupNameEmpty
        }
        let nameTaken = profileGroups.contains {
            $0.id != id && $0.name == normalizedName
        }
        guard !nameTaken else {
            throw ProfileError.groupNameAlreadyExists
        }

        let normalizedCode = normalizedOptional(code)
        let normalizedEmoji = normalizedGroupEmoji(emoji)
        let oldProfiles = profiles
        let oldName = existingGroup.name

        for index in profiles.indices {
            let belongsToGroup = profiles[index].groupID == id
                || (profiles[index].groupID == nil
                    && profiles[index].displayGroupName == oldName)
            guard belongsToGroup else { continue }

            profiles[index].groupID = id
            profiles[index].groupName = normalizedName
            profiles[index].groupCode = normalizedCode
            profiles[index].groupEmoji = normalizedEmoji
            profiles[index].name = linkedProfileName(
                profiles[index].name,
                replacingGroupName: oldName,
                with: normalizedName
            )
            profiles[index].updatedAt = .now
        }

        do {
            try persist()
        } catch {
            profiles = oldProfiles
            throw error
        }
    }

    /// More descriptive alias for callers that treat this as a rename action.
    func renameGroup(
        id: UUID,
        name: String,
        code: String? = nil,
        emoji: String? = nil
    ) throws {
        try updateGroup(id: id, name: name, code: code, emoji: emoji)
    }

    func updateProfile(
        _ updatedProfile: BrowserProfile,
        autofillUsername: String? = nil,
        autofillPassword: String? = nil
    ) throws {
        guard let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) else {
            throw ProfileError.notFound
        }
        let previousProfile = profiles[index]
        var value = updatedProfile
        value.groupName = normalizedOptional(value.groupName)
        assignGroupMetadata(
            to: &value,
            preserving: previousProfile,
            whenGroupNameUnchanged: value.groupName == previousProfile.groupName
        )
        value.socksProxyNumber = normalizedProxyNumber(value.socksProxyNumber)
        value.updatedAt = .now
        profiles[index] = value
        do {
            try persist()
        } catch {
            profiles[index] = previousProfile
            throw error
        }
        try saveAutofillCredentialIfNeeded(
            profileID: value.id,
            homePage: value.homePage,
            username: autofillUsername,
            password: autofillPassword
        )
    }

    // MARK: - SOCKS proxies

    /// The single source of truth for volatile display numbers. Management,
    /// profile editing, and browser launch must all use this ranking so a
    /// number never resolves to different proxies in different screens.
    var rankedSocksProxies: [SocksProxyRanking] {
        ranked(socksProxies, using: socksProxyValidationSettings.sortMode)
    }

    /// Returns the proxy currently occupying a profile's volatile display
    /// number. A profile deliberately stores the number, not this record's ID.
    func socksProxy(for profile: BrowserProfile) -> SocksProxy? {
        guard let number = profile.socksProxyNumber else { return nil }
        return socksProxy(forDisplayNumber: number)
    }

    func socksProxy(forDisplayNumber number: Int) -> SocksProxy? {
        guard number > 0 else { return nil }
        return rankedSocksProxies.first(where: { $0.number == number })?.proxy
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

        let settings = socksProxyValidationSettings.normalized
        let originalOrder = socksProxies
        let service = socksProxyValidationService(for: settings)
        let results = await service.validate(
            originalOrder,
            maxConcurrent: settings.maxConcurrent
        )
        let resultsByID = Dictionary(
            uniqueKeysWithValues: results.map { ($0.proxyID, $0) }
        )
        let validatedInOriginalOrder = originalOrder.map { proxy in
            guard let result = resultsByID[proxy.id] else { return proxy }
            return proxy.applying(result)
        }

        let candidates = settings.retainOnlyAvailable
            ? validatedInOriginalOrder.filter { $0.status == .available }
            : validatedInOriginalOrder
        let candidatesByRank = ordered(candidates, using: settings.sortMode)
        let selected: [SocksProxy]
        if settings.maxRetainedCount == 0 {
            selected = candidatesByRank
        } else {
            selected = Array(candidatesByRank.prefix(settings.maxRetainedCount))
        }

        // Persist the retained records in their pre-validation order. Ranking
        // remains a derived view, allowing the user to switch back to input
        // order without a previous latency sort having destroyed that order.
        let selectedIDs = Set(selected.map(\.id))
        let retained = validatedInOriginalOrder.filter { selectedIDs.contains($0.id) }
        try socksProxyRepository.save(retained)
        socksProxies = retained
    }

    func validateSocksProxy(_ proxy: SocksProxy) async throws {
        guard socksProxies.contains(where: { $0.id == proxy.id }) else {
            throw SocksProxyError.notFound
        }

        let service = socksProxyValidationService(for: socksProxyValidationSettings)
        let result = await service.validate(proxy)
        let updated = socksProxies.map { $0.applying(result) }
        // A single test updates status only. Retention is intentionally a
        // batch policy, and sorting is derived by `rankedSocksProxies`.
        try socksProxyRepository.save(updated)
        socksProxies = updated
    }

    func updateSocksProxyValidationSettings(
        _ settings: SocksProxyValidationSettings
    ) throws {
        let normalized = settings.normalized
        let previousSettings = socksProxyValidationSettings
        let validationRulesChanged = validationContextChanged(
            from: previousSettings,
            to: normalized
        )

        if validationRulesChanged {
            let previousProxies = socksProxies
            let invalidated = previousProxies.map { $0.invalidatingValidation() }
            if invalidated != previousProxies {
                try socksProxyRepository.save(invalidated)
            }

            do {
                try socksProxyRepository.saveSettings(normalized)
            } catch {
                if invalidated != previousProxies {
                    try? socksProxyRepository.save(previousProxies)
                }
                throw error
            }
            socksProxies = invalidated
        } else {
            try socksProxyRepository.saveSettings(normalized)
        }

        socksProxyValidationSettings = normalized
    }

    func resetSocksProxyValidationSettings() throws {
        try updateSocksProxyValidationSettings(.defaults)
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
        guard let group = profileGroups.first(where: { $0.name == groupName }) else {
            return
        }
        await deleteProfiles(inGroupID: group.id)
    }

    func deleteProfiles(inGroupID groupID: UUID) async {
        guard let targetGroup = profileGroups.first(where: { $0.id == groupID }) else {
            return
        }
        let targetName = targetGroup.name
        let profilesToDelete = profiles.filter { profile in
            profile.groupID == groupID
                || (profile.groupID == nil
                    && profile.displayGroupName == targetName)
        }
        guard !profilesToDelete.isEmpty else { return }
        guard !isDestructiveOperationInProgress else { return }

        busyGroupName = targetName
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
            isProfileStoreAvailable = true
            isLoadingProfiles = false
        } catch {
            // Keep the store unavailable until a retry succeeds.  Presenting
            // an empty array as valid here would allow a later action to
            // overwrite the user's intact profiles.json.
            isProfileStoreAvailable = false
            isLoadingProfiles = true
        }
    }

    // MARK: - Group metadata

    /// Adds stable group IDs and normalizes copied metadata for files written
    /// by versions that only stored `groupName`.  The migration is deliberately
    /// performed once at launch and written back atomically through the existing
    /// profile repository, so old installations do not need a second data file.
    private func migrateGroupMetadataIfNeeded() {
        guard !profiles.isEmpty else { return }

        let originalProfiles = profiles
        var idByName: [String: UUID] = [:]
        var nameByID: [UUID: String] = [:]
        var codeByID: [UUID: String] = [:]
        var emojiByID: [UUID: String] = [:]
        var migrated = profiles

        for index in migrated.indices {
            let profile = migrated[index]
            let displayName = profile.displayGroupName
            let candidateID = profile.groupID

            let groupID: UUID
            if let existingID = idByName[displayName] {
                // The first profile in a name bucket defines its stable ID.
                // This also repairs older files that accidentally assigned a
                // different ID to one member of the same group.
                groupID = existingID
            } else if let candidateID, nameByID[candidateID] == nil {
                groupID = candidateID
                idByName[displayName] = candidateID
                nameByID[candidateID] = displayName
            } else {
                groupID = UUID()
                idByName[displayName] = groupID
                nameByID[groupID] = displayName
            }

            nameByID[groupID] = nameByID[groupID] ?? displayName
            if codeByID[groupID] == nil,
               let code = normalizedOptional(profile.groupCode) {
                codeByID[groupID] = code
            }
            if emojiByID[groupID] == nil,
               let emoji = normalizedGroupEmoji(profile.groupEmoji) {
                emojiByID[groupID] = emoji
            }

            migrated[index].groupID = groupID
            migrated[index].groupName = normalizedOptional(profile.groupName)
        }

        for index in migrated.indices {
            guard let groupID = migrated[index].groupID else { continue }
            migrated[index].groupCode = codeByID[groupID]
            migrated[index].groupEmoji = emojiByID[groupID]
        }

        guard migrated != originalProfiles else { return }
        profiles = migrated
        do {
            try persist()
        } catch {
            profiles = originalProfiles
            present(error)
        }
    }

    private func groupMetadata(named groupName: String?) -> (id: UUID, code: String?, emoji: String?)? {
        let displayName = groupName ?? "未分组"
        guard let group = profileGroups.first(where: { $0.name == displayName }) else {
            return nil
        }
        return (group.id, group.code, group.emoji)
    }

    /// Assigns a profile to an existing group when possible, otherwise creates
    /// a new stable identity.  Metadata is copied from the first member of the
    /// target group, keeping all cards consistent after per-profile edits.
    private func assignGroupMetadata(
        to profile: inout BrowserProfile,
        preserving previousProfile: BrowserProfile? = nil,
        whenGroupNameUnchanged: Bool = false
    ) {
        let normalizedName = normalizedOptional(profile.groupName)
        profile.groupName = normalizedName

        if whenGroupNameUnchanged,
           let previousProfile,
           let previousID = previousProfile.groupID {
            profile.groupID = previousID
            profile.groupCode = previousProfile.groupCode
            profile.groupEmoji = previousProfile.groupEmoji
            return
        }

        if let group = groupMetadata(named: normalizedName) {
            profile.groupID = group.id
            profile.groupCode = group.code
            profile.groupEmoji = group.emoji
            return
        }

        // A new group name must receive a fresh identity.  Reusing an old
        // profile's ID here would make a renamed/moved profile appear in two
        // unrelated groups that happen to share no metadata.
        profile.groupID = UUID()
        profile.groupCode = normalizedOptional(profile.groupCode)
        profile.groupEmoji = normalizedGroupEmoji(profile.groupEmoji)
    }

    private func linkedProfileName(
        _ profileName: String,
        replacingGroupName oldName: String,
        with newName: String
    ) -> String {
        guard oldName != newName else { return profileName }
        guard !oldName.isEmpty, profileName.hasPrefix(oldName) else {
            return profileName
        }

        let suffix = String(profileName.dropFirst(oldName.count))
        // Names such as “站点 1”, “站点-主账号” and “站点一” are common
        // generated labels.  Preserve their suffix while changing only the
        // group-derived prefix; unrelated custom names remain untouched.
        guard suffix.isEmpty
            || suffix.first?.isNumber == true
            || suffix.first?.isLetter == false
            || suffix.first == "_"
            || suffix.first == "-"
            || suffix.first == " "
            || suffix.first == "·"
        else {
            return profileName
        }
        return newName + suffix
    }

    private func normalizedGroupEmoji(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        // Keep a compact card layout while allowing composed emoji (one
        // Character can contain multiple Unicode scalars).
        return String(trimmed.prefix(4))
    }

    private func reloadSocksProxies() {
        do {
            let loadedProxies = try socksProxyRepository.load()
            let migratedProxies = loadedProxies.map { proxy in
                proxy.validationRevision == SocksProxy.currentValidationRevision
                    ? proxy
                    : proxy.invalidatingValidation()
            }
            if migratedProxies != loadedProxies {
                try socksProxyRepository.save(migratedProxies)
            }
            socksProxies = migratedProxies
            proxyPresets = try socksProxyRepository.loadPresets()
        } catch {
            present(error)
        }
    }

    private func reloadSocksProxyValidationSettings() {
        do {
            socksProxyValidationSettings = try socksProxyRepository.loadSettings()
        } catch {
            socksProxyValidationSettings = .defaults
            present(error)
        }
    }

    private func socksProxyValidationService(
        for settings: SocksProxyValidationSettings
    ) -> SocksProxyValidationService {
        socksProxyValidationServiceOverride
            ?? SocksProxyValidationService(configuration: settings.validationConfiguration)
    }

    private func ranked(
        _ proxies: [SocksProxy],
        using sortMode: SocksProxySortMode
    ) -> [SocksProxyRanking] {
        ordered(proxies, using: sortMode).enumerated().map { index, proxy in
            SocksProxyRanking(number: index + 1, proxy: proxy)
        }
    }

    private func ordered(
        _ proxies: [SocksProxy],
        using sortMode: SocksProxySortMode
    ) -> [SocksProxy] {
        switch sortMode {
        case .latencyAscending:
            return SocksProxyValidationService.sort(proxies)
        case .inputOrder:
            return proxies
        }
    }

    private func validationContextChanged(
        from previous: SocksProxyValidationSettings,
        to updated: SocksProxyValidationSettings
    ) -> Bool {
        let previous = previous.normalized
        let updated = updated.normalized
        return previous.targetHost != updated.targetHost
            || previous.targetPort != updated.targetPort
            || previous.verifiesTLS != updated.verifiesTLS
    }

    private func persist() throws {
        guard isProfileStoreAvailable else {
            throw ProfileError.profileStoreUnavailable
        }
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
        let previousBalance = profiles[index].cachedBalance
        profiles[index].cachedBalance = balance
        do {
            try persist()
        } catch {
            profiles[index].cachedBalance = previousBalance
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
    case profileStoreUnavailable
    case groupNotFound
    case groupNameEmpty
    case groupNameAlreadyExists
    case autofillCredentialsIncomplete
    case invalidAutofillOrigin

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "找不到这个浏览器环境。"
        case .profileStoreUnavailable:
            return "环境数据尚未成功读取。为保护原文件，本次修改没有保存，请先重试读取。"
        case .groupNotFound:
            return "找不到这个分组。"
        case .groupNameEmpty:
            return "分组名称不能为空。"
        case .groupNameAlreadyExists:
            return "已经存在同名分组，请换一个名称。"
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
