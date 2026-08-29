import Foundation
import WebKit

@MainActor
struct WebsiteDataStoreManager {
    private let existingWebsiteDataClearer: ((BrowserProfile) async -> Void)?

    init(
        clearExistingWebsiteDataHandler: ((BrowserProfile) async -> Void)? = nil
    ) {
        existingWebsiteDataClearer = clearExistingWebsiteDataHandler
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

    func clearExistingWebsiteData(for profile: BrowserProfile) async {
        if let existingWebsiteDataClearer {
            await existingWebsiteDataClearer(profile)
            return
        }

        let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
        guard identifiers.contains(profile.websiteDataStoreID) else { return }

        // Removing an identified data store while WebKit is winding down can
        // terminate the app. Clearing its contents keeps the deletion private
        // and makes the now-unreferenced store unusable by the app.
        let dataStore = WKWebsiteDataStore(forIdentifier: profile.websiteDataStoreID)
        await dataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }

    func cookieCount(for profile: BrowserProfile) async -> Int {
        await dataStore(for: profile).httpCookieStore.allCookies().count
    }
}
