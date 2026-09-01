import Foundation
import Testing
@testable import ProfileBrowser

struct UserAgentTests {
    private let testOSVersion = OperatingSystemVersion(
        majorVersion: 26,
        minorVersion: 0,
        patchVersion: 0
    )

    @Test
    func viaPresetAndCatalogValuesAreIOS() {
        let preset = BrowserProfile.userAgentPresets.first { $0.name == "Via" }
        #expect(preset?.value.contains("iPhone") == true)
        #expect(preset?.value.contains("Via/1.9.0") == true)
        #expect(preset?.value.contains("Android") == false)

        let candidates = BrowserProfile.userAgentCandidates(
            for: "Via",
            maximumOSVersion: testOSVersion
        )
        #expect(candidates.count >= 30)
        #expect(candidates.allSatisfy { value in
            value.contains("iPhone")
                && value.contains("Via/1.9.0")
                && !value.contains("Android")
        })
    }

    @Test
    func candidatePoolsAreLargeUniqueAndSelfConsistent() {
        let minimumCounts = [
            "iPhone Safari": 30,
            "iPad Safari": 30,
            "UC": 30,
            "Via": 30,
            "Edge": 50,
            "Chrome": 700,
            "Alook": 30,
            "Firefox": 1_500,
            "Opera": 30
        ]

        for (browserName, minimumCount) in minimumCounts {
            let candidates = BrowserProfile.userAgentCandidates(
                for: browserName,
                maximumOSVersion: testOSVersion
            )

            #expect(candidates.count >= minimumCount)
            #expect(Set(candidates).count == candidates.count)
            #expect(candidates.allSatisfy {
                BrowserProfile.userAgentPresetName(for: $0) == browserName
            })
        }
    }

    @Test
    func generatorHonorsExclusionsAndReportsExhaustion() {
        let candidates = BrowserProfile.userAgentCandidates(
            for: "UC",
            maximumOSVersion: testOSVersion
        )
        let onlyAvailable = candidates[0]
        let allOtherValues = Set(candidates.dropFirst())

        let generated = BrowserProfile.uniqueRandomUserAgent(
            for: "UC",
            excluding: allOtherValues,
            maximumOSVersion: testOSVersion
        )
        #expect(generated == onlyAvailable)

        let exhausted = BrowserProfile.uniqueRandomUserAgent(
            for: "UC",
            excluding: Set(candidates),
            maximumOSVersion: testOSVersion
        )
        #expect(exhausted == nil)
    }

    @Test
    func catalogDoesNotGenerateAnOSNewerThanTheDevice() {
        let maximum = OperatingSystemVersion(
            majorVersion: 18,
            minorVersion: 4,
            patchVersion: 1
        )
        let candidates = BrowserProfile.userAgentCandidates(
            for: "Chrome",
            maximumOSVersion: maximum
        )

        #expect(candidates.contains { $0.contains("iPhone OS 18_4_1") })
        #expect(!candidates.contains { $0.contains("iPhone OS 18_5") })
        #expect(!candidates.contains { $0.contains("iPhone OS 26_") })
    }

    @Test
    func detailsDescribeTheGeneratedIdentity() throws {
        let candidates = BrowserProfile.userAgentCandidates(
            for: "Chrome",
            maximumOSVersion: testOSVersion
        )
        let value = try #require(candidates.first {
            $0.contains("iPhone OS 18_6_2")
                && $0.contains("CriOS/152.0.7977.64")
        })
        let details = try #require(BrowserProfile.userAgentDetails(for: value))

        #expect(details.browserName == "Chrome")
        #expect(details.deviceName == "iPhone")
        #expect(details.operatingSystemVersion == "18.6.2")
        #expect(details.browserVersion == "152.0.7977.64")
        #expect(details.summary == "Chrome · iPhone · iOS 18.6.2 · 152.0.7977.64")
    }

    @Test
    func safariDeviceFamiliesRemainSeparate() {
        let iphoneValues = BrowserProfile.userAgentCandidates(
            for: "iPhone Safari",
            maximumOSVersion: testOSVersion
        )
        let ipadValues = BrowserProfile.userAgentCandidates(
            for: "iPad Safari",
            maximumOSVersion: testOSVersion
        )

        #expect(iphoneValues.allSatisfy { $0.contains("iPhone") && !$0.contains("iPad") })
        #expect(ipadValues.allSatisfy { $0.contains("iPad") && !$0.contains("iPhone") })
    }
}
