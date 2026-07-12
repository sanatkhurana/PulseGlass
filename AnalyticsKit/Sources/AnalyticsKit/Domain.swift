import Foundation

// MARK: - Domain types folded from HogQL rows (§4.3)

public enum DeviceType: String, Codable, Sendable, Hashable, CaseIterable {
    case desktop = "Desktop"
    case mobile = "Mobile"
    case tablet = "Tablet"
    case other = "Other"

    public init(label: String?) {
        self = DeviceType(rawValue: label ?? "") ?? .other
    }

    /// SF Symbol used in city rows and the widget's micro device row (§5.4, §6.1).
    public var symbolName: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .mobile: return "iphone"
        case .tablet: return "ipad"
        case .other: return "questionmark.circle"
        }
    }
}

// MARK: Positional rows (decode order matches the SELECT clauses in HogQL.swift)

/// Q2 row: (day, visitors, pageviews)
public struct TrendRow: Decodable, Sendable, Equatable {
    public let day: Date
    public let visitors: Int
    public let pageviews: Int

    public init(day: Date, visitors: Int, pageviews: Int) {
        self.day = day
        self.visitors = visitors
        self.pageviews = pageviews
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let rawDay = try c.decode(HogQLScalar.self)
        day = rawDay.stringValue.flatMap(FlexibleDate.parse) ?? .distantPast
        visitors = try c.decode(HogQLScalar.self).intValue
        pageviews = try c.decode(HogQLScalar.self).intValue
    }
}

/// Q3 row: (country_code, country, visitors, pageviews)
public struct CountryRow: Decodable, Sendable, Equatable {
    public let countryCode: String
    public let country: String
    public let visitors: Int
    public let pageviews: Int

    public init(countryCode: String, country: String, visitors: Int, pageviews: Int) {
        self.countryCode = countryCode
        self.country = country
        self.visitors = visitors
        self.pageviews = pageviews
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        countryCode = try c.decode(HogQLScalar.self).stringValue ?? "??"
        country = try c.decode(HogQLScalar.self).stringValue ?? "Unknown"
        visitors = try c.decode(HogQLScalar.self).intValue
        pageviews = try c.decode(HogQLScalar.self).intValue
    }
}

/// Q4 row: (city, country, country_code, device_type, visitors, pageviews)
public struct CityRow: Decodable, Sendable, Equatable {
    public let city: String
    public let country: String
    public let countryCode: String
    public let deviceType: DeviceType
    public let visitors: Int
    public let pageviews: Int

    public init(city: String, country: String, countryCode: String,
                deviceType: DeviceType, visitors: Int, pageviews: Int) {
        self.city = city
        self.country = country
        self.countryCode = countryCode
        self.deviceType = deviceType
        self.visitors = visitors
        self.pageviews = pageviews
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        city = try c.decode(HogQLScalar.self).stringValue ?? "Unknown"
        country = try c.decode(HogQLScalar.self).stringValue ?? "Unknown"
        countryCode = try c.decode(HogQLScalar.self).stringValue ?? "??"
        deviceType = DeviceType(label: try c.decode(HogQLScalar.self).stringValue)
        visitors = try c.decode(HogQLScalar.self).intValue
        pageviews = try c.decode(HogQLScalar.self).intValue
    }
}

/// Q5 row: (visitors)
public struct UnknownRow: Decodable, Sendable, Equatable {
    public let visitors: Int

    public init(visitors: Int) { self.visitors = visitors }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        visitors = try c.decode(HogQLScalar.self).intValue
    }
}

// MARK: Folded domain models

public struct CountryStat: Codable, Sendable, Equatable, Identifiable {
    public let countryCode: String
    public let country: String
    public let visitors: Int
    public let pageviews: Int

    public var id: String { countryCode }
    public var flagEmoji: String { Formatting.flagEmoji(countryCode: countryCode) }

