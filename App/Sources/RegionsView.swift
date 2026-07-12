import SwiftUI
import MapKit
import AnalyticsKit

// MARK: - Regions tab (§5.4)

struct RegionsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case countries = "Countries"
        case cities = "Cities"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .countries
    @State private var panelExpanded = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @Namespace private var glassNamespace

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // The list lives in an inline panel rather than a presented
                // sheet, so the Liquid Glass tab bar stays visible and tabs
                // remain reachable while browsing regions.
                VStack(spacing: 0) {
                    mapLayer
                        .overlay(alignment: .bottom) {
                            glassControls
                                .padding(.bottom, 12)
                        }
                    RegionListPanel(mode: mode, expanded: $panelExpanded)
                        .frame(height: geo.size.height * (panelExpanded ? 0.72 : 0.38))
                }
                .animation(.snappy(duration: 0.3), value: panelExpanded)
            }
            .navigationTitle("Regions")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if model.countries.isEmpty {
                    await model.refresh()
                }
                await model.refreshUnknownLocations()
            }
        }
    }

    /// Floating mode switcher + re-center: the screen's grouped custom glass
    /// controls, morphing via glassEffectID (§5.4.2).
    private var glassControls: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 24) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .padding(6)
                .glassEffect(.regular.interactive())
                .glassEffectID("mode-switcher", in: glassNamespace)

                Button {
                    withAnimation { cameraPosition = .automatic }
                } label: {
                    Image(systemName: "location.viewfinder")
                        .font(.title3)
                        .padding(4)
                }
                .buttonStyle(.glass)
                .glassEffectID("recenter", in: glassNamespace)
            }
        }
    }

    /// Map layer is content — standard map, no glass (§5.4.1).
    private var mapLayer: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            ForEach(model.countries) { country in
                if let centroid = CountryCentroids.centroid(for: country.countryCode) {
                    let coordinate = CLLocationCoordinate2D(
                        latitude: centroid.latitude, longitude: centroid.longitude
                    )
                    MapCircle(center: coordinate, radius: bubbleRadius(visitors: country.visitors))
                        .foregroundStyle(.blue.opacity(0.30))
                        .stroke(.blue.opacity(0.6), lineWidth: 1)
                    Annotation(country.country, coordinate: coordinate) {
                        Text(country.flagEmoji)
                            .font(.caption)
                            .onTapGesture { focus(on: coordinate) }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    /// Bubble radius scales with log(visitors) (§5.4.1).
    private func bubbleRadius(visitors: Int) -> CLLocationDistance {
        60_000 * log(Double(max(visitors, 2)))
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 14)
            ))
        }
    }
}

// MARK: - Inline bottom panel (content on material, §5.4.3)

struct RegionListPanel: View {
    @Environment(AppModel.self) private var model
    let mode: RegionsView.Mode
    @Binding var expanded: Bool

    private var totalVisitors: Int {
        Int(model.digest?.visitors.current ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            List {
                // Header repeats the digest total so map, list, and dashboard
                // never disagree silently (§5.4.4).
                Section {
                    HStack {
                        Text("Total visitors")
                            .font(.subheadline)
                        Spacer()
                        Text(Formatting.abbreviated(totalVisitors))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }

                Section {
                    switch mode {
                    case .countries:
                        countriesRows
                    case .cities:
                        citiesRows
                    }

                    if let unknown = model.unknownVisitors, unknown > 0 {
                        HStack {
                            Label("Unknown locations", systemImage: "questionmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(unknown) visitors")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if model.countries.isEmpty && model.cities.isEmpty {
                        Text("No location data. If your project has the GeoIP transformation disabled, or visitors browse with IP anonymization, geo fields are empty.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(.regularMaterial, in: UnevenRoundedRectangle(
            topLeadingRadius: 20, topTrailingRadius: 20
        ))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -40 { expanded = true }
                    if value.translation.height > 40 { expanded = false }
                }
        )
    }

    /// Drag handle: tap or drag to expand/collapse the list.
    private var grabber: some View {
        Button {
            expanded.toggle()
        } label: {
            VStack(spacing: 4) {
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 36, height: 5)
                HStack {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Collapse list" : "Expand list")
    }

    @ViewBuilder
    private var countriesRows: some View {
        let maxVisitors = max(model.countries.first?.visitors ?? 1, 1)
        ForEach(model.countries) { country in
            VStack(spacing: 4) {
                HStack {
                    Text(country.flagEmoji)
                    Text(country.country)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(Formatting.abbreviated(country.visitors))
                        .font(.subheadline.monospacedDigit())
                    Text("· \(Formatting.abbreviated(country.pageviews)) views")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Share-of-total bar (§5.4.3).
                GeometryReader { geo in
                    Capsule()
                        .fill(.blue.opacity(0.25))
                        .frame(width: geo.size.width * CGFloat(country.visitors) / CGFloat(maxVisitors))
                }
                .frame(height: 4)
            }
        }
    }

    @ViewBuilder
    private var citiesRows: some View {
        ForEach(model.cities) { city in
            CityRowView(city: city)
        }
    }
}

struct CityRowView: View {
    let city: CityStat

    var body: some View {
        HStack {
            Text(city.flagEmoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(city.city)
                    .font(.subheadline.weight(.medium))
                Text(city.country)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            deviceCounters
            Text(Formatting.abbreviated(city.visitors))
                .font(.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Three SF Symbol counters: desktopcomputer / iphone / ipad (§5.4.3).
    private var deviceCounters: some View {
        HStack(spacing: 8) {
            ForEach([DeviceType.desktop, .mobile, .tablet], id: \.self) { device in
                if let count = city.deviceSplit[device], count > 0 {
                    Label("\(count)", systemImage: device.symbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Berlin, Germany — 412 visitors: 280 mobile, 120 desktop, 12 tablet" (§10).
    private var accessibilitySummary: String {
        let split = [DeviceType.mobile, .desktop, .tablet]
            .compactMap { device -> String? in
                guard let count = city.deviceSplit[device], count > 0 else { return nil }
                return "\(count) \(device.rawValue.lowercased())"
            }
            .joined(separator: ", ")
        return "\(city.city), \(city.country) — \(city.visitors) visitors" + (split.isEmpty ? "" : ": \(split)")
    }
}

// MARK: - Search tab (§5.2: searches pages/cities)

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if !matchingPages.isEmpty {
                    Section("Pages") {
                        ForEach(Array(matchingPages.enumerated()), id: \.offset) { _, page in
                            HStack {
                                Text(page.path).font(.subheadline)
                                Spacer()
                                Text(Formatting.abbreviated(page.visitors))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !matchingCities.isEmpty {
                    Section("Cities") {
                        ForEach(matchingCities) { city in
                            CityRowView(city: city)
                        }
                    }
                }
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search pages and cities", systemImage: "magnifyingglass")
                } else if matchingPages.isEmpty && matchingCities.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Pages, cities…")
        }
    }

    private var matchingPages: [WeeklyDigest.TopPage] {
        guard !query.isEmpty else { return [] }
        return (model.digest?.topPages ?? [])
            .filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    private var matchingCities: [CityStat] {
        guard !query.isEmpty else { return [] }
        return model.cities.filter {
            $0.city.localizedCaseInsensitiveContains(query)
                || $0.country.localizedCaseInsensitiveContains(query)
        }
    }
}
