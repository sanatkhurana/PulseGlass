import Foundation

// MARK: - Errors (§9)

public enum PostHogError: Error, Sendable, Equatable {
    /// 401 `authentication_failed` — key invalid, revoked, or wrong host/region.
    case invalidKey
    /// 403 — key lacks `web_analytics:read` / `query:read`.
    case insufficientScope
    /// 404 — wrong project ID or wrong host.
    case notFound
    /// 429 — never retried in-session; caller falls back to the cached snapshot.
    case rateLimited(retryAfter: TimeInterval?)
    /// 400 with HogQL error detail — non-fatal, card-level.
    case hogQLError(String)
    case transport(String)
    case decoding(String)
    case unexpectedStatus(Int)
}

// MARK: - Transport abstraction (§2.4 QueryTransport seam + testability)

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PostHogError.transport("Non-HTTP response")
        }
        return (data, http)
    }
}

// MARK: - Client (§4.2)

public actor PostHogClient {

    public struct Config: Sendable {
        public let host: URL
        public let projectID: Int
        /// Dereferences the personal API key at request time (Keychain-backed
        /// in production). The key itself is never held by the client.
        public let apiKey: @Sendable () throws -> String
        public let timeout: TimeInterval
        public let userAgent: String

        public init(host: URL, projectID: Int,
                    apiKey: @escaping @Sendable () throws -> String,
                    timeout: TimeInterval = 15,
                    userAgent: String = "PulseGlass/1.0") {
            self.host = host
            self.projectID = projectID
            self.apiKey = apiKey
            self.timeout = timeout
            self.userAgent = userAgent
        }
    }

    private let config: Config
    private let transport: HTTPTransport
    /// Single-flight table: concurrent identical requests (e.g. dashboard and
    /// widget racing at app launch) share one network call (§7).
    private var inFlight: [String: Task<Data, Error>] = [:]

    public init(config: Config, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    // MARK: Public API

    public func weeklyDigest(days: Int = 7, compare: Bool = true) async throws -> WeeklyDigest {
        var components = URLComponents(
            url: config.host.appending(path: "/api/projects/\(config.projectID)/web_analytics/weekly_digest/"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "compare", value: compare ? "true" : "false"),
        ]
        let data = try await perform(request: try makeRequest(url: components.url!, method: "GET"),
                                     coalescingKey: "digest.\(days).\(compare)")
        return try decode(WeeklyDigest.self, from: data)
    }

    public func hogQL<Row: Decodable & Sendable>(
        _ query: HogQLRequest, as _: Row.Type
    ) async throws -> QueryEnvelope<Row> {
        let url = config.host.appending(path: "/api/projects/\(config.projectID)/query/")
        var request = try makeRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: [String: String]] = [
            "query": ["kind": "HogQLQuery", "query": query.sql, "name": query.name]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request: request, coalescingKey: "hogql.\(query.sql.hashValue)")
        let envelope = try decode(QueryEnvelope<Row>.self, from: data)
        if let error = envelope.error {
            throw PostHogError.hogQLError(error)
        }
        return envelope
    }

    /// Validates key + host (§4.1 step 3). A 200 proves both.
    public func currentUser() async throws -> MeUser {
        let url = config.host.appending(path: "/api/users/@me/")
        let data = try await perform(request: try makeRequest(url: url, method: "GET"),
                                     coalescingKey: "me")
        return try decode(MeUser.self, from: data)
    }

    public func organizations() async throws -> [OrganizationSummary] {
        let url = config.host.appending(path: "/api/organizations/")
        let data = try await perform(request: try makeRequest(url: url, method: "GET"),
                                     coalescingKey: "orgs")
        return try decode(ListEnvelope<OrganizationSummary>.self, from: data).results
    }

    public func projects(organizationID: String) async throws -> [ProjectSummary] {
        let url = config.host.appending(path: "/api/organizations/\(organizationID)/projects/")
        let data = try await perform(request: try makeRequest(url: url, method: "GET"),
                                     coalescingKey: "projects.\(organizationID)")
        return try decode(ListEnvelope<ProjectSummary>.self, from: data).results
    }

    // MARK: Internals

    private func makeRequest(url: URL, method: String) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = method
        request.setValue("Bearer \(try config.apiKey())", forHTTPHeaderField: "Authorization")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func perform(request: URLRequest, coalescingKey: String) async throws -> Data {
        if let existing = inFlight[coalescingKey] {
            return try await existing.value
        }
        let transport = self.transport
        let task = Task<Data, Error> {
            try await Self.sendWithRetry(request: request, transport: transport)
        }
        inFlight[coalescingKey] = task
        defer { inFlight[coalescingKey] = nil }
        return try await task.value
    }

    /// One retry on transient transport failure with jittered backoff.
    /// HTTP 429 is never retried (§4.2); HTTP errors other than 5xx are final.
    private static func sendWithRetry(request: URLRequest, transport: HTTPTransport) async throws -> Data {
        do {
            return try await sendOnce(request: request, transport: transport)
        } catch let error as PostHogError {
            switch error {
            case .transport, .unexpectedStatus(500...599):
                let jitterMillis = UInt64.random(in: 250...750)
                try? await Task.sleep(nanoseconds: jitterMillis * 1_000_000)
                return try await sendOnce(request: request, transport: transport)
            default:
                throw error
            }
        }
    }

    private static func sendOnce(request: URLRequest, transport: HTTPTransport) async throws -> Data {
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.send(request)
        } catch let error as PostHogError {
            throw error
        } catch {
            throw PostHogError.transport(error.localizedDescription)
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 400:
            let detail = Self.errorDetail(from: data) ?? "Bad request"
            throw PostHogError.hogQLError(detail)
        case 401:
            throw PostHogError.invalidKey
        case 403:
            throw PostHogError.insufficientScope
        case 404:
            throw PostHogError.notFound
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw PostHogError.rateLimited(retryAfter: retryAfter)
        default:
            throw PostHogError.unexpectedStatus(http.statusCode)
        }
    }

    private static func errorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (object["detail"] as? String) ?? (object["error"] as? String)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PostHogError.decoding(String(describing: error))
        }
    }
}
