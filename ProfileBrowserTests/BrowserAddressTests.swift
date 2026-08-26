import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct BrowserAddressTests {
    @Test
    func preservesCompleteHTTPSURL() throws {
        let url = try #require(BrowserSession.resolveAddress("https://example.com/account"))
        #expect(url.absoluteString == "https://example.com/account")
    }

    @Test
    func addsHTTPSForHostInput() throws {
        let url = try #require(BrowserSession.resolveAddress("example.com/login"))
        #expect(url.absoluteString == "https://example.com/login")
    }

    @Test
    func turnsWordsIntoSearch() throws {
        let url = try #require(BrowserSession.resolveAddress("privacy browser"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "duckduckgo.com")
        #expect(components.queryItems?.first?.name == "q")
        #expect(components.queryItems?.first?.value == "privacy browser")
    }
}
