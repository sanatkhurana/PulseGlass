import Foundation

// MARK: - Bundled sample data (widget gallery placeholder, previews) (§6.2)

public enum SampleData {

    public static let profileID = UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF")!

    public static var digest: WeeklyDigest { digest(range: .week) }

    /// Sample metrics scale with the range so toggling 7D/30D/90D visibly
    /// changes every number, like a real project would.
    public static func digest(range: DateRange) -> WeeklyDigest {
        let factor = scaleFactor(for: range)
        func change(_ percent: Double, _ direction: WeeklyDigest.ChangeDirection) -> WeeklyDigest.Change {
            WeeklyDigest.Change(
                percent: percent, direction: direction,
                text: "\(direction == .up ? "▲" : "▼") \(Formatting.percent(abs(percent)))",
                longText: "\(direction == .up ? "Up" : "Down") \(Formatting.percent(abs(percent))) from the previous period"
            )
        }
        func scaled(_ value: Double) -> Double { (value * factor).rounded() }
        let deltas: (visitors: Double, pageviews: Double, sessions: Double)
        switch range {
        case .week: deltas = (8.2, 5.0, -2.7)
        case .month: deltas = (14.6, 11.3, 4.9)
        case .quarter: deltas = (31.4, 27.8, 19.2)
        }
        return WeeklyDigest(
            visitors: .init(current: scaled(12437), previous: scaled(11494),
                            change: change(deltas.visitors, deltas.visitors >= 0 ? .up : .down)),
            pageviews: .init(current: scaled(48210), previous: scaled(45930),
                             change: change(deltas.pageviews, deltas.pageviews >= 0 ? .up : .down)),
            sessions: .init(current: scaled(16780), previous: scaled(17240),
                            change: change(deltas.sessions, deltas.sessions >= 0 ? .up : .down)),
            bounceRate: .init(current: 0.42, previous: 0.45, change: change(-6.7, .down)),
            avgSessionDuration: .init(current: 154, previous: 149, change: change(3.4, .up)),
            topPages: [
                .init(host: "example.com", path: "/", visitors: Int(scaled(5210)), change: change(4.1, .up)),
                .init(host: "example.com", path: "/pricing", visitors: Int(scaled(2380)), change: change(12.9, .up)),
                .init(host: "example.com", path: "/blog", visitors: Int(scaled(1910)), change: change(-1.8, .down)),
            ],
            topSources: [
                .init(name: "Google", visitors: Int(scaled(6120)), change: change(6.3, .up)),
                .init(name: "Direct", visitors: Int(scaled(3480)), change: change(1.2, .up)),
                .init(name: "GitHub", visitors: Int(scaled(980)), change: change(22.5, .up)),
            ],
            goals: [],
            dashboardURL: URL(string: "https://us.posthog.com/project/1/web/analytics")
        )
    }

    /// Longer ranges accumulate more traffic; sub-linear vs. days because the
    /// sample project is "growing" (recent days are busier).
    private static func scaleFactor(for range: DateRange) -> Double {
        switch range {
        case .week: 1
        case .month: 3.9
        case .quarter: 10.4
        }
    }

    public static var trend: [TrendPoint] { trend(range: .week) }

    /// 7 daily points, 30 daily points, or 13 weekly buckets — mirroring the
    /// real Q2 (toStartOfDay vs. toStartOfWeek for 90d).
    public static func trend(range: DateRange) -> [TrendPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        switch range {
        case .week:
            let visitors = [1512, 1688, 1745, 1820, 1610, 1930, 2132]
            let pageviews = [5910, 6480, 6702, 7150, 6244, 7480, 8244]
            return (0..<7).map { i in
                TrendPoint(day: calendar.date(byAdding: .day, value: i - 6, to: today)!,
                           visitors: visitors[i], pageviews: pageviews[i])
            }
        case .month:
            return (0..<30).map { i in
                // Deterministic weekly seasonality + gentle growth.
                let base = 1350.0 + Double(i) * 14 + 320 * sin(Double(i) * .pi / 3.5)
                return TrendPoint(day: calendar.date(byAdding: .day, value: i - 29, to: today)!,
                                  visitors: Int(base), pageviews: Int(base * 3.9))
            }
        case .quarter:
            return (0..<13).map { i in
                let base = 8200.0 + Double(i) * 310 + 900 * sin(Double(i) * .pi / 2.6)
                return TrendPoint(day: calendar.date(byAdding: .day, value: (i - 12) * 7, to: today)!,
                                  visitors: Int(base), pageviews: Int(base * 3.8))
            }
        }
    }

    public static var countries: [CountryStat] { countries(range: .week) }

    public static func countries(range: DateRange) -> [CountryStat] {
        let f = scaleFactor(for: range)
        return [
            .init(countryCode: "US", country: "United States", visitors: Int(4820 * f), pageviews: Int(19240 * f)),
            .init(countryCode: "DE", country: "Germany", visitors: Int(2110 * f), pageviews: Int(8103 * f)),
            .init(countryCode: "GB", country: "United Kingdom", visitors: Int(1608 * f), pageviews: Int(6220 * f)),
            .init(countryCode: "IN", country: "India", visitors: Int(1245 * f), pageviews: Int(4470 * f)),
            .init(countryCode: "FR", country: "France", visitors: Int(830 * f), pageviews: Int(3110 * f)),
        ]
    }

    public static var cities: [CityStat] { cities(range: .week) }

    public static func cities(range: DateRange) -> [CityStat] {
        let f = scaleFactor(for: range)
        func split(_ pairs: [DeviceType: Int]) -> [DeviceType: Int] {
            pairs.mapValues { Int(Double($0) * f) }
        }
        return [
            .init(city: "Berlin", country: "Germany", countryCode: "DE",
                  visitors: Int(412 * f), pageviews: Int(1620 * f),
                  deviceSplit: split([.mobile: 280, .desktop: 120, .tablet: 12])),
            .init(city: "San Francisco", country: "United States", countryCode: "US",
                  visitors: Int(391 * f), pageviews: Int(1804 * f),
                  deviceSplit: split([.desktop: 301, .mobile: 84, .tablet: 6])),
            .init(city: "London", country: "United Kingdom", countryCode: "GB",
                  visitors: Int(342 * f), pageviews: Int(1310 * f),
                  deviceSplit: split([.mobile: 190, .desktop: 148, .tablet: 4])),
            .init(city: "Bengaluru", country: "India", countryCode: "IN",
                  visitors: Int(297 * f), pageviews: Int(1002 * f),
                  deviceSplit: split([.mobile: 232, .desktop: 65])),
            .init(city: "Paris", country: "France", countryCode: "FR",
                  visitors: Int(214 * f), pageviews: Int(803 * f),
                  deviceSplit: split([.mobile: 120, .desktop: 90, .tablet: 4])),
        ]
    }

    public static func snapshot(asOf date: Date = Date(), range: DateRange = .week) -> Snapshot {
        Snapshot(profileID: profileID, fetchedAt: date, range: range,
                 digest: digest(range: range), trend: trend(range: range),
                 countries: countries(range: range), cities: cities(range: range),
                 unknownVisitors: Int(118 * scaleFactor(for: range)))
    }
}
