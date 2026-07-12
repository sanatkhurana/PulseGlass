import SwiftUI
import AnalyticsKit

// MARK: - Settings tab (§5.5)

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddProfile = false
    @State private var showSignOutConfirmation = false
    @State private var connectionTestResult: String?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                Section("Connections") {
                    ForEach(model.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.id == model.activeProfile?.id,
                            keyPreview: model.apiKeyPreview(for: profile),
                            select: {
                                model.setActiveProfile(profile)
                                Task { await model.refresh(force: true) }
                            },
                            testConnection: { await testConnection(profile) }
                        )
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            model.removeProfile(model.profiles[offset])
                        }
                    }
                    Button {
                        showAddProfile = true
                    } label: {
                        Label("Add connection", systemImage: "plus")
                    }
                }

                if let result = connectionTestResult {
                    Section("Connection test") {
                        Text(result).font(.footnote)
                    }
                }

                Section("Widget") {
                    Text("Add the widget from the Home Screen, then long-press it and choose Edit Widget to pick a profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Cache") {
                    Button("Clear cached snapshots") {
                        model.clearCachedSnapshots()
                    }
                }

                Section("Diagnostics") {
                    if model.lastHTTPStatusByEndpoint.isEmpty {
                        Text("No requests yet").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(model.lastHTTPStatusByEndpoint.sorted(by: { $0.key < $1.key }), id: \.key) { endpoint, status in
                        HStack {
                            Text(endpoint).font(.footnote)
                            Spacer()
                            Text(status).font(.footnote.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    if !model.lastQueryNames.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recent query_log names").font(.footnote.weight(.medium))
                            ForEach(model.lastQueryNames, id: \.self) { name in
                                Text(name).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                } footer: {
                    Text("Removes all profiles from the Keychain and wipes cached snapshots.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddProfile) {
                OnboardingView()
            }
            .confirmationDialog("Sign out of all profiles?",
                                isPresented: $showSignOutConfirmation,
                                titleVisibility: .visible) {
                Button("Sign out and wipe data", role: .destructive) {
                    model.signOut()
                }
            }
        }
    }

    private func testConnection(_ profile: Profile) async {
        connectionTestResult = "Testing \(profile.name)…"
        do {
            // /users/@me/ needs the optional user:read scope; a 403 there
            // still means the key authenticated, so don't fail the test on it.
            var identity = "a scoped key"
            do {
                let user = try await model.client(for: profile).currentUser()
                identity = user.email ?? "unknown"
            } catch PostHogError.insufficientScope {
                // Least-privilege key without user:read — fine.
            }
            let digest = try await model.client(for: profile).weeklyDigest(days: 7)
            connectionTestResult = "✓ \(profile.name): authenticated as \(identity), \(Int(digest.visitors.current)) visitors last 7 days"
        } catch let error as PostHogError {
            connectionTestResult = "✗ \(profile.name): \(describe(error))"
        } catch {
            connectionTestResult = "✗ \(profile.name): \(error.localizedDescription)"
        }
    }

    private func describe(_ error: PostHogError) -> String {
        switch error {
        case .invalidKey: "key invalid or revoked (401)"
        case .insufficientScope: "key is missing required scopes (403)"
        case .notFound: "project not found — check host and project ID (404)"
        case .rateLimited: "rate limited (429)"
        case .transport(let detail): "network error: \(detail)"
        case .hogQLError(let detail): "query error: \(detail)"
        case .decoding: "unexpected response format"
        case .unexpectedStatus(let code): "HTTP \(code)"
        }
    }
}

struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let keyPreview: String
    let select: () -> Void
    let testConnection: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: select) {
                    HStack {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isActive ? Color.accentColor : .secondary)
                        Text(profile.name).font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Test") {
                    Task { await testConnection() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            Text("\(profile.host.host() ?? "?") · project \(profile.projectID) · \(keyPreview)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
