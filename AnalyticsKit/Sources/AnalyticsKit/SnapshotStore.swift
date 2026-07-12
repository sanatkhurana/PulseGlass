import Foundation

// MARK: - Last-good snapshots in the App Group container (§3, §6.5, §7)

/// The merged last-good payload shared between app and widget. Aggregates
/// only — no API key, no per-person data (§8).
public struct Snapshot: Codable, Sendable, Equatable {
    public let profileID: UUID
    public let fetchedAt: Date
    public let range: DateRange
    public let digest: WeeklyDigest?
    public let trend: [TrendPoint]
    public let countries: [CountryStat]
    public let cities: [CityStat]
    public let unknownVisitors: Int?

    public init(profileID: UUID, fetchedAt: Date, range: DateRange = .week,
                digest: WeeklyDigest?, trend: [TrendPoint] = [],
                countries: [CountryStat] = [], cities: [CityStat] = [],
                unknownVisitors: Int? = nil) {
        self.profileID = profileID
        self.fetchedAt = fetchedAt
        self.range = range
        self.digest = digest
        self.trend = trend
        self.countries = countries
        self.cities = cities
        self.unknownVisitors = unknownVisitors
    }

    /// Entries older than 12 h render dimmed with a stale badge (§6.2).
    public func isStale(asOf now: Date = Date(), threshold: TimeInterval = 12 * 3600) -> Bool {
        now.timeIntervalSince(fetchedAt) > threshold
    }
}

public struct SnapshotStore: Sendable {
    public static let appGroupID = "group.com.example.pulseglass"

    public let directory: URL

    /// Resolves the shared App Group container, falling back to caches when
    /// the entitlement is unavailable (unit tests, previews).
    public init(appGroupID: String = SnapshotStore.appGroupID) {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            directory = container.appending(path: "Snapshots", directoryHint: .isDirectory)
        } else {
            directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appending(path: "PulseGlassSnapshots", directoryHint: .isDirectory)
        }
    }

    /// Injectable directory for tests.
    public init(directory: URL) {
        self.directory = directory
    }

    private func fileURL(profileID: UUID, range: DateRange) -> URL {
        directory.appending(path: "snapshot-\(profileID.uuidString)-\(range.days)d.json")
    }

    public func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(profileID: snapshot.profileID, range: snapshot.range), options: .atomic)
    }

    public func load(profileID: UUID, range: DateRange = .week) -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL(profileID: profileID, range: range)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    /// Wipes all cached snapshots (sign-out, "Clear cached snapshots").
    public func wipeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Client-side refetch gate (§7)

/// Persists PostHog's `cache_target_age` per query name and applies a client
/// TTL floor, so identical queries are never re-issued while either window is
/// still valid. Pure logic; persistence is a plain JSON file next to snapshots.
public struct CachePolicy: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public let fetchedAt: Date
        public let cacheTargetAge: Date?

        public init(fetchedAt: Date, cacheTargetAge: Date?) {
            self.fetchedAt = fetchedAt
            self.cacheTargetAge = cacheTargetAge
        }
    }

    public let clientTTL: TimeInterval
    private var entries: [String: Entry]

    public init(clientTTL: TimeInterval = 5 * 60, entries: [String: Entry] = [:]) {
        self.clientTTL = clientTTL
        self.entries = entries
    }

    public mutating func recordFetch(key: String, at date: Date, cacheTargetAge: Date?) {
        entries[key] = Entry(fetchedAt: date, cacheTargetAge: cacheTargetAge)
    }

    /// True when the query should hit the network: no record, client TTL
    /// elapsed, *and* the server's cache window has lapsed.
    public func shouldRefetch(key: String, now: Date) -> Bool {
        guard let entry = entries[key] else { return true }
        if now.timeIntervalSince(entry.fetchedAt) < clientTTL { return false }
        if let target = entry.cacheTargetAge, now < target { return false }
        return true
    }

    public var allEntries: [String: Entry] { entries }
}
