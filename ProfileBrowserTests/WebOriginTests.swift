import Foundation
import Testing
@testable import ProfileBrowser

struct WebOriginTests {
    @Test
    func normalizesHTTPSOrigin() throws {
        let url = try #require(URL(string: "https://Example.COM/login?next=/home"))
        let origin = try #require(WebOrigin(url: url))

        #expect(origin.scheme == "https")
        #expect(origin.host == "example.com")
        #expect(origin.port == 443)
        #expect(origin.displayString == "https://example.com")
        #expect(origin.isSecure)
    }

    @Test
    func keepsNonDefaultPortDistinct() throws {
        let standardURL = try #require(URL(string: "https://example.com"))
        let alternateURL = try #require(URL(string: "https://example.com:8443"))
        let standard = try #require(WebOrigin(url: standardURL))
        let alternate = try #require(WebOrigin(url: alternateURL))

        #expect(standard != alternate)
        #expect(alternate.displayString == "https://example.com:8443")
    }

    @Test
    func rejectsNonWebSchemes() throws {
        let fileURL = try #require(URL(string: "file:///tmp/index.html"))
        #expect(WebOrigin(url: fileURL) == nil)
    }
}
