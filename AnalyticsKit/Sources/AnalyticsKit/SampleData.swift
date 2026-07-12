import Foundation

// MARK: - Bundled sample data (widget gallery placeholder, previews) (§6.2)

public enum SampleData {

    public static let profileID = UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF")!

    public static var digest: WeeklyDigest {
        func change(_ percent: Double, _ direction: WeeklyDigest.ChangeDirection) -> WeeklyDigest.Change {
            WeeklyDigest.Change(
                percent: percent, direction: direction,
                text: "\(direction == .up ? "▲" : "▼") \(Formatting.percent(abs(percent)))",
                longText: "\(direction == .up ? "Up" : "Down") \(Formatting.percent(abs(percent))) from the previous period"
            )
        }
        return WeeklyDigest(
            visitors: .init(current: 12437, previous: 11494, change: change(8.2, .up)),
            pageviews: .init(current: 48210, previous: 45930, change: change(5.0, .up)),
            sessions: .init(current: 16780, previous: 17240, change: change(-2.7, .down)),
            bounceRate: .init(current: 0.42, previous: 0.45, change: change(-6.7, .down)),
            avgSessionDuration: .init(current: 154, previous: 149, change: change(3.4, .up)),
            topPages: [
                .init(host: "example.com", path: "/", visitors: 5210, change: change(4.1, .up)),
                .init(host: "example.com", path: "/pricing", visitors: 2380, change: change(12.9, .up)),
                .init(host: "example.com", path: "/blog", visitors: 1910, change: change(-1.8, .down)),
            ],
            topSources: [
                .init(name: "Google", visitors: 6120, change: change(6.3, .up)),
                .init(name: "Direct", visitors: 3480, change: change(1.2, .up)),
                .init(name: "GitHub", visitors: 980, change: change(22.5, .up)),
            ],
            goals: [],
            dashboardURL: URL(string: "https://us.posthog.com/project/1/web/analytics")
        )
    }

    public static var trend: [TrendPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let visitors = [1512, 1688, 1745, 1820, 1610, 1930, 2132]
        let pageviews = [5910, 6480, 6702, 7150, 6244, 7480, 8244]
        return (0..<7).map { i in
            TrendPoint(
                day: calendar.date(byAdding: .day, value: i - 6, to: today)!,
                visitors: visitors[i],
                pageviews: pageviews[i]
            )
        }
    }

    public static var countries: [CountryStat] {
        [
            .init(countryCode: "US", country: "United States", visitors: 4820, pageviews: 19240),
            .init(countryCode: "DE", country: "Germany", visitors: 2110, pageviews: 8103),
            .init(countryCode: "GB", country: "United Kingdom", visitors: 1608, pageviews: 6220),
            .init(countryCode: "IN", country: "India", visitors: 1245, pageviews: 4470),
            .init(countryCode: "FR", country: "France", visitors: 830, pageviews: 3110),
        ]
    }

    public static var cities: [CityStat] {
        [
            .init(city: "Berlin", country: "Germany", countryCode: "DE",
                  visitors: 412, pageviews: 1620, deviceSplit: [.mobile: 280, .desktop: 120, .tablet: 12]),
            .init(city: "San Francisco", country: "United States", countryCode: "US",
                  visitors: 391, pageviews: 1804, deviceSplit: [.desktop: 301, .mobile: 84, .tablet: 6]),
            .init(city: "London", country: "United Kingdom", countryCode: "GB",
                  visitors: 342, pageviews: 1310, deviceSplit: [.mobile: 190, .desktop: 148, .tablet: 4]),
            .init(city: "Bengaluru", country: "India", countryCode: "IN",
                  visitors: 297, pageviews: 1002, deviceSplit: [.mobile: 232, .desktop: 65]),
            .init(city: "Paris", country: "France", countryCode: "FR",
                  visitors: 214, pageviews: 803, deviceSplit: [.mobile: 120, .desktop: 90, .tablet: 4]),
        ]
    }

    public static func snapshot(asOf date: Date = Date()) -> Snapshot {
        Snapshot(profileID: profileID, fetchedAt: date, range: .week,
                 digest: digest, trend: trend, countries: countries,
                 cities: cities, unknownVisitors: 118)
    }
}
