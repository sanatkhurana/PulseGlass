import XCTest
@testable import AnalyticsKit

/// HogQL builders snapshot-tested byte-for-byte: PostHog's server-side query
/// cache keys on the exact SQL text, so any drift here silently invalidates
/// the cache (§11).
final class HogQLSnapshotTests: XCTestCase {

    func testQ2TrendWeekly() {
        let q = HogQL.trend(range: .week)
        XCTAssertEqual(q.name, "pulseglass.trend.daily")
        XCTAssertEqual(q.sql, """
        SELECT
            toStartOfDay(timestamp) AS day,
            uniq(person_id)         AS visitors,
            count()                 AS pageviews
        FROM events
        WHERE event = '$pageview'
          AND timestamp >= now() - INTERVAL 7 DAY
        GROUP BY day
        ORDER BY day ASC
        LIMIT 31
        """)
    }

    func testQ2TrendMonthlyUsesDailyBuckets() {
        XCTAssertTrue(HogQL.trend(range: .month).sql.contains("INTERVAL 30 DAY"))
        XCTAssertTrue(HogQL.trend(range: .month).sql.contains("toStartOfDay"))
    }

    func testQ2TrendQuarterlyUsesWeeklyBuckets() {
        let sql = HogQL.trend(range: .quarter).sql
        XCTAssertTrue(sql.contains("INTERVAL 90 DAY"))
        XCTAssertTrue(sql.contains("toStartOfWeek"))
        XCTAssertFalse(sql.contains("toStartOfDay"))
    }

    func testQ3Countries() {
        let q = HogQL.countries(range: .week)
        XCTAssertEqual(q.name, "pulseglass.regions.countries")
        XCTAssertEqual(q.sql, """
        SELECT
            properties.$geoip_country_code AS country_code,
            properties.$geoip_country_name AS country,
            uniq(person_id)                AS visitors,
            count()                        AS pageviews
        FROM events
        WHERE event = '$pageview'
          AND timestamp >= now() - INTERVAL 7 DAY
          AND properties.$geoip_country_code IS NOT NULL
        GROUP BY country_code, country
        ORDER BY visitors DESC
        LIMIT 250
        """)
    }

    func testQ4Cities() {
        let q = HogQL.cities(range: .week)
        XCTAssertEqual(q.name, "pulseglass.regions.cities")
        XCTAssertEqual(q.sql, """
        SELECT
            properties.$geoip_city_name     AS city,
            properties.$geoip_country_name  AS country,
            properties.$geoip_country_code  AS country_code,
            properties.$device_type         AS device_type,
            uniq(person_id)                 AS visitors,
            count()                         AS pageviews
        FROM events
        WHERE event = '$pageview'
          AND timestamp >= now() - INTERVAL 7 DAY
          AND properties.$geoip_city_name IS NOT NULL
        GROUP BY city, country, country_code, device_type
        ORDER BY visitors DESC
        LIMIT 120
        """)
    }

    func testQ5UnknownLocations() {
        let q = HogQL.unknownLocations(range: .week)
        XCTAssertEqual(q.name, "pulseglass.regions.unknown")
        XCTAssertEqual(q.sql, """
        SELECT uniq(person_id) AS visitors
        FROM events
        WHERE event = '$pageview'
          AND timestamp >= now() - INTERVAL 7 DAY
          AND properties.$geoip_country_code IS NULL
        LIMIT 1
        """)
    }

    func testIdenticalRangesProduceIdenticalSQLText() {
        // Cache-key stability: two builds of the same query must be byte-identical.
        XCTAssertEqual(HogQL.cities(range: .month), HogQL.cities(range: .month))
    }

    func testEveryQueryHasExplicitLimitAndName() {
        let all = [
            HogQL.trend(range: .week), HogQL.trend(range: .quarter),
            HogQL.countries(range: .week), HogQL.cities(range: .week),
            HogQL.unknownLocations(range: .week),
        ]
        for q in all {
            XCTAssertTrue(q.sql.contains("LIMIT "), "\(q.name) is missing an explicit LIMIT")
            XCTAssertTrue(q.name.hasPrefix("pulseglass."), "\(q.name) is missing query_log attribution")
            XCTAssertFalse(q.sql.contains("OFFSET"), "OFFSET is rejected by /query for personal keys")
        }
    }
}
