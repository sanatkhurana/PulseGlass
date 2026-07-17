import Foundation
import SwiftUI
import WidgetKit
import AnalyticsKit

/// Central observable state: profiles, the active connection, fetched data,
/// and the cache-aware refresh orchestration described in §7.
@MainActor
@Observable
final class AppModel {

    // MARK: Connection state

    private(set) var profiles: [Profile] = []
    var activeProfileID: UUID?

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID } ?? profiles.first
    }

    var needsOnboarding: Bool { profiles.isEmpty }

    // MARK: Dashboard / Regions data

    var range: DateRange = .week
    private(set) var digest: WeeklyDigest?
    private(set) var trend: [TrendPoint] = []
    private(set) var countries: [CountryStat] = []
    private(set) var cities: [CityStat] = []
    private(set) var unknownVisitors: Int?
    private(set) var lastUpdated: Date?
    private(set) var servedFromPostHogCache = false
    private(set) var isRefreshing = false
    private(set) var isOffline = false

    /// True while a newly selected range has no cached snapshot and its data
    /// is still loading — drives the skeleton/redacted state on the Dashboard.
    private(set) var isSwitchingRange = false

    /// Refreshes may overlap (range switch + pull-to-refresh); count them so
    /// `isRefreshing` only clears when the last one finishes.
    private var activeRefreshCount = 0 {
        didSet { isRefreshing = activeRefreshCount > 0 }
    }

    /// One-line banner for rate limits and auth problems (§9).
    var banner: String?

    /// Diagnostics for Settings (§5.5).
    private(set) var lastHTTPStatusByEndpoint: [String: String] = [:]
    private(set) var lastQueryNames: [String] = []

    // MARK: Navigation

    enum TabSelection: Hashable { case dashboard, regions, settings, search }
    var selectedTab: TabSelection = .dashboard
    var regionsFocusCity: String?

    // MARK: Infrastructure

    private let profileStore: ProfileStore
    private let snapshotStore: SnapshotStore
    private var cachePolicy = CachePolicy()
    private var clients: [UUID: PostHogClient] = [:]

    /// Demo mode renders bundled sample data with no network access — for
    /// exploring the UI without a PostHog account. In-memory only; nothing is
    /// written to the Keychain or App Group.
    private(set) var isDemo = false

    init(profileStore: ProfileStore = ProfileStore(), snapshotStore: SnapshotStore = SnapshotStore()) {
        self.profileStore = profileStore
        self.snapshotStore = snapshotStore
        profiles = profileStore.loadProfiles()
        activeProfileID = profiles.first?.id
        warmStart()
        if profiles.isEmpty, ProcessInfo.processInfo.arguments.contains("-pulseglass-demo") {
            enableDemo()
        }
        // `-pulseglass-url pulseglass://…` routes through the DeepLink parser
        // at launch (used by UI verification; harmless otherwise).
        if let raw = UserDefaults.standard.string(forKey: "pulseglass-url"),
           let url = URL(string: raw) {
            handle(url: url)
        }
    }

    func enableDemo() {
        isDemo = true
        let demo = Profile(id: SampleData.profileID, name: "Demo",
                           host: URL(string: "https://us.posthog.com")!, projectID: 0)
        profiles = [demo]
        activeProfileID = demo.id
        apply(snapshot: SampleData.snapshot(range: range))
    }

    // MARK: Warm start (§7: 0 network calls before first paint)

    @discardableResult
    func warmStart() -> Bool {
        guard let profile = activeProfile,
              let snapshot = snapshotStore.load(profileID: profile.id, range: range) else { return false }
        apply(snapshot: snapshot)
        return true
    }

    private func apply(snapshot: Snapshot) {
        digest = snapshot.digest
        trend = snapshot.trend
        countries = snapshot.countries
        cities = snapshot.cities
        unknownVisitors = snapshot.unknownVisitors
        lastUpdated = snapshot.fetchedAt
    }

    // MARK: Client access

    func client(for profile: Profile) -> PostHogClient {
        if let existing = clients[profile.id] { return existing }
        let store = profileStore
        let profileID = profile.id
        let client = PostHogClient(config: .init(
            host: profile.host,
            projectID: profile.projectID,
            apiKey: { try store.apiKey(for: profileID) }
        ))
        clients[profile.id] = client
        return client
    }

    // MARK: Refresh (§7 call budget: 1 digest + up to 3 queries; Q5 lazily)

    func refresh(force: Bool = false) async {
        if isDemo {
            apply(snapshot: SampleData.snapshot(range: range))
            return
        }
        guard let profile = activeProfile else { return }
        activeRefreshCount += 1
        defer { activeRefreshCount -= 1 }

        let client = client(for: profile)
        let now = Date()
        let range = self.range

        let trendQuery = HogQL.trend(range: range)
        let countriesQuery = HogQL.countries(range: range)
        let citiesQuery = HogQL.cities(range: range)

        let digestKey = "digest.\(range.days)"
        let needDigest = force || cachePolicy.shouldRefetch(key: digestKey, now: now)
        let needTrend = force || cachePolicy.shouldRefetch(key: cacheKey(trendQuery, range), now: now)
        let needCountries = force || cachePolicy.shouldRefetch(key: cacheKey(countriesQuery, range), now: now)
        let needCities = force || cachePolicy.shouldRefetch(key: cacheKey(citiesQuery, range), now: now)

        // Digest + Q2–Q4 run concurrently (they are independent), Result-typed
        // so one failure doesn't lose the other responses.
        async let digestFetch = Self.capture(if: needDigest) {
            try await client.weeklyDigest(days: range.days)
        }
        async let trendFetch = Self.capture(if: needTrend) {
            try await client.hogQL(trendQuery, as: TrendRow.self)
        }
        async let countriesFetch = Self.capture(if: needCountries) {
            try await client.hogQL(countriesQuery, as: CountryRow.self)
        }
        async let citiesFetch = Self.capture(if: needCities) {
            try await client.hogQL(citiesQuery, as: CityRow.self)
        }
        let (digestResult, trendResult, countriesResult, citiesResult) =
            await (digestFetch, trendFetch, countriesFetch, citiesFetch)

        // The user picked a different range while these were in flight —
        // discard rather than overwrite the newer range's data.
        guard self.range == range else { return }

        var failed = false
        if let digestResult {
            switch digestResult {
            case .success(let value):
                digest = value
                cachePolicy.recordFetch(key: digestKey, at: now, cacheTargetAge: nil)
                recordStatus("weekly_digest", "200")
                isOffline = false
            case .failure(let error):
                failed = true
                handle(error: error, endpoint: "weekly_digest")
            }
        }
        applyQueryResult(trendResult, query: trendQuery, range: range, now: now, failed: &failed) { envelope in
            self.trend = envelope.results.map(TrendPoint.init)
            self.servedFromPostHogCache = envelope.isCached ?? false
        }
        applyQueryResult(countriesResult, query: countriesQuery, range: range, now: now, failed: &failed) { envelope in
            self.countries = envelope.results.map(CountryStat.init)
        }
        applyQueryResult(citiesResult, query: citiesQuery, range: range, now: now, failed: &failed) { envelope in
            self.cities = CityStat.fold(rows: envelope.results)
        }

        if !failed {
            lastUpdated = now
            banner = nil
            persistSnapshot()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.visitors)
        }
    }

    /// Runs `operation` when `needed`, capturing the outcome as a `Result` so
    /// concurrent fetches can be awaited together without one throw
    /// cancelling the rest.
    private static func capture<T: Sendable>(
        if needed: Bool,
        _ operation: @Sendable () async throws -> T
    ) async -> Result<T, Error>? {
        guard needed else { return nil }
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }

    private func cacheKey(_ query: HogQLRequest, _ range: DateRange) -> String {
        query.name + ".\(range.days)"
    }

    /// Q5 — fetched lazily when the Regions tab appears (§7).
    func refreshUnknownLocations() async {
        guard !isDemo, let profile = activeProfile else { return }
        let query = HogQL.unknownLocations(range: range)
        let now = Date()
        guard cachePolicy.shouldRefetch(key: query.name + ".\(range.days)", now: now) else { return }
        do {
            let envelope = try await client(for: profile).hogQL(query, as: UnknownRow.self)
            unknownVisitors = envelope.results.first?.visitors
            cachePolicy.recordFetch(key: query.name + ".\(range.days)", at: now,
                                    cacheTargetAge: envelope.cacheTargetAge)
            recordQueryName(query.name)
        } catch {
            handle(error: error, endpoint: query.name)
        }
    }

    private func applyQueryResult<Row: Decodable & Sendable>(
        _ result: Result<QueryEnvelope<Row>, Error>?,
        query: HogQLRequest, range: DateRange, now: Date, failed: inout Bool,
        apply: (QueryEnvelope<Row>) -> Void
    ) {
        guard let result else { return } // cache still valid; nothing fetched
        switch result {
        case .success(let envelope):
            apply(envelope)
            cachePolicy.recordFetch(key: cacheKey(query, range), at: now,
                                    cacheTargetAge: envelope.cacheTargetAge)
            recordStatus("query", "200")
            recordQueryName(query.name)
        case .failure(let error):
            // HogQL errors are card-level and non-fatal (§9); everything else
            // marks the refresh failed so the snapshot is not overwritten.
            if let posthogError = error as? PostHogError,
               case .hogQLError(let detail) = posthogError {
                recordStatus(query.name, "400 \(detail)")
            } else {
                failed = true
                handle(error: error, endpoint: query.name)
            }
        }
    }

    private func handle(error: Error, endpoint: String) {
        guard let posthogError = error as? PostHogError else {
            recordStatus(endpoint, "error")
            return
        }
        switch posthogError {
        case .rateLimited:
            banner = "PostHog rate limit reached — showing cached data"
            recordStatus(endpoint, "429")
        case .invalidKey:
            banner = "API key invalid or revoked — check Settings"
            recordStatus(endpoint, "401")
        case .insufficientScope:
            banner = "API key is missing web_analytics:read or query:read scope"
            recordStatus(endpoint, "403")
        case .notFound:
            banner = "Project not found — check host and project ID"
            recordStatus(endpoint, "404")
        case .transport:
            isOffline = true
            recordStatus(endpoint, "offline")
        case .hogQLError(let detail):
            recordStatus(endpoint, "400 \(detail)")
        case .decoding:
            recordStatus(endpoint, "decode error")
        case .unexpectedStatus(let code):
            recordStatus(endpoint, "\(code)")
        }
    }

    private func recordStatus(_ endpoint: String, _ status: String) {
        lastHTTPStatusByEndpoint[endpoint] = status
    }

    private func recordQueryName(_ name: String) {
        lastQueryNames.removeAll { $0 == name }
        lastQueryNames.append(name)
        if lastQueryNames.count > 8 { lastQueryNames.removeFirst() }
    }

    private func persistSnapshot() {
        guard let profile = activeProfile else { return }
        let snapshot = Snapshot(
            profileID: profile.id, fetchedAt: Date(), range: range,
            digest: digest, trend: trend, countries: countries,
            cities: cities, unknownVisitors: unknownVisitors
        )
        try? snapshotStore.save(snapshot)
    }

    // MARK: Range switching (§7: cached per range)

    func setRange(_ newRange: DateRange) async {
        guard newRange != range else { return }
        range = newRange
        if isDemo {
            // Simulate a short fetch so the loading affordance (spinner +
            // skeleton) is visible in demo mode too.
            isSwitchingRange = true
            try? await Task.sleep(for: .milliseconds(350))
            guard range == newRange else { return } // superseded by a newer tap
            apply(snapshot: SampleData.snapshot(range: newRange))
            isSwitchingRange = false
            return
        }
        // Paint instantly from the new range's snapshot when one exists; only
        // show the skeleton state when there is nothing cached to show.
        let hasCachedSnapshot = warmStart()
        isSwitchingRange = !hasCachedSnapshot
        await refresh()
        // Only clear the skeleton if a newer switch hasn't superseded this one.
        if range == newRange { isSwitchingRange = false }
    }

    // MARK: Profile management (§4.1, §5.5)

    /// Adds a connection and makes it the active one immediately, so
    /// "connect to a different dashboard" is a single flow.
    func addProfile(name: String, host: URL, projectID: Int, apiKey: String) throws {
        if isDemo {
            // Demo is in-memory only; a real connection replaces it.
            isDemo = false
            profiles = []
            activeProfileID = nil
        }
        let profile = Profile(name: name, host: host, projectID: projectID)
        try profileStore.setAPIKey(apiKey, for: profile.id)
        profiles.append(profile)
        try profileStore.saveProfiles(profiles)
        setActiveProfile(profile)
    }

    /// Switches the active connection, clearing the previous project's data
    /// so nothing stale lingers, then warm-starts from the new profile's
    /// snapshot. Callers refresh afterwards.
    func setActiveProfile(_ profile: Profile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        activeProfileID = profile.id
        digest = nil
        trend = []
        countries = []
        cities = []
        unknownVisitors = nil
        lastUpdated = nil
        banner = nil
        cachePolicy = CachePolicy()
        warmStart()
    }

    func removeProfile(_ profile: Profile) {
        try? profileStore.removeProfile(profile.id)
        profiles.removeAll { $0.id == profile.id }
        clients[profile.id] = nil
        if activeProfileID == profile.id {
            activeProfileID = profiles.first?.id
        }
    }

    func apiKeyPreview(for profile: Profile) -> String {
        (try? profileStore.apiKey(for: profile.id)).map(Profile.keyPreview) ?? "—"
    }

    func clearCachedSnapshots() {
        try? snapshotStore.wipeAll()
        cachePolicy = CachePolicy()
    }

    /// Destructive sign-out: wipes Keychain items and App Group snapshots (§5.5).
    /// Also exits demo mode.
    func signOut() {
        isDemo = false
        try? profileStore.wipeAll()
        try? snapshotStore.wipeAll()
        profiles = []
        activeProfileID = nil
        clients = [:]
        digest = nil
        trend = []
        countries = []
        cities = []
        unknownVisitors = nil
        lastUpdated = nil
        banner = nil
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.visitors)
    }

    // MARK: Deep links (§6.1)

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .dashboard(let linkRange):
            selectedTab = .dashboard
            if linkRange != range {
                Task { await setRange(linkRange) }
            }
        case .regions(let city):
            selectedTab = .regions
            regionsFocusCity = city
        case .onboarding:
            break // onboarding is presented automatically when no profile exists
        }
    }
}
