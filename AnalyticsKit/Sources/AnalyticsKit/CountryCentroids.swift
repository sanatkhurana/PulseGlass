import Foundation

// MARK: - Bundled country centroid table (§5.4)

/// Approximate geographic centroids per ISO-3166 alpha-2 code, used to place
/// visitor bubbles on the Regions map. Bundled so the app makes no geocoding
/// network calls. Codes without an entry simply don't render a bubble (the
/// list below the map still shows them).
public enum CountryCentroids {

    public struct Coordinate: Sendable, Equatable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public static func centroid(for countryCode: String) -> Coordinate? {
        table[countryCode.uppercased()]
    }

    static let table: [String: Coordinate] = [
        "AE": .init(latitude: 23.42, longitude: 53.85),
        "AR": .init(latitude: -38.42, longitude: -63.62),
        "AT": .init(latitude: 47.52, longitude: 14.55),
        "AU": .init(latitude: -25.27, longitude: 133.78),
        "BD": .init(latitude: 23.68, longitude: 90.36),
        "BE": .init(latitude: 50.50, longitude: 4.47),
        "BG": .init(latitude: 42.73, longitude: 25.49),
        "BR": .init(latitude: -14.24, longitude: -51.93),
        "CA": .init(latitude: 56.13, longitude: -106.35),
        "CH": .init(latitude: 46.82, longitude: 8.23),
        "CL": .init(latitude: -35.68, longitude: -71.54),
        "CN": .init(latitude: 35.86, longitude: 104.20),
        "CO": .init(latitude: 4.57, longitude: -74.30),
        "CZ": .init(latitude: 49.82, longitude: 15.47),
        "DE": .init(latitude: 51.17, longitude: 10.45),
        "DK": .init(latitude: 56.26, longitude: 9.50),
        "EE": .init(latitude: 58.60, longitude: 25.01),
        "EG": .init(latitude: 26.82, longitude: 30.80),
        "ES": .init(latitude: 40.46, longitude: -3.75),
        "FI": .init(latitude: 61.92, longitude: 25.75),
        "FR": .init(latitude: 46.23, longitude: 2.21),
        "GB": .init(latitude: 55.38, longitude: -3.44),
        "GR": .init(latitude: 39.07, longitude: 21.82),
        "HK": .init(latitude: 22.40, longitude: 114.11),
        "HR": .init(latitude: 45.10, longitude: 15.20),
        "HU": .init(latitude: 47.16, longitude: 19.50),
        "ID": .init(latitude: -0.79, longitude: 113.92),
        "IE": .init(latitude: 53.41, longitude: -8.24),
        "IL": .init(latitude: 31.05, longitude: 34.85),
        "IN": .init(latitude: 20.59, longitude: 78.96),
        "IT": .init(latitude: 41.87, longitude: 12.57),
        "JP": .init(latitude: 36.20, longitude: 138.25),
        "KE": .init(latitude: -0.02, longitude: 37.91),
        "KR": .init(latitude: 35.91, longitude: 127.77),
        "LT": .init(latitude: 55.17, longitude: 23.88),
        "LV": .init(latitude: 56.88, longitude: 24.60),
        "MX": .init(latitude: 23.63, longitude: -102.55),
        "MY": .init(latitude: 4.21, longitude: 101.98),
        "NG": .init(latitude: 9.08, longitude: 8.68),
        "NL": .init(latitude: 52.13, longitude: 5.29),
        "NO": .init(latitude: 60.47, longitude: 8.47),
        "NZ": .init(latitude: -40.90, longitude: 174.89),
        "PE": .init(latitude: -9.19, longitude: -75.02),
        "PH": .init(latitude: 12.88, longitude: 121.77),
        "PK": .init(latitude: 30.38, longitude: 69.35),
        "PL": .init(latitude: 51.92, longitude: 19.15),
        "PT": .init(latitude: 39.40, longitude: -8.22),
        "RO": .init(latitude: 45.94, longitude: 24.97),
        "RS": .init(latitude: 44.02, longitude: 21.01),
        "RU": .init(latitude: 61.52, longitude: 105.32),
        "SA": .init(latitude: 23.89, longitude: 45.08),
        "SE": .init(latitude: 60.13, longitude: 18.64),
        "SG": .init(latitude: 1.35, longitude: 103.82),
        "SK": .init(latitude: 48.67, longitude: 19.70),
        "TH": .init(latitude: 15.87, longitude: 100.99),
        "TR": .init(latitude: 38.96, longitude: 35.24),
        "TW": .init(latitude: 23.70, longitude: 120.96),
        "UA": .init(latitude: 48.38, longitude: 31.17),
        "US": .init(latitude: 37.09, longitude: -95.71),
        "VN": .init(latitude: 14.06, longitude: 108.28),
        "ZA": .init(latitude: -30.56, longitude: 22.94),
    ]
}
