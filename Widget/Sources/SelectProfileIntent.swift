import AppIntents
import AnalyticsKit

// MARK: - Widget configuration intent (§6.3)

/// A profile as seen by the widget configuration UI. Backed by Keychain
/// metadata; the API key itself is only dereferenced inside the provider.
struct ProfileEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "PostHog Profile"
    static let defaultQuery = ProfileEntityQuery()

    let id: UUID
    let name: String
    let hostLabel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(hostLabel)")
    }

    init(profile: Profile) {
        id = profile.id
        name = profile.name
        hostLabel = profile.host.host() ?? profile.host.absoluteString
    }
}

struct ProfileEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        ProfileStore().loadProfiles()
            .filter { identifiers.contains($0.id) }
            .map(ProfileEntity.init)
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        ProfileStore().loadProfiles().map(ProfileEntity.init)
    }

    func defaultResult() async -> ProfileEntity? {
        ProfileStore().loadProfiles().first.map(ProfileEntity.init)
    }
}

/// Which location list the medium/large families emphasize (§6.3).
enum LocationsShown: String, AppEnum {
    case cities
    case countries
    case mixed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Locations shown"
    static let caseDisplayRepresentations: [LocationsShown: DisplayRepresentation] = [
        .cities: "Cities",
        .countries: "Countries",
        .mixed: "Mixed",
    ]
}

struct SelectProfileIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Visitors — last 7 days"
    static let description = IntentDescription(
        "Unique visitors with top cities, countries, and devices from PostHog."
    )

    @Parameter(title: "Profile")
    var profile: ProfileEntity?

    // Default Mixed: systemLarge shows cities + countries; the smaller
    // families render Mixed as Cities (§6.3).
    @Parameter(title: "Locations shown", default: .mixed)
    var locations: LocationsShown
}
