import Foundation

// MARK: - /query response envelope (§2.2, §4.2)

/// Decoded response of `POST /api/projects/:id/query/` for `HogQLQuery`.
/// `results` is an array of rows; each row is a positional array whose element
/// order matches the SELECT clause, so row types decode from unkeyed containers.
public struct QueryEnvelope<Row: Decodable & Sendable>: Decodable, Sendable {
    public let results: [Row]
    public let columns: [String]?
    public let isCached: Bool?
    public let cacheKey: String?
    public let cacheTargetAge: Date?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case results, columns, error
        case isCached = "is_cached"
        case cacheKey = "cache_key"
        case cacheTargetAge = "cache_target_age"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? c.decodeIfPresent([Row].self, forKey: .results)) ?? []
        columns = try? c.decodeIfPresent([String].self, forKey: .columns)
        isCached = try? c.decodeIfPresent(Bool.self, forKey: .isCached)
        cacheKey = try? c.decodeIfPresent(String.self, forKey: .cacheKey)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        // cache_target_age may arrive as an ISO-8601 string or an epoch number.
        if let iso = try? c.decodeIfPresent(String.self, forKey: .cacheTargetAge) {
            cacheTargetAge = FlexibleDate.parse(iso)
        } else if let epoch = try? c.decodeIfPresent(Double.self, forKey: .cacheTargetAge) {
            cacheTargetAge = Date(timeIntervalSince1970: epoch)
        } else {
            cacheTargetAge = nil
        }
    }

    public init(results: [Row], columns: [String]? = nil, isCached: Bool? = nil,
                cacheKey: String? = nil, cacheTargetAge: Date? = nil, error: String? = nil) {
        self.results = results
        self.columns = columns
        self.isCached = isCached
        self.cacheKey = cacheKey
        self.cacheTargetAge = cacheTargetAge
        self.error = error
    }
}

/// Parses the date formats PostHog emits (ISO-8601 with/without fractional seconds).
public enum FlexibleDate {
    public static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: string) { return d }
        // Django often emits "2026-07-05 12:00:00" style timestamps.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        for pattern in ["yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            fmt.dateFormat = pattern
            if let d = fmt.date(from: string) { return d }
        }
        return nil
    }
}

// MARK: - Positional row scalar

/// A scalar cell in a HogQL result row. ClickHouse aggregates may surface as
/// Int, Double, String, Bool, or null depending on the column.
public enum HogQLScalar: Decodable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    public var intValue: Int {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s) ?? 0
        case .bool(let b): return b ? 1 : 0
        case .null: return 0
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool, .null: return nil
        }
    }
}
