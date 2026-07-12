import SwiftUI
import AnalyticsKit

// MARK: - Onboarding (§4.1)

struct OnboardingView: View {
    enum HostChoice: String, CaseIterable, Identifiable {
        case us = "PostHog Cloud US"
        case eu = "PostHog Cloud EU"
        case selfHosted = "Self-hosted"

        var id: String { rawValue }

        var url: URL? {
            switch self {
            case .us: URL(string: "https://us.posthog.com")
            case .eu: URL(string: "https://eu.posthog.com")
            case .selfHosted: nil
            }
        }
    }

    enum Step {
        case credentials
        case projectPicker(orgs: [OrganizationSummary])
        case manualProject
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var hostChoice: HostChoice = .us
    @State private var selfHostedURL = ""
    @State private var apiKey = ""
    @State private var profileName = "My project"
    @State private var manualProjectID = ""
    @State private var step: Step = .credentials
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var projectsByOrg: [String: [ProjectSummary]] = [:]

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .credentials:
                    credentialsForm
                case .projectPicker(let orgs):
                    projectPicker(orgs: orgs)
                case .manualProject:
                    manualProjectForm
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Connect PostHog")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Step 1–2: host + key

    @ViewBuilder
    private var credentialsForm: some View {
        Section {
            Picker("Region", selection: $hostChoice) {
                ForEach(HostChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.menu)

            if hostChoice == .selfHosted {
                TextField("https://posthog.example.com", text: $selfHostedURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Host")
        } footer: {
            Text("US keys live on us.posthog.com, EU keys on eu.posthog.com. Self-hosted must use HTTPS.")
        }

        Section {
            SecureField("phx_…", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Profile name", text: $profileName)
        } header: {
            Text("Personal API key")
        } footer: {
            Text("Create a scoped key in PostHog under Settings → Personal API keys with web_analytics:read and query:read. Optional: project:read + organization:read enable the project picker, user:read shows your account email.")
        }

        Section {
            Button {
                Task { await validateAndContinue() }
            } label: {
                if isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Connect").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(apiKey.isEmpty || isWorking || resolvedHost == nil)
            .listRowBackground(Color.clear)

            // First-run only: when reused as the "Add connection" sheet,
            // demo mode would replace the user's real connections.
            if model.needsOnboarding {
                Button("Explore with sample data") {
                    model.enableDemo()
                    dismiss()
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
    }

    private var resolvedHost: URL? {
        if let fixed = hostChoice.url { return fixed }
        // HTTPS enforced; HTTP self-hosted URLs are rejected at input (§8).
        guard let url = URL(string: selfHostedURL), url.scheme == "https", url.host() != nil else {
            return nil
        }
        return url
    }

    // MARK: Step 3–4: validate key, pick project

    private func validateAndContinue() async {
        guard let host = resolvedHost else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let key = apiKey
        let probe = PostHogClient(config: .init(host: host, projectID: 0, apiKey: { key }))

        do {
            _ = try await probe.currentUser()
        } catch let error as PostHogError {
            switch error {
            case .invalidKey:
                errorMessage = "Key invalid or revoked. US keys live on us.posthog.com, EU on eu.posthog.com — check the host too."
                return
            case .insufficientScope:
                // A least-privilege key (web_analytics:read + query:read only)
                // lacks user:read, so /users/@me/ answers 403 — but a 403
                // proves the key authenticated (a bad key would be 401).
                // Proceed; the smoke test validates the scopes that matter.
                break
            case .notFound:
                errorMessage = "Host looks wrong — that URL doesn't answer PostHog's API."
                return
            default:
                errorMessage = "Could not validate the key: \(error)"
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Key + host are valid. Try the project picker; if the key can't list
        // projects, fall back to manual project ID entry (§4.1 step 4).
        do {
            let orgs = try await probe.organizations()
            var byOrg: [String: [ProjectSummary]] = [:]
            for org in orgs {
                byOrg[org.id] = (try? await probe.projects(organizationID: org.id)) ?? []
            }
            if byOrg.values.allSatisfy(\.isEmpty) {
                step = .manualProject
            } else {
                projectsByOrg = byOrg
                step = .projectPicker(orgs: orgs)
            }
        } catch {
            step = .manualProject
        }
    }

    @ViewBuilder
    private func projectPicker(orgs: [OrganizationSummary]) -> some View {
        ForEach(orgs) { org in
            Section(org.name) {
                ForEach(projectsByOrg[org.id] ?? []) { project in
                    Button {
                        Task { await finish(projectID: project.id, suggestedName: project.name) }
                    } label: {
                        HStack {
                            Text(project.name)
                            Spacer()
                            Text("#\(project.id)").foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isWorking)
                }
            }
        }
        Section {
            Button("Enter project ID manually") { step = .manualProject }
        }
    }

    @ViewBuilder
    private var manualProjectForm: some View {
        Section {
            TextField("12345", text: $manualProjectID)
                .keyboardType(.numberPad)
        } header: {
            Text("Project ID")
        } footer: {
            Text("Find the numeric project ID in your PostHog project settings.")
        }
        Section {
            Button {
                guard let id = Int(manualProjectID) else { return }
                Task { await finish(projectID: id, suggestedName: profileName) }
            } label: {
                if isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Validate & finish").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(Int(manualProjectID) == nil || isWorking)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Step 5: smoke test + save

    private func finish(projectID: Int, suggestedName: String) async {
        guard let host = resolvedHost else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let key = apiKey
        let client = PostHogClient(config: .init(host: host, projectID: projectID, apiKey: { key }))

        do {
            // Smoke test: one digest call + one 1-row HogQL query (§4.1 step 5).
            _ = try await client.weeklyDigest(days: 7)
            _ = try await client.hogQL(HogQL.unknownLocations(range: .week), as: UnknownRow.self)
        } catch let error as PostHogError {
            switch error {
            case .insufficientScope:
                errorMessage = "The key is missing web_analytics:read or query:read for this project."
            case .notFound:
                errorMessage = "Project \(projectID) not found on this host."
            default:
                errorMessage = "Smoke test failed: \(error)"
            }
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            let name = profileName.isEmpty ? suggestedName : profileName
            try model.addProfile(name: name, host: host, projectID: projectID, apiKey: key)
        } catch {
            errorMessage = "Could not save to the Keychain: \(error.localizedDescription)"
            return
        }

        dismiss()
        await model.refresh(force: true)
    }
}
