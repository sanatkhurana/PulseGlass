import SwiftUI
import AnalyticsKit

@main
struct PulseGlassApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    model.handle(url: url)
                }
        }
    }
}

/// System Liquid Glass tab bar (§5.2). The bar stays visible on every tab —
/// including Regions — so switching tabs is always one tap away.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            Tab("Dashboard", systemImage: "chart.bar.xaxis", value: AppModel.TabSelection.dashboard) {
                DashboardView()
            }
            Tab("Regions", systemImage: "globe.americas.fill", value: AppModel.TabSelection.regions) {
                RegionsView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppModel.TabSelection.settings) {
                SettingsView()
            }
            Tab(value: AppModel.TabSelection.search, role: .search) {
                SearchView()
            }
        }
        .sheet(isPresented: .constant(model.needsOnboarding)) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .task {
            guard !model.needsOnboarding else { return }
            await model.refresh()
        }
    }
}

// MARK: - Shared banner (§9)

struct BannerView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
