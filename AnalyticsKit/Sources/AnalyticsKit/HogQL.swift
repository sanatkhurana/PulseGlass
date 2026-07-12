import Foundation

// MARK: - HogQL query builders (§4.3)

/// A named HogQL query. The SQL text is deliberately deterministic:
/// PostHog's server-side query cache keys on the exact query text, so the
/// builders below are snapshot-tested byte-for-byte.
public struct HogQLRequest: Sendable, Equatable, Hashable {
    public let name: String
    public let sql: String

    public init(name: String, sql: String) {
        self.name = name
        self.sql = sql
    }
}

/// The date range selectable in the app. The widget always uses `.week`.
public enum DateRange: Int, CaseIterable, Sendable, Codable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    public var id: Int { rawValue }
    public var days: Int { rawValue }
    public var label: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        }
    }

    /// Longer ranges bucket by week to stay under the 96-point chart budget (§10).
    var bucketFunction: String { self == .quarter ? "toStartOfWeek" : "toStartOfDay" }
}

public enum HogQL {

    /// Q2 — Daily visitors & pageviews trend (app chart + widget sparkline).
    public static func trend(range: DateRange = .week) -> HogQLRequest {
        HogQLRequest(
            name: "pulseglass.trend.daily",
            sql: """
            SELECT
                \(range.bucketFunction)(timestamp) AS day,
                uniq(person_id)         AS visitors,
                count()                 AS pageviews
            FROM events
            WHERE event = '$pageview'
              AND timestamp >= now() - INTERVAL \(range.days) DAY
            GROUP BY day
            ORDER BY day ASC
            LIMIT 31
            """
        )
    }

    /// Q3 — Countries (app Regions view).
    public static func countries(range: DateRange = .week) -> HogQLRequest {
        HogQLRequest(
            name: "pulseglass.regions.countries",
            sql: """
            SELECT
                properties.$geoip_country_code AS country_code,
                properties.$geoip_country_name AS country,
                uniq(person_id)                AS visitors,
                count()                        AS pageviews
            FROM events
            WHERE event = '$pageview'
              AND timestamp >= now() - INTERVAL \(range.days) DAY
              AND properties.$geoip_country_code IS NOT NULL
            GROUP BY country_code, country
            ORDER BY visitors DESC
            LIMIT 250
            """
        )
    }

    /// Q4 — Cities with device split (app drill-down + widget geo list).
    public static func cities(range: DateRange = .week) -> HogQLRequest {
        HogQLRequest(
            name: "pulseglass.regions.cities",
            sql: """
            SELECT
                properties.$geoip_city_name     AS city,
                properties.$geoip_country_name  AS country,
                properties.$geoip_country_code  AS country_code,
                properties.$device_type         AS device_type,
                uniq(person_id)                 AS visitors,
                count()                         AS pageviews
            FROM events
            WHERE event = '$pageview'
              AND timestamp >= now() - INTERVAL \(range.days) DAY
              AND properties.$geoip_city_name IS NOT NULL
            GROUP BY city, country, country_code, device_type
            ORDER BY visitors DESC
            LIMIT 120
            """
        )
    }

    /// Q5 — Unknown-locations reconciliation (app footer).
    public static func unknownLocations(range: DateRange = .week) -> HogQLRequest {
        HogQLRequest(
            name: "pulseglass.regions.unknown",
            sql: """
            SELECT uniq(person_id) AS visitors
            FROM events
            WHERE event = '$pageview'
              AND timestamp >= now() - INTERVAL \(range.days) DAY
              AND properties.$geoip_country_code IS NULL
            LIMIT 1
            """
        )
    }
}
