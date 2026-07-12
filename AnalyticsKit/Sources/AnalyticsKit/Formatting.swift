import Foundation

// MARK: - Display formatting shared by app and widget

public enum Formatting {

    /// Abbreviates counts the way the dashboard tiles do: 950 → "950",
    /// 12_437 → "12.4K", 1_200_000 → "1.2M". Trailing ".0" is dropped.
    public static func abbreviated(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let v = abs(value)
        func trim(_ scaled: Double, suffix: String) -> String {
            let rounded = (scaled * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(sign)\(Int(rounded))\(suffix)"
            }
            return "\(sign)\(String(format: "%.1f", rounded))\(suffix)"
        }
        switch v {
        case 1_000_000_000...: return trim(v / 1_000_000_000, suffix: "B")
        case 1_000_000...: return trim(v / 1_000_000, suffix: "M")
        case 1_000...: return trim(v / 1_000, suffix: "K")
        default:
            if v == v.rounded() { return "\(sign)\(Int(v))" }
            return "\(sign)\(String(format: "%.1f", v))"
        }
    }

    public static func abbreviated(_ value: Int) -> String {
        abbreviated(Double(value))
    }

    /// "72" seconds → "1m 12s"; 3661 → "1h 1m".
    public static func duration(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }

    /// Percentage for delta chips: "8.2%".
    public static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))%" }
        return String(format: "%.1f%%", rounded)
    }

    /// Bounce rate arrives as a fraction (0.42) → "42%".
    public static func bounceRate(_ fraction: Double) -> String {
        // Some deployments return 0–1, others 0–100; normalize defensively.
        let pct = fraction <= 1 ? fraction * 100 : fraction
        return percent(pct)
    }

    /// ISO country code → flag emoji via regional-indicator symbols (§5.4).
    /// Invalid or unknown codes return a white flag.
    public static func flagEmoji(countryCode: String) -> String {
        let code = countryCode.uppercased()
        guard code.count == 2, code.allSatisfy({ $0.isLetter && $0.isASCII }) else {
            return "🏳️"
        }
        var flag = ""
        for scalar in code.unicodeScalars {
            guard let indicator = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) else {
                return "🏳️"
            }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }
}

// MARK: - Deep links (§6.1, §8)

/// `pulseglass://` routes, parsed against an allowlist. Anything not matching
/// a known route/param combination is rejected.
public enum DeepLink: Equatable, Sendable {
    case dashboard(range: DateRange)
    case regions(city: String?)
    case onboarding

    public static let scheme = "pulseglass"

    public init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        switch url.host() {
        case "dashboard":
            let raw = queryItems.first(where: { $0.name == "range" })?.value ?? "7d"
            switch raw {
            case "7d": self = .dashboard(range: .week)
            case "30d": self = .dashboard(range: .month)
            case "90d": self = .dashboard(range: .quarter)
            default: return nil
            }
        case "regions":
            let city = queryItems.first(where: { $0.name == "city" })?.value
            self = .regions(city: city)
        case "onboarding":
            self = .onboarding
        default:
            return nil
        }
    }

    public var url: URL {
        switch self {
        case .dashboard(let range):
            return URL(string: "pulseglass://dashboard?range=\(range.days)d")!
        case .regions(let city):
            var components = URLComponents(string: "pulseglass://regions")!
            if let city {
                components.queryItems = [URLQueryItem(name: "city", value: city)]
            }
            return components.url!
        case .onboarding:
            return URL(string: "pulseglass://onboarding")!
        }
    }
}

/// Validates that the digest's `dashboard_url` points at the configured
/// PostHog host before the app will open it (§8).
public enum DashboardURLPolicy {
    public static func isAllowed(_ url: URL, configuredHost: URL) -> Bool {
        guard url.scheme == "https" else { return false }
        guard let urlHost = url.host(), let configured = configuredHost.host() else { return false }
        return urlHost.lowercased() == configured.lowercased()
    }
}
