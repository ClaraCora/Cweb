import Foundation
import Testing
@testable import ProfileBrowser

struct UserAgentTests {
    @Test
    func viaPresetAndRandomValuesAreIOS() {
        let preset = BrowserProfile.userAgentPresets.first { $0.name == "Via" }
        #expect(preset?.value.contains("iPhone") == true)
        #expect(preset?.value.contains("Android") == false)

        for _ in 0..<12 {
            let value = BrowserProfile.randomUserAgent(for: "Via")
            #expect(value.contains("iPhone"))
            #expect(value.contains("Via/"))
            #expect(!value.contains("Android"))
        }
    }

    @Test
    func randomValuesHaveMoreThanTwoCombinations() {
        let values = Set((0..<40).map { _ in
            BrowserProfile.randomUserAgent(for: "Chrome")
        })

        #expect(values.count > 2)
    }

    @Test
    func identifiesRandomizedBrowserType() {
        let browserNames = ["UC", "Via", "Edge", "Chrome", "Alook", "Firefox", "Opera"]
        for name in browserNames {
            let value = BrowserProfile.randomUserAgent(for: name)
            #expect(BrowserProfile.userAgentPresetName(for: value) == name)
        }

        let iPad = BrowserProfile.randomUserAgent(for: "iPad Safari")
        #expect(BrowserProfile.userAgentPresetName(for: iPad) == "iPad Safari")
    }
}