    public init(row: CountryRow) {
        countryCode = row.countryCode
        country = row.country
        visitors = row.visitors
        pageviews = row.pageviews
    }

    public init(countryCode: String, country: String, visitors: Int, pageviews: Int) {
        self.countryCode = countryCode
        self.country = country
        self.visitors = visitors
        self.pageviews = pageviews
    }

    /// Aggregates Q4 city rows per country. Used by the widget, whose per-reload
    /// budget is two HogQL queries (§7): countries are derived from the city
    /// query instead of also issuing Q3. City-less events are absent here, so
    /// this is a lower bound; the app's Regions tab uses the exact Q3 instead.
    public static func fold(fromCityRows rows: [CityRow]) -> [CountryStat] {
        var order: [String] = []
        var acc: [String: (name: String, visitors: Int, pageviews: Int)] = [:]
        for row in rows {
            if acc[row.countryCode] == nil {
                order.append(row.countryCode)
                acc[row.countryCode] = (row.country, 0, 0)
            }
            acc[row.countryCode]!.visitors += row.visitors
            acc[row.countryCode]!.pageviews += row.pageviews
        }
        return order
            .map { code in
                let v = acc[code]!
                return CountryStat(countryCode: code, country: v.name,
                                   visitors: v.visitors, pageviews: v.pageviews)
            }
            .sorted { $0.visitors > $1.visitors }
    }
}

/// One city with its device breakdown, folded from Q4's per-(city, device) rows.
///
/// `visitors` is the sum of per-device unique counts; a person browsing the
/// same city from two device types counts once per device. The UI labels the
/// split accordingly ("280 mobile, 120 desktop") rather than implying a
/// deduplicated total.
public struct CityStat: Codable, Sendable, Equatable, Identifiable {
    public let city: String
    public let country: String
    public let countryCode: String
    public let visitors: Int
    public let pageviews: Int
    public let deviceSplit: [DeviceType: Int]

    public var id: String { "\(city)|\(countryCode)" }
    public var flagEmoji: String { Formatting.flagEmoji(countryCode: countryCode) }

    public init(city: String, country: String, countryCode: String,
                visitors: Int, pageviews: Int, deviceSplit: [DeviceType: Int]) {
        self.city = city
        self.country = country
        self.countryCode = countryCode
        self.visitors = visitors
        self.pageviews = pageviews
        self.deviceSplit = deviceSplit
    }

    /// Folds one row per (city, device) into one entry per city, summing
    /// visitors/pageviews and accumulating the device split. Order: visitors desc.
    public static func fold(rows: [CityRow]) -> [CityStat] {
        struct Key: Hashable { let city: String; let countryCode: String }
        var order: [Key] = []
        var acc: [Key: (country: String, visitors: Int, pageviews: Int, split: [DeviceType: Int])] = [:]

        for row in rows {
            let key = Key(city: row.city, countryCode: row.countryCode)
            if acc[key] == nil {
                order.append(key)
                acc[key] = (row.country, 0, 0, [:])
            }
            acc[key]!.visitors += row.visitors
            acc[key]!.pageviews += row.pageviews
            acc[key]!.split[row.deviceType, default: 0] += row.visitors
        }

        return order
            .map { key in
                let v = acc[key]!
                return CityStat(city: key.city, country: v.country, countryCode: key.countryCode,
                                visitors: v.visitors, pageviews: v.pageviews, deviceSplit: v.split)
            }
            .sorted { $0.visitors > $1.visitors }
    }
}

public struct TrendPoint: Codable, Sendable, Equatable, Identifiable {
    public let day: Date
    public let visitors: Int
    public let pageviews: Int

    public var id: Date { day }

    public init(row: TrendRow) {
        day = row.day
        visitors = row.visitors
        pageviews = row.pageviews
    }

    public init(day: Date, visitors: Int, pageviews: Int) {
        self.day = day
        self.visitors = visitors
        self.pageviews = pageviews
    }
}
