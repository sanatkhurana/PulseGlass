import WidgetKit
import SwiftUI
import AnalyticsKit

@main
struct PulseGlassWidgetBundle: WidgetBundle {
    var body: some Widget {
        VisitorsWidget()
    }
}

// MARK: - Widget definition (§6.2)

struct VisitorsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetKinds.visitors,
            intent: SelectProfileIntent.self,
            provider: VisitorsTimelineProvider()
        ) { entry in
            VisitorsWidgetView(entry: entry)
                // System supplies the Liquid Glass / tint treatment (§6.4).
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Visitors — last 7 days")
        .description("Unique visitors with top cities, countries, and devices from PostHog.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

// MARK: - Root view: family dispatch

struct VisitorsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VisitorsEntry

    var body: some View {
        switch entry.state {
        case .needsSetup:
            NeedsSetupView()
                .widgetURL(DeepLink.onboarding.url)
        case .data(let snapshot, let isStale, let locations):
            dataView(snapshot: snapshot, isStale: isStale, locations: locations)
                .opacity(isStale ? 0.6 : 1) // stale rendering (§6.2)
        }
    }

    @ViewBuilder
    private func dataView(snapshot: Snapshot, isStale: Bool, locations: LocationsShown) -> some View {
        switch family {
        case .systemSmall:
            SmallView(snapshot: snapshot, isStale: isStale)
                .widgetURL(DeepLink.dashboard(range: .week).url)
        case .systemMedium:
            MediumView(snapshot: snapshot, isStale: isStale, locations: locations)
        case .systemLarge:
            LargeView(snapshot: snapshot, isStale: isStale, locations: locations)
        case .accessoryCircular:
            CircularView(snapshot: snapshot)
                .widgetURL(DeepLink.dashboard(range: .week).url)
        case .accessoryRectangular:
            RectangularView(snapshot: snapshot)
                .widgetURL(DeepLink.dashboard(range: .week).url)
        case .accessoryInline:
            InlineView(snapshot: snapshot)
                .widgetURL(DeepLink.dashboard(range: .week).url)
        default:
            SmallView(snapshot: snapshot, isStale: isStale)
        }
    }
}

struct NeedsSetupView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open PulseGlass to connect PostHog")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared pieces

/// Headline count with `.rounded` design and numeric content transitions (§6.4).
struct VisitorCount: View {
    let digest: WeeklyDigest?
    var font: Font = .system(.title, design: .rounded, weight: .semibold)

    var body: some View {
        Text(Formatting.abbreviated(digest?.visitors.current ?? 0))
            .font(font)
            .contentTransition(.numericText())
            .widgetAccentable()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

/// Delta chip. In accented/vibrant rendering the green/red is dropped and the
/// ▲/▼ glyph alone carries meaning (§6.4).
struct WidgetDeltaChip: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let change: WeeklyDigest.Change?

    var body: some View {
        if let change {
            HStack(spacing: 2) {
                Image(systemName: symbol(for: change.direction))
                    .font(.system(size: 8, weight: .bold))
                Text(Formatting.percent(abs(change.percent)))
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(renderingMode == .fullColor ? color(for: change.direction) : .secondary)
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

/// 7-point sparkline drawn with a lightweight Path (no Charts dependency).
struct Sparkline: View {
    let points: [TrendPoint]

    var body: some View {
        GeometryReader { geo in
            let values = points.map { Double($0.visitors) }
            if values.count > 1, let maxValue = values.max(), maxValue > 0 {
                let minValue = values.min() ?? 0
                let span = max(maxValue - minValue, 1)
                let step = geo.size.width / CGFloat(values.count - 1)
                Path { path in
                    for (i, value) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = geo.size.height * (1 - CGFloat((value - minValue) / span) * 0.9 - 0.05)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .widgetAccentable()
    }
}

struct StaleBadge: View {
    let date: Date

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 8))
            Text(date, style: .relative)
                .font(.system(size: 9))
        }
        .foregroundStyle(.secondary)
    }
}

/// Micro device row: `desktopcomputer`/`iphone`/`ipad` symbols + counts (§6.1).
struct DeviceMicroRow: View {
    let split: [DeviceType: Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach([DeviceType.desktop, .mobile, .tablet], id: \.self) { device in
                if let count = split[device], count > 0 {
                    HStack(spacing: 1) {
                        Image(systemName: device.symbolName)
                            .font(.system(size: 7))
                        Text(Formatting.abbreviated(count))
                            .font(.system(size: 8).monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct CityLinkRow: View {
    let city: CityStat
    var showDevices = true

    var body: some View {
        // Each city row is its own tap target in medium/large families (§6.1).
        Link(destination: DeepLink.regions(city: city.city).url) {
            HStack(spacing: 4) {
                Text("\(city.city), \(city.countryCode)")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Text("· \(Formatting.abbreviated(city.visitors))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if showDevices {
                    DeviceMicroRow(split: city.deviceSplit)
                }
            }
        }
    }
}

// MARK: - systemSmall

struct SmallView: View {
    let snapshot: Snapshot
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Visitors")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isStale { StaleBadge(date: snapshot.fetchedAt) }
            }
            VisitorCount(digest: snapshot.digest)
            WidgetDeltaChip(change: snapshot.digest?.visitors.change)
            Sparkline(points: snapshot.trend)
                .frame(height: 24)
            Text("Last 7 days")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - systemMedium

struct MediumView: View {
    let snapshot: Snapshot
    let isStale: Bool
    let locations: LocationsShown

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Visitors · 7d")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                VisitorCount(digest: snapshot.digest)
                WidgetDeltaChip(change: snapshot.digest?.visitors.change)
                Sparkline(points: snapshot.trend)
                    .frame(height: 22)
                if isStale { StaleBadge(date: snapshot.fetchedAt) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if locations == .countries {
                    ForEach(snapshot.countries.prefix(3)) { country in
                        HStack(spacing: 4) {
                            Text(country.flagEmoji).font(.caption2)
                            Text(country.country)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(Formatting.abbreviated(country.visitors))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(snapshot.cities.prefix(3)) { city in
                        CityLinkRow(city: city)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(DeepLink.dashboard(range: .week).url)
    }
}

// MARK: - systemLarge

struct LargeView: View {
    let snapshot: Snapshot
    let isStale: Bool
    let locations: LocationsShown

    private var effectiveLocations: LocationsShown { locations }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: count + delta + sparkline.
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Visitors · last 7 days")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        VisitorCount(digest: snapshot.digest,
                                     font: .system(.largeTitle, design: .rounded, weight: .semibold))
                        WidgetDeltaChip(change: snapshot.digest?.visitors.change)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Sparkline(points: snapshot.trend)
                        .frame(width: 90, height: 30)
                    if isStale { StaleBadge(date: snapshot.fetchedAt) }
                }
            }

            if effectiveLocations != .countries {
                Text("Top cities")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(snapshot.cities.prefix(5)) { city in
                    CityLinkRow(city: city)
                }
            }

            if effectiveLocations != .cities {
                Text("Top countries")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(snapshot.countries.prefix(3)) { country in
                    HStack(spacing: 4) {
                        Text(country.flagEmoji).font(.caption2)
                        Text(country.country)
                            .font(.caption2.weight(.medium))
                        Text("· \(Formatting.abbreviated(country.visitors))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text("\(Formatting.abbreviated(country.pageviews)) views")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(DeepLink.dashboard(range: .week).url)
    }
}

// MARK: - Accessory families (inherently vibrant; no color-encoded meaning, §6.4)

struct CircularView: View {
    let snapshot: Snapshot

    var body: some View {
        Gauge(value: gaugeValue) {
            Text("7d")
        } currentValueLabel: {
            Text(Formatting.abbreviated(snapshot.digest?.visitors.current ?? 0))
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    /// Ring shows current vs. previous period, capped at 2× growth.
    private var gaugeValue: Double {
        guard let visitors = snapshot.digest?.visitors,
              let previous = visitors.previous, previous > 0 else { return 1 }
        return min(visitors.current / (previous * 2), 1)
    }
}

struct RectangularView: View {
    let snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Visitors · 7d")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(Formatting.abbreviated(snapshot.digest?.visitors.current ?? 0))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .widgetAccentable()
                if let change = snapshot.digest?.visitors.change {
                    Text("\(change.direction == .down ? "▼" : "▲") \(Formatting.percent(abs(change.percent)))")
                        .font(.caption2)
                }
            }
            if let top = snapshot.cities.first {
                Text("\(top.city), \(top.countryCode)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct InlineView: View {
    let snapshot: Snapshot

    var body: some View {
        Text("👥 \(Formatting.abbreviated(snapshot.digest?.visitors.current ?? 0)) visitors · 7d")
    }
}

// MARK: - Previews (§11: all families)

#Preview("Small", as: .systemSmall) {
    VisitorsWidget()
} timeline: {
    VisitorsEntry.sample()
}

#Preview("Medium", as: .systemMedium) {
    VisitorsWidget()
} timeline: {
    VisitorsEntry.sample()
}

#Preview("Large", as: .systemLarge) {
    VisitorsWidget()
} timeline: {
    VisitorsEntry.sample()
}

#Preview("Circular", as: .accessoryCircular) {
    VisitorsWidget()
} timeline: {
    VisitorsEntry.sample()
}

#Preview("Rectangular", as: .accessoryRectangular) {
    VisitorsWidget()
} timeline: {
    VisitorsEntry.sample()
}

#Preview("Inline", as: .accessoryInline) {
    VisitorsWidget()
} timeline: {
    VisitorsEntry.sample()
}
