import XCTest
@testable import AnalyticsKit

final class DomainTests: XCTestCase {

    // MARK: CityStat folding (§4.3: one row per (city, device) → one city entry)

    func testFoldMergesDeviceRowsPerCity() {
        let rows = [
            CityRow(city: "Berlin", country: "Germany", countryCode: "DE",
                    deviceType: .mobile, visitors: 280, pageviews: 1100),
            CityRow(city: "Berlin", country: "Germany", countryCode: "DE",
                    deviceType: .desktop, visitors: 120, pageviews: 480),
            CityRow(city: "Berlin", country: "Germany", countryCode: "DE",
                    deviceType: .tablet, visitors: 12, pageviews: 40),
            CityRow(city: "London", country: "United Kingdom", countryCode: "GB",
                    deviceType: .mobile, visitors: 190, pageviews: 700),
        ]

        let stats = CityStat.fold(rows: rows)

        XCTAssertEqual(stats.count, 2)
        let berlin = stats[0]
        XCTAssertEqual(berlin.city, "Berlin")
        XCTAssertEqual(berlin.visitors, 412)
        XCTAssertEqual(berlin.pageviews, 1620)
        XCTAssertEqual(berlin.deviceSplit, [.mobile: 280, .desktop: 120, .tablet: 12])
        XCTAssertEqual(stats[1].city, "London")
    }

    func testFoldSortsByVisitorsDescending() {
        let rows = [
            CityRow(city: "Small", country: "X", countryCode: "US", deviceType: .mobile, visitors: 5, pageviews: 9),
            CityRow(city: "Big", country: "X", countryCode: "US", deviceType: .mobile, visitors: 900, pageviews: 2000),
            CityRow(city: "Mid", country: "X", countryCode: "US", deviceType: .desktop, visitors: 50, pageviews: 80),
        ]
        XCTAssertEqual(CityStat.fold(rows: rows).map(\.city), ["Big", "Mid", "Small"])
    }

    func testFoldDisambiguatesSameCityNameAcrossCountries() {
        // Paris, FR and Paris, US (Texas) must not merge.
        let rows = [
            CityRow(city: "Paris", country: "France", countryCode: "FR", deviceType: .mobile, visitors: 200, pageviews: 500),
            CityRow(city: "Paris", country: "United States", countryCode: "US", deviceType: .mobile, visitors: 10, pageviews: 20),
        ]
        let stats = CityStat.fold(rows: rows)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats[0].country, "France")
        XCTAssertEqual(stats[1].country, "United States")
    }

    func testFoldEmptyInput() {
        XCTAssertTrue(CityStat.fold(rows: []).isEmpty)
    }

    func testCountryFoldFromCityRowsAggregatesAcrossCitiesAndDevices() {
        let rows = [
            CityRow(city: "Berlin", country: "Germany", countryCode: "DE", deviceType: .mobile, visitors: 280, pageviews: 1100),
            CityRow(city: "Munich", country: "Germany", countryCode: "DE", deviceType: .desktop, visitors: 90, pageviews: 300),
            CityRow(city: "London", country: "United Kingdom", countryCode: "GB", deviceType: .mobile, visitors: 500, pageviews: 900),
        ]
        let countries = CountryStat.fold(fromCityRows: rows)

        XCTAssertEqual(countries.map(\.countryCode), ["GB", "DE"], "sorted by visitors desc")
        XCTAssertEqual(countries[1].visitors, 370)
        XCTAssertEqual(countries[1].pageviews, 1400)
        XCTAssertEqual(countries[1].country, "Germany")
    }

    // MARK: Device types

    func testDeviceTypeMapping() {
        XCTAssertEqual(DeviceType(label: "Desktop"), .desktop)
        XCTAssertEqual(DeviceType(label: "Mobile"), .mobile)
        XCTAssertEqual(DeviceType(label: "Tablet"), .tablet)
        XCTAssertEqual(DeviceType(label: "Console"), .other)
        XCTAssertEqual(DeviceType(label: nil), .other)
    }

    func testDeviceSymbolsMatchSpec() {
        // §5.4 / §6.1: desktopcomputer, iphone, ipad.
        XCTAssertEqual(DeviceType.desktop.symbolName, "desktopcomputer")
        XCTAssertEqual(DeviceType.mobile.symbolName, "iphone")
        XCTAssertEqual(DeviceType.tablet.symbolName, "ipad")
    }

    // MARK: Country centroids (§5.4 bundled table)

    func testCentroidLookup() {
        let de = CountryCentroids.centroid(for: "DE")
        XCTAssertEqual(de?.latitude ?? 0, 51.17, accuracy: 0.01)
        XCTAssertEqual(de?.longitude ?? 0, 10.45, accuracy: 0.01)
        XCTAssertNotNil(CountryCentroids.centroid(for: "us"), "lookup is case-insensitive")
        XCTAssertNil(CountryCentroids.centroid(for: "ZZ"))
    }
}
