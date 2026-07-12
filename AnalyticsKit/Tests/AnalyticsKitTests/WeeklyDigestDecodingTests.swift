import XCTest
@testable import AnalyticsKit

/// DTO decoding against captured fixtures of the documented `weekly_digest`
/// schema (§11), including partial payloads and unknown enum values.
final class WeeklyDigestDecodingTests: XCTestCase {

    static let fullFixture = Data("""
    {
        "visitors": {
            "current": 12437, "previous": 11494,
            "change": {"percent": 8.2, "direction": "increase",
                       "text": "▲ 8.2%", "long_text": "Up 8.2% from the previous period", "color": "green"}
        },
        "pageviews": {
            "current": 48210, "previous": 45930,
            "change": {"percent": 5.0, "direction": "up", "text": "▲ 5%", "long_text": "Up 5%", "color": "green"}
        },
        "sessions": {
            "current": 16780, "previous": 17240,
            "change": {"percent": -2.7, "direction": "down", "text": "▼ 2.7%", "long_text": "Down 2.7%", "color": "red"}
        },
        "bounce_rate": {
            "current": 0.42, "previous": 0.45,
            "change": {"percent": -6.7, "direction": "down", "text": "▼ 6.7%", "long_text": "Down 6.7%", "color": "green"}
        },
        "avg_session_duration": {
            "current": 154.2, "previous": 149.0,
            "change": {"percent": 3.4, "direction": "up", "text": "▲ 3.4%", "long_text": "Up 3.4%", "color": "green"}
        },
        "top_pages": [
            {"host": "example.com", "path": "/", "visitors": 5210,
             "change": {"percent": 4.1, "direction": "up"}},
            {"host": null, "path": "/pricing", "visitors": 2380, "change": null}
        ],
        "top_sources": [
            {"name": "Google", "visitors": 6120, "change": {"percent": 6.3, "direction": "up"}}
        ],
        "goals": [
            {"name": "Signed up", "conversions": 82, "change": {"percent": 11.0, "direction": "up"}}
        ],
        "dashboard_url": "https://us.posthog.com/project/123/web/analytics"
    }
    """.utf8)

    func testDecodesFullDocumentedSchema() throws {
        let digest = try JSONDecoder().decode(WeeklyDigest.self, from: Self.fullFixture)

        XCTAssertEqual(digest.visitors.current, 12437)
        XCTAssertEqual(digest.visitors.previous, 11494)
        XCTAssertEqual(digest.visitors.change?.percent, 8.2)
        XCTAssertEqual(digest.pageviews.change?.direction, .up)
        XCTAssertEqual(digest.sessions.change?.direction, .down)
        XCTAssertEqual(digest.bounceRate.current, 0.42)
        XCTAssertEqual(digest.avgSessionDuration.current, 154.2, accuracy: 0.001)
        XCTAssertEqual(digest.visitors.change?.longText, "Up 8.2% from the previous period")

        XCTAssertEqual(digest.topPages.count, 2)
        XCTAssertEqual(digest.topPages[0].host, "example.com")
        XCTAssertEqual(digest.topPages[1].host, nil)
        XCTAssertEqual(digest.topPages[1].path, "/pricing")
        XCTAssertNil(digest.topPages[1].change)

        XCTAssertEqual(digest.topSources.first?.name, "Google")
        XCTAssertEqual(digest.goals.first?.conversions, 82)
        XCTAssertEqual(digest.dashboardURL?.host(), "us.posthog.com")
    }

    func testUnknownDirectionStringMapsToFlat() throws {
        // "increase" is not one of up/down/flat — must map to .flat, not throw (§4.4).
        let digest = try JSONDecoder().decode(WeeklyDigest.self, from: Self.fullFixture)
        XCTAssertEqual(digest.visitors.change?.direction, .flat)
    }

    func testDecodesMinimalPayloadWithoutCrashing() throws {
        // Server-side schema evolution: missing fields must decode to defaults.
        let minimal = Data(#"{"visitors": {"current": 10}}"#.utf8)
        let digest = try JSONDecoder().decode(WeeklyDigest.self, from: minimal)

        XCTAssertEqual(digest.visitors.current, 10)
        XCTAssertNil(digest.visitors.previous)
        XCTAssertEqual(digest.pageviews.current, 0)
        XCTAssertTrue(digest.topPages.isEmpty)
        XCTAssertTrue(digest.goals.isEmpty)
        XCTAssertNil(digest.dashboardURL)
    }

    func testDecodesEmptyObject() throws {
        let digest = try JSONDecoder().decode(WeeklyDigest.self, from: Data("{}".utf8))
        XCTAssertEqual(digest.visitors.current, 0)
        XCTAssertEqual(digest.sessions.current, 0)
    }

    func testUnknownExtraFieldsAreIgnored() throws {
        let payload = Data(#"""
        {"visitors": {"current": 5, "brand_new_field": [1,2,3]}, "future_top_level": {"x": 1}}
        """#.utf8)
        let digest = try JSONDecoder().decode(WeeklyDigest.self, from: payload)
        XCTAssertEqual(digest.visitors.current, 5)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = SampleData.snapshot(asOf: Date(timeIntervalSince1970: 1_780_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Snapshot.self, from: try encoder.encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }
}
