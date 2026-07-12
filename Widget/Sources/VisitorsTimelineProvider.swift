import WidgetKit
import Foundation
import AnalyticsKit

// MARK: - Timeline entry

struct VisitorsEntry: TimelineEntry {
    enum State {
        /// No profile configured yet — "Open PulseGlass to connect" (§6.5).
        case needsSetup
        /// Rendering data (fresh or from the last-good snapshot).
        case data(Snapshot, isStale: Bool, locations: LocationsShown)
    }

    let date: Date
    let state: State

    static func sample(date: Date = Date()) -> VisitorsEntry {
        VisitorsEntry(date: date, state: .data(SampleData.snapshot(asOf: date),
                                               isStale: false, locations: .cities))
    }
}

// MARK: - Provider (§6.2)

struct VisitorsTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> VisitorsEntry {
        // Bundled sample data; redaction-friendly.
        .sample()
    }

    func snapshot(for configuration: SelectProfileIntent, in context: Context) async -> VisitorsEntry {
        // Widget gallery must be instant: App Group snapshot, no network.
        let store = SnapshotStore()
        if let profile = resolveProfile(configuration),
           let snapshot = store.load(profileID: profile.id, range: .week) {
            return VisitorsEntry(date: Date(),
                                 state: .data(snapshot, isStale: false, locations: configuration.locations))
        }
        return .sample()
    }

    func timeline(for configuration: SelectProfileIntent, in context: Context) async -> Timeline<VisitorsEntry> {
        let now = Date()
        guard let profile = resolveProfile(configuration) else {
            // Retry occasionally in case the user connects a profile later.
            return Timeline(entries: [VisitorsEntry(date: now, state: .needsSetup)],
                            policy: .after(now.addingTimeInterval(30 * 60)))
        }

        let store = SnapshotStore()
        let fetched = await fetchSnapshot(profile: profile, now: now, store: store)
        let plan = TimelinePlanner.plan(
            fetched: fetched,
            fallback: store.load(profileID: profile.id, range: .week),
            now: now
        )

        let state: VisitorsEntry.State
        if let snapshot = plan.snapshot {
            state = .data(snapshot, isStale: plan.isStale, locations: configuration.locations)
        } else {
            state = .needsSetup
        }
        return Timeline(entries: [VisitorsEntry(date: now, state: state)],
                        policy: .after(plan.reloadAfter))
    }

    private func resolveProfile(_ configuration: SelectProfileIntent) -> Profile? {
        let profiles = ProfileStore().loadProfiles()
        if let selected = configuration.profile {
            return profiles.first { $0.id == selected.id }
        }
        return profiles.first
    }

    /// 1 × digest + 2 × /query per timeline reload (§6.2, §7). Failures return
    /// nil so the planner falls back to the last-good snapshot. A HogQL-only
    /// failure drops the geo section but keeps the count (§9).
    private func fetchSnapshot(profile: Profile, now: Date, store: SnapshotStore) async -> Snapshot? {
        let profileStore = ProfileStore()
        let profileID = profile.id
        let client = PostHogClient(config: .init(
            host: profile.host,
            projectID: profile.projectID,
            apiKey: { try profileStore.apiKey(for: profileID) },
            timeout: 12 // widget budget (§4.2)
        ))

        guard let digest = try? await client.weeklyDigest(days: 7) else {
            return nil
        }

        let trend = (try? await client.hogQL(HogQL.trend(range: .week), as: TrendRow.self))?
            .results.map(TrendPoint.init) ?? []
        let cityRows = (try? await client.hogQL(HogQL.cities(range: .week), as: CityRow.self))?
            .results ?? []

        let snapshot = Snapshot(
            profileID: profile.id, fetchedAt: now, range: .week,
            digest: digest, trend: trend,
            countries: CountryStat.fold(fromCityRows: cityRows),
            cities: CityStat.fold(rows: cityRows), unknownVisitors: nil
        )
        try? store.save(snapshot)
        return snapshot
    }
}
