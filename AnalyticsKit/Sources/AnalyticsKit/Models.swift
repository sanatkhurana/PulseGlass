import Foundation

// MARK: - Weekly digest (§2.1)

/// Decoded response of `GET /api/projects/:id/web_analytics/weekly_digest/`.
/// Decoding is defensive throughout: every field is optional-tolerant so a
/// server-side schema addition or omission never crashes the app or widget.
public struct WeeklyDigest: Codable, Sendable, Equatable {

    public enum ChangeDirection: String, Codable, Sendable, Equatable {
        case up, down, flat

        /// Unknown direction strings map to `.flat` rather than failing decode.
        public init(from decoder: Decoder) throws {
            let raw = try? decoder.singleValueContainer().decode(String.self)
            self = ChangeDirection(rawValue: raw?.lowercased() ?? "") ?? .flat
        }
    }

    public struct Change: Codable, Sendable, Equatable {
        public let percent: Double
        public let direction: ChangeDirection
        public let text: String?
        public let longText: String?

        enum CodingKeys: String, CodingKey {
            case percent, direction, text
            case longText = "long_text"
        }

        public init(percent: Double, direction: ChangeDirection, text: String? = nil, longText: String? = nil) {
            self.percent = percent
            self.direction = direction
            self.text = text
            self.longText = longText
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            percent = (try? c.decodeIfPresent(Double.self, forKey: .percent)) ?? 0
            direction = (try? c.decodeIfPresent(ChangeDirection.self, forKey: .direction)) ?? .flat
            text = try? c.decodeIfPresent(String.self, forKey: .text)
            longText = try? c.decodeIfPresent(String.self, forKey: .longText)
        }
    }

    public struct Metric: Codable, Sendable, Equatable {
        public let current: Double
        public let previous: Double?
        public let change: Change?

        public init(current: Double, previous: Double? = nil, change: Change? = nil) {
            self.current = current
            self.previous = previous
            self.change = change
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            current = (try? c.decodeIfPresent(Double.self, forKey: .current)) ?? 0
            previous = try? c.decodeIfPresent(Double.self, forKey: .previous)
            change = try? c.decodeIfPresent(Change.self, forKey: .change)
        }

        enum CodingKeys: String, CodingKey { case current, previous, change }
    }

    /// Same shape as `Metric`; the value is seconds and is formatted as a duration.
    public typealias DurationMetric = Metric

    public struct TopPage: Codable, Sendable, Equatable {
        public let host: String?
        public let path: String
        public let visitors: Int
        public let change: Change?

        public init(host: String?, path: String, visitors: Int, change: Change? = nil) {
            self.host = host
            self.path = path
            self.visitors = visitors
            self.change = change
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            host = try? c.decodeIfPresent(String.self, forKey: .host)
            path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? ""
            visitors = (try? c.decodeIfPresent(Int.self, forKey: .visitors)) ?? 0
            change = try? c.decodeIfPresent(Change.self, forKey: .change)
        }

        enum CodingKeys: String, CodingKey { case host, path, visitors, change }
    }

    public struct TopSource: Codable, Sendable, Equatable {
        public let name: String
        public let visitors: Int
        public let change: Change?

        public init(name: String, visitors: Int, change: Change? = nil) {
            self.name = name
            self.visitors = visitors
            self.change = change
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            visitors = (try? c.decodeIfPresent(Int.self, forKey: .visitors)) ?? 0
            change = try? c.decodeIfPresent(Change.self, forKey: .change)
        }

        enum CodingKeys: String, CodingKey { case name, visitors, change }
    }

    public struct Goal: Codable, Sendable, Equatable {
        public let name: String
        public let conversions: Int
        public let change: Change?

        public init(name: String, conversions: Int, change: Change? = nil) {
            self.name = name
            self.conversions = conversions
            self.change = change
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            conversions = (try? c.decodeIfPresent(Int.self, forKey: .conversions)) ?? 0
            change = try? c.decodeIfPresent(Change.self, forKey: .change)
        }

        enum CodingKeys: String, CodingKey { case name, conversions, change }
    }

    public let visitors: Metric
    public let pageviews: Metric
    public let sessions: Metric
    public let bounceRate: Metric
    public let avgSessionDuration: DurationMetric
    public let topPages: [TopPage]
    public let topSources: [TopSource]
    public let goals: [Goal]
    public let dashboardURL: URL?

    enum CodingKeys: String, CodingKey {
        case visitors, pageviews, sessions, goals
        case bounceRate = "bounce_rate"
        case avgSessionDuration = "avg_session_duration"
        case topPages = "top_pages"
        case topSources = "top_sources"
        case dashboardURL = "dashboard_url"
    }

    public init(
        visitors: Metric, pageviews: Metric, sessions: Metric,
        bounceRate: Metric, avgSessionDuration: DurationMetric,
        topPages: [TopPage] = [], topSources: [TopSource] = [],
        goals: [Goal] = [], dashboardURL: URL? = nil
    ) {
        self.visitors = visitors
        self.pageviews = pageviews
        self.sessions = sessions
        self.bounceRate = bounceRate
        self.avgSessionDuration = avgSessionDuration
        self.topPages = topPages
        self.topSources = topSources
        self.goals = goals
        self.dashboardURL = dashboardURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let zero = Metric(current: 0)
        visitors = (try? c.decodeIfPresent(Metric.self, forKey: .visitors)) ?? zero
        pageviews = (try? c.decodeIfPresent(Metric.self, forKey: .pageviews)) ?? zero
        sessions = (try? c.decodeIfPresent(Metric.self, forKey: .sessions)) ?? zero
        bounceRate = (try? c.decodeIfPresent(Metric.self, forKey: .bounceRate)) ?? zero
        avgSessionDuration = (try? c.decodeIfPresent(Metric.self, forKey: .avgSessionDuration)) ?? zero
        topPages = (try? c.decodeIfPresent([TopPage].self, forKey: .topPages)) ?? []
        topSources = (try? c.decodeIfPresent([TopSource].self, forKey: .topSources)) ?? []
        goals = (try? c.decodeIfPresent([Goal].self, forKey: .goals)) ?? []
        dashboardURL = try? c.decodeIfPresent(URL.self, forKey: .dashboardURL)
    }
}

// MARK: - Setup & validation endpoints (§2.3)

public struct MeUser: Codable, Sendable, Equatable {
    public let uuid: String?
    public let email: String?
    public let firstName: String?

    enum CodingKeys: String, CodingKey {
        case uuid, email
        case firstName = "first_name"
    }
}

public struct OrganizationSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
}

public struct ProjectSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
}

/// Paginated list envelope used by PostHog CRUD list endpoints.
struct ListEnvelope<T: Codable & Sendable>: Codable, Sendable {
    let results: [T]
}
