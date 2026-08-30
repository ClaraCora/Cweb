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

    func cookieCount(for profile: BrowserProfile) async -> Int {
        await dataStore(for: profile).httpCookieStore.allCookies().count
    }
}
