import Foundation
import WebKit

@MainActor
struct WebsiteDataStoreManager {
    // Keep leases until process exit: closing a WebPage does not mean native
    // WebKit has released its backing store yet.
    private static var leasedIDs = Set<UUID>()

    static func lease(_ id: UUID) { leasedIDs.insert(id) }

    static func orphanIDs(all: Set<UUID>, referenced: Set<UUID>, leased: Set<UUID>) -> Set<UUID> {
        all.subtracting(referenced).subtracting(leased)
    }

    func removeOrphans(referenced: @MainActor () -> Set<UUID>) async -> [UUID: String] {
        // Enumerating identifiers can dispatch back to WebKit's main run loop
        // before it exists on a cold launch. The default store initializes
        // WebKit synchronously; it is never used for environment browsing.
        _ = WKWebsiteDataStore.default()
        let all = Set(await WKWebsiteDataStore.allDataStoreIdentifiers)
        guard !all.isEmpty else { return [:] }
        let candidates = Self.orphanIDs(all: all, referenced: referenced(), leased: Self.leasedIDs)
        var failures: [UUID: String] = [:]
        for id in candidates {
            // Another environment may have opened or claimed this store during the previous removal.
            guard !Self.leasedIDs.contains(id), !referenced().contains(id) else { continue }
            do { try await WKWebsiteDataStore.remove(forIdentifier: id) }
            catch { failures[id] = error.localizedDescription }
        }
        return failures
    }

    func dataStore(for profile: BrowserProfile) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: profile.websiteDataStoreID)
    }

    func clearWebsiteData(for profile: BrowserProfile) async {
        let dataStore = dataStore(for: profile)
        await dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    func cookieCount(for profile: BrowserProfile) async -> Int {
        await dataStore(for: profile).httpCookieStore.allCookies().count
    }
}
