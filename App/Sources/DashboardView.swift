import SwiftUI
import Charts
import AnalyticsKit

// MARK: - Dashboard tab (§5.3)

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Namespace private var glassNamespace
    @State private var showAddConnection = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let banner = model.banner {
                        BannerView(text: banner)
                    }
                    if model.isOffline {
                        BannerView(text: "Offline — showing cached data")
                    }
                    // While a freshly selected range loads with no cached
                    // snapshot, the cards render as dimmed skeletons so it's
                    // clear their content is being fetched.
                    Group {
                        OverviewTilesGrid(digest: model.digest)
                        TrendChartCard(trend: model.trend)
                        if let digest = model.digest {
                            TopPagesCard(digest: digest, openDashboard: openDashboard)
                            TopSourcesCard(sources: digest.topSources)
                            if !digest.goals.isEmpty {
                                GoalsCard(goals: digest.goals)
                            }
                        }
                    }
                    .redacted(reason: model.isSwitchingRange ? .placeholder : [])
                    .opacity(model.isSwitchingRange ? 0.55 : 1)
                    .animation(.easeInOut(duration: 0.2), value: model.isSwitchingRange)
                    updatedCaption
                }
                .padding(.horizontal)
                .padding(.bottom, 80)
            }
            .navigationTitle("PulseGlass")
            .refreshable {
                await model.refresh(force: true)
            }
            // Connection switcher: change the PostHog project/host from
            // anywhere, or connect a new one (system glass toolbar button).
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Connection") {
                            ForEach(model.profiles) { profile in
                                Button {
                                    model.setActiveProfile(profile)
                                    Task { await model.refresh(force: true) }
                                } label: {
                                    if profile.id == model.activeProfile?.id {
                                        Label(profile.name, systemImage: "checkmark")
                                    } else {
                                        Text(profile.name)
                                    }
                                }
                            }
                        }
                        Button {
                            showAddConnection = true
                        } label: {
                            Label("Add connection…", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Switch PostHog connection")
                }
            }
            .sheet(isPresented: $showAddConnection) {
                OnboardingView()
            }
            // Range picker: transient chrome pinned above content, so it is
            // the screen's single custom glass surface (§5.3, §5.6).
            .safeAreaInset(edge: .top) {
                RangePicker()
            }
            // Floating refresh button, grouped in the screen's one
            // GlassEffectContainer (§5.3, §10: ≤ 1 container per screen).
            .overlay(alignment: .bottomTrailing) {
                GlassEffectContainer {
                    Button {
                        Task { await model.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .padding(4)
                    }
                    .buttonStyle(.glass)
                    .disabled(model.isRefreshing)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var updatedCaption: some View {
        Group {
            if let updated = model.lastUpdated {
                Text("Updated \(updated, style: .relative) ago\(model.servedFromPostHogCache ? " · cached by PostHog" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openDashboard(_ url: URL) {
        guard let host = model.activeProfile?.host,
              DashboardURLPolicy.isAllowed(url, configuredHost: host) else { return }
        openURL(url)
    }
}

// MARK: - Range picker (custom glass capsule)

struct RangePicker: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DateRange.allCases) { range in
                Button {
                    Task { await model.setRange(range) }
                } label: {
                    Text(range.label)
                        .font(.subheadline.weight(model.range == range ? .bold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .contentShape(Capsule())
                        .background {
                            // The selection is itself a liquid glass lens:
                            // it refracts/magnifies what's beneath it and
                            // slides fluidly between segments.
                            if model.range == range {
                                Color.clear
                                    .glassEffect(.regular.tint(.accentColor.opacity(0.25)).interactive())
                                    .matchedGeometryEffect(id: "range-selection", in: selectionNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            // Inline processing indicator: visible whenever data for the
            // selected range is being fetched.
            if model.isSwitchingRange || model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
        }
        .padding(4)
        // The track is material, not glass — the moving pill is the single
        // glass element here, so glass never stacks on glass.
        .background(.thinMaterial, in: Capsule())
        .animation(.snappy(duration: 0.28), value: model.range)
        .animation(.easeInOut(duration: 0.2), value: model.isSwitchingRange)
        .animation(.easeInOut(duration: 0.2), value: model.isRefreshing)
        .padding(.top, 4)
    }
}

// MARK: - Overview tiles (§5.3.2 — content, material not glass)

struct OverviewTilesGrid: View {
    let digest: WeeklyDigest?

    var body: some View {
        // ViewThatFits reflows 2 columns → 1 at accessibility sizes (§10).
        ViewThatFits(in: .horizontal) {
            grid(columns: 2)
            grid(columns: 1)
        }
        // Drives the tiles' contentTransition(.numericText()) when a new
        // range's numbers arrive.
        .animation(.snappy(duration: 0.3), value: digest)
    }

    private func grid(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            StatCard(title: "Visitors", metric: digest?.visitors) {
                Formatting.abbreviated($0.current)
            }
            StatCard(title: "Pageviews", metric: digest?.pageviews) {
                Formatting.abbreviated($0.current)
            }
            StatCard(title: "Sessions", metric: digest?.sessions) {
                Formatting.abbreviated($0.current)
            }
            StatCard(title: "Bounce rate", metric: digest?.bounceRate) {
                Formatting.bounceRate($0.current)
            }
            StatCard(title: "Avg session", metric: digest?.avgSessionDuration) {
                Formatting.duration(seconds: $0.current)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let metric: WeeklyDigest.Metric?
    let format: (WeeklyDigest.Metric) -> String

    init(title: String, metric: WeeklyDigest.Metric?,
         format: @escaping (WeeklyDigest.Metric) -> String) {
        self.title = title
        self.metric = metric
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(metric.map(format) ?? "—")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())
            DeltaChip(change: metric?.change)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(metric.map(format) ?? "no data"). \(metric?.change?.longText ?? "")")
    }
}

struct DeltaChip: View {
    let change: WeeklyDigest.Change?

    var body: some View {
        if let change {
            Label {
                Text(Formatting.percent(abs(change.percent)))
            } icon: {
                Image(systemName: symbol(for: change.direction))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color(for: change.direction))
            .labelStyle(.titleAndIcon)
        } else {
            Text(" ").font(.caption2)
        }
    }

    private func symbol(for direction: WeeklyDigest.ChangeDirection) -> String {
        switch direction {
        case .up: "arrowtriangle.up.fill"
        case .down: "arrowtriangle.down.fill"
        case .flat: "minus"
        }
    }

    private func color(for direction: WeeklyDigest.ChangeDirection) -> Color {
        switch direction {
        case .up: .green
        case .down: .red
        case .flat: .secondary
        }
    }
}

// MARK: - Trend chart (§5.3.3)

struct TrendChartCard: View {
    let trend: [TrendPoint]

    @State private var showPageviews = false
    @State private var scrubbed: TrendPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trend")
                    .font(.headline)
                Spacer()
                Toggle("Pageviews", isOn: $showPageviews)
                    .font(.caption)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
            }

            if trend.isEmpty {
                Text("No trend data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var chart: some View {
        Chart(trend) { point in
            if showPageviews {
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Pageviews", point.pageviews)
                )
                .foregroundStyle(.teal.opacity(0.35))
            }
            AreaMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("Visitors", point.visitors)
            )
            .foregroundStyle(
                LinearGradient(colors: [.accentColor.opacity(0.30), .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            LineMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("Visitors", point.visitors)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2))

            if let scrubbed, scrubbed.id == point.id {
                RuleMark(x: .value("Day", scrubbed.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .frame(height: 180)
        // Swift Charts on iOS 27 logs invalid frame dimensions when a data swap
        // of a different length (7D -> 30D/90D) runs inside an animated
        // transaction, so data changes here must not animate.
        .transaction { $0.animation = nil }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let origin = geometry[proxy.plotFrame!].origin
                                if let day: Date = proxy.value(atX: value.location.x - origin.x) {
                                    scrubbed = trend.min(by: {
                                        abs($0.day.timeIntervalSince(day)) < abs($1.day.timeIntervalSince(day))
                                    })
                                }
                            }
                            .onEnded { _ in scrubbed = nil }
                    )
            }
        }
        // Scrub readout: transient functional layer → glass capsule (§5.3, §5.6).
        .overlay(alignment: .top) {
            if let scrubbed {
                HStack(spacing: 8) {
                    Text(scrubbed.day, format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(.secondary)
                    Label(Formatting.abbreviated(scrubbed.visitors), systemImage: "person.2")
                    if showPageviews {
                        Label(Formatting.abbreviated(scrubbed.pageviews), systemImage: "doc.text")
                    }
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect()
            }
        }
    }
}

// MARK: - Top pages / sources / goals (§5.3.4–5)

struct TopPagesCard: View {
    let digest: WeeklyDigest
    let openDashboard: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top pages")
                .font(.headline)
            if digest.topPages.isEmpty {
                Text("No pageviews in this period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(digest.topPages.enumerated()), id: \.offset) { _, page in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.path)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let host = page.host {
                            Text(host)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Formatting.abbreviated(page.visitors))
                        .font(.subheadline.monospacedDigit())
                    DeltaChip(change: page.change)
                }
            }
            if let url = digest.dashboardURL {
                Button("Open full dashboard") {
                    openDashboard(url)
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct TopSourcesCard: View {
    let sources: [WeeklyDigest.TopSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top sources")
                .font(.headline)
            if sources.isEmpty {
                Text("No referrer data in this period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                HStack {
                    Text(source.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(Formatting.abbreviated(source.visitors))
                        .font(.subheadline.monospacedDigit())
                    DeltaChip(change: source.change)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct GoalsCard: View {
    let goals: [WeeklyDigest.Goal]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goals")
                .font(.headline)
            ForEach(Array(goals.enumerated()), id: \.offset) { _, goal in
                HStack {
                    Text(goal.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(goal.conversions)")
                        .font(.subheadline.monospacedDigit())
                    DeltaChip(change: goal.change)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
