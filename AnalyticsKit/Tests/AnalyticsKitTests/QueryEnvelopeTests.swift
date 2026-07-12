import XCTest
@testable import AnalyticsKit

/// `/query` envelope decoding, including `is_cached`/`cache_target_age`
/// variants and positional row decoding (§11).
final class QueryEnvelopeTests: XCTestCase {

    func testDecodesTrendRowsWithCacheMetadata() throws {
        let payload = Data("""
        {
            "results": [
                ["2026-06-29T00:00:00Z", 1512, 5910],
                ["2026-06-30T00:00:00Z", 1688, 6480]
            ],
            "columns": ["day", "visitors", "pageviews"],
            "is_cached": true,
            "cache_key": "cache_8a41",
            "cache_target_age": "2026-07-05T12:30:00Z"
        }
        """.utf8)

        let envelope = try JSONDecoder().decode(QueryEnvelope<TrendRow>.self, from: payload)

        XCTAssertEqual(envelope.results.count, 2)
        XCTAssertEqual(envelope.results[0].visitors, 1512)
        XCTAssertEqual(envelope.results[1].pageviews, 6480)
        XCTAssertEqual(envelope.columns, ["day", "visitors", "pageviews"])
        XCTAssertEqual(envelope.isCached, true)
        XCTAssertEqual(envelope.cacheKey, "cache_8a41")
        XCTAssertEqual(envelope.cacheTargetAge, FlexibleDate.parse("2026-07-05T12:30:00Z"))
    }

    func testDecodesUncachedEnvelopeWithoutCacheFields() throws {
        let payload = Data(#"{"results": [["2026-06-29 00:00:00", 3, 9]]}"#.utf8)
        let envelope = try JSONDecoder().decode(QueryEnvelope<TrendRow>.self, from: payload)

        XCTAssertNil(envelope.isCached)
        XCTAssertNil(envelope.cacheTargetAge)
        XCTAssertEqual(envelope.results[0].visitors, 3)
        // Django-style timestamp without T/Z still parses.
        XCTAssertNotEqual(envelope.results[0].day, .distantPast)
    }

    func testDecodesCountryRows() throws {
        let payload = Data("""
        {"results": [["DE", "Germany", 2110, 8103], [null, null, 40, 90]]}
        """.utf8)
        let envelope = try JSONDecoder().decode(QueryEnvelope<CountryRow>.self, from: payload)

        XCTAssertEqual(envelope.results[0].countryCode, "DE")
        XCTAssertEqual(envelope.results[0].country, "Germany")
        // Null cells degrade to placeholders instead of failing the whole decode.
        XCTAssertEqual(envelope.results[1].countryCode, "??")
        XCTAssertEqual(envelope.results[1].visitors, 40)
    }

    func testDecodesCityRowsWithDeviceTypes() throws {
        let payload = Data("""
        {"results": [
            ["Berlin", "Germany", "DE", "Mobile", 280, 1100],
            ["Berlin", "Germany", "DE", "SmartFridge", 3, 5]
        ]}
        """.utf8)
        let envelope = try JSONDecoder().decode(QueryEnvelope<CityRow>.self, from: payload)

        XCTAssertEqual(envelope.results[0].deviceType, .mobile)
        // Unknown device labels map to .other, never crash the widget.
        XCTAssertEqual(envelope.results[1].deviceType, .other)
    }

    func testDecodesUnknownLocationsSingleValueRow() throws {
        let payload = Data(#"{"results": [[118]]}"#.utf8)
        let envelope = try JSONDecoder().decode(QueryEnvelope<UnknownRow>.self, from: payload)
        XCTAssertEqual(envelope.results.first?.visitors, 118)
    }

    func testErrorPayloadIsExposed() throws {
        let payload = Data(#"{"results": [], "error": "Unable to parse HogQL"}"#.utf8)
        let envelope = try JSONDecoder().decode(QueryEnvelope<TrendRow>.self, from: payload)
        XCTAssertEqual(envelope.error, "Unable to parse HogQL")
    }

    func testFloatAggregatesDecodeToInts() throws {
        // ClickHouse sometimes returns aggregate counts as floats.
        let payload = Data(#"{"results": [["2026-06-29T00:00:00Z", 1512.0, 5910.0]]}"#.utf8)
        let envelope = try JSONDecoder().decode(QueryEnvelope<TrendRow>.self, from: payload)
        XCTAssertEqual(envelope.results[0].visitors, 1512)
    }

    func testEpochCacheTargetAge() throws {
        let payload = Data(#"{"results": [], "cache_target_age": 1780000000.5}"#.utf8)
        let envelope = try JSONDecoder().decode(QueryEnvelope<TrendRow>.self, from: payload)
        XCTAssertEqual(envelope.cacheTargetAge?.timeIntervalSince1970 ?? 0, 1_780_000_000.5, accuracy: 1)
    }
}
