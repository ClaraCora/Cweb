import Foundation
import WebKit

@MainActor
struct WebsiteDataStoreManager {
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

    func deleteDataStore(for profile: BrowserProfile) async throws {
        let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
        guard identifiers.contains(profile.websiteDataStoreID) else { return }
        try await WKWebsiteDataStore.remove(forIdentifier: profile.websiteDataStoreID)
    }

    func cookieCount(for profile: BrowserProfile) async -> Int {
        await dataStore(for: profile).httpCookieStore.allCookies().count
    }
}
