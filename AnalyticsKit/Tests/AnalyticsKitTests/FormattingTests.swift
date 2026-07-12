import XCTest
@testable import AnalyticsKit

final class FormattingTests: XCTestCase {

    func testAbbreviatedCounts() {
        XCTAssertEqual(Formatting.abbreviated(0), "0")
        XCTAssertEqual(Formatting.abbreviated(950), "950")
        XCTAssertEqual(Formatting.abbreviated(1_000), "1K")
        XCTAssertEqual(Formatting.abbreviated(1_499), "1.5K")
        XCTAssertEqual(Formatting.abbreviated(12_437), "12.4K")
        XCTAssertEqual(Formatting.abbreviated(999_949), "999.9K")
        XCTAssertEqual(Formatting.abbreviated(1_200_000), "1.2M")
        XCTAssertEqual(Formatting.abbreviated(3_000_000_000.0), "3B")
        XCTAssertEqual(Formatting.abbreviated(-12_437), "-12.4K")
    }

    func testDurations() {
        XCTAssertEqual(Formatting.duration(seconds: 42), "42s")
        XCTAssertEqual(Formatting.duration(seconds: 72), "1m 12s")
        XCTAssertEqual(Formatting.duration(seconds: 120), "2m")
        XCTAssertEqual(Formatting.duration(seconds: 3661), "1h 1m")
        XCTAssertEqual(Formatting.duration(seconds: 154.2), "2m 34s")
    }

    func testPercent() {
        XCTAssertEqual(Formatting.percent(8.2), "8.2%")
        XCTAssertEqual(Formatting.percent(5.0), "5%")
        XCTAssertEqual(Formatting.percent(0), "0%")
    }

    func testBounceRateNormalizesFractionsAndPercentages() {
        XCTAssertEqual(Formatting.bounceRate(0.42), "42%")
        XCTAssertEqual(Formatting.bounceRate(42), "42%")
        XCTAssertEqual(Formatting.bounceRate(1), "100%")
    }

    func testFlagEmoji() {
        XCTAssertEqual(Formatting.flagEmoji(countryCode: "DE"), "🇩🇪")
        XCTAssertEqual(Formatting.flagEmoji(countryCode: "us"), "🇺🇸")
        XCTAssertEqual(Formatting.flagEmoji(countryCode: "GB"), "🇬🇧")
        XCTAssertEqual(Formatting.flagEmoji(countryCode: "??"), "🏳️")
        XCTAssertEqual(Formatting.flagEmoji(countryCode: ""), "🏳️")
        XCTAssertEqual(Formatting.flagEmoji(countryCode: "USA"), "🏳️")
    }

    func testKeyPreviewNeverExposesFullKey() {
        // §8: Settings shows `phx_…last4` only.
        XCTAssertEqual(Profile.keyPreview("phx_AbCdEfGh1234"), "phx_…1234")
        XCTAssertEqual(Profile.keyPreview("phx_1"), "phx_…")
    }
}

final class DeepLinkTests: XCTestCase {

    func testDashboardRoute() {
        XCTAssertEqual(DeepLink(url: URL(string: "pulseglass://dashboard?range=7d")!),
                       .dashboard(range: .week))
        XCTAssertEqual(DeepLink(url: URL(string: "pulseglass://dashboard?range=30d")!),
                       .dashboard(range: .month))
        XCTAssertEqual(DeepLink(url: URL(string: "pulseglass://dashboard")!),
                       .dashboard(range: .week), "range defaults to 7d")
    }

    func testRegionsRoute() {
        XCTAssertEqual(DeepLink(url: URL(string: "pulseglass://regions?city=Berlin")!),
                       .regions(city: "Berlin"))
        XCTAssertEqual(DeepLink(url: URL(string: "pulseglass://regions")!),
                       .regions(city: nil))
    }

    func testOnboardingRoute() {
        XCTAssertEqual(DeepLink(url: URL(string: "pulseglass://onboarding")!), .onboarding)
    }

    func testAllowlistRejectsUnknownRoutesAndSchemes() {
        // §8: parsed with an allowlist of routes/params.
        XCTAssertNil(DeepLink(url: URL(string: "pulseglass://settings")!))
        XCTAssertNil(DeepLink(url: URL(string: "pulseglass://dashboard?range=365d")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://dashboard?range=7d")!))
        XCTAssertNil(DeepLink(url: URL(string: "evil://dashboard")!))
    }

    func testRoundTrip() {
        for link: DeepLink in [.dashboard(range: .quarter), .regions(city: "São Paulo"), .onboarding] {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
    }

    func testDashboardURLPolicyRequiresConfiguredHostAndHTTPS() {
        let configured = URL(string: "https://us.posthog.com")!
        XCTAssertTrue(DashboardURLPolicy.isAllowed(
            URL(string: "https://us.posthog.com/project/1/web")!, configuredHost: configured))
        XCTAssertFalse(DashboardURLPolicy.isAllowed(
            URL(string: "https://evil.example.com/project/1")!, configuredHost: configured))
        XCTAssertFalse(DashboardURLPolicy.isAllowed(
            URL(string: "http://us.posthog.com/project/1")!, configuredHost: configured))
    }
}
