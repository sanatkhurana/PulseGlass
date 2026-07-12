import XCTest
@testable import AnalyticsKit

// MARK: - Mock transport (§11: success / 401 / 403 / 429 / offline)

/// Scriptable transport: returns queued responses in order and records every
/// outgoing request for assertion.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Stub {
        let status: Int
        let body: Data
        let headers: [String: String]

        init(status: Int, body: Data = Data("{}".utf8), headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }
    }

    private let lock = NSLock()
    private var stubs: [Stub]
    private(set) var requests: [URLRequest] = []
    var failWith: Error?
    /// Artificial latency so concurrency tests deterministically overlap.
    var responseDelay: TimeInterval = 0

    init(stubs: [Stub]) {
        self.stubs = stubs
    }

    /// Synchronous so the NSLock use is legal under Swift 6's noasync rules.
    private func record(_ request: URLRequest) -> Result<Stub, Error> {
        lock.withLock {
            requests.append(request)
            if let error = failWith { return .failure(error) }
            return .success(stubs.isEmpty ? Stub(status: 200) : stubs.removeFirst())
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if responseDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        let stub = try record(request).get()

        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.status,
            httpVersion: "HTTP/1.1", headerFields: stub.headers
        )!
        return (stub.body, response)
    }
}

final class PostHogClientTests: XCTestCase {

    private func makeClient(_ transport: MockTransport) -> PostHogClient {
        PostHogClient(
            config: .init(
                host: URL(string: "https://us.posthog.com")!,
                projectID: 123,
                apiKey: { "phx_test_key_1234" }
            ),
            transport: transport
        )
    }

    // MARK: Request construction (§4.2)

    func testWeeklyDigestRequestShape() async throws {
        let transport = MockTransport(stubs: [
            .init(status: 200, body: WeeklyDigestDecodingTests.fullFixture)
        ])
        let digest = try await makeClient(transport).weeklyDigest(days: 30, compare: true)

        XCTAssertEqual(digest.visitors.current, 12437)
        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path(), "/api/projects/123/web_analytics/weekly_digest/")
        XCTAssertTrue(request.url!.query()!.contains("days=30"))
        XCTAssertTrue(request.url!.query()!.contains("compare=true"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer phx_test_key_1234")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "PulseGlass/1.0")
    }

    func testHogQLRequestBodyIsDocumentedShape() async throws {
        let transport = MockTransport(stubs: [
            .init(status: 200, body: Data(#"{"results": []}"#.utf8))
        ])
        _ = try await makeClient(transport).hogQL(HogQL.trend(range: .week), as: TrendRow.self)

        let request = transport.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path(), "/api/projects/123/query/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: [String: String]]
        XCTAssertEqual(body["query"]?["kind"], "HogQLQuery")
        XCTAssertEqual(body["query"]?["name"], "pulseglass.trend.daily")
        XCTAssertEqual(body["query"]?["query"], HogQL.trend(range: .week).sql)
    }

    // MARK: Error matrix (§9)

    func testMaps401ToInvalidKey() async {
        let transport = MockTransport(stubs: [
            .init(status: 401, body: Data(#"{"type": "authentication_error", "code": "authentication_failed"}"#.utf8))
        ])
        do {
            _ = try await makeClient(transport).currentUser()
            XCTFail("Expected invalidKey")
        } catch let error as PostHogError {
            XCTAssertEqual(error, .invalidKey)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testMaps403ToInsufficientScope() async {
        let transport = MockTransport(stubs: [.init(status: 403)])
        do {
            _ = try await makeClient(transport).weeklyDigest()
            XCTFail("Expected insufficientScope")
        } catch let error as PostHogError {
            XCTAssertEqual(error, .insufficientScope)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testMaps429ToRateLimitedWithRetryAfterAndNeverRetries() async {
        let transport = MockTransport(stubs: [
            .init(status: 429, headers: ["Retry-After": "42"])
        ])
        do {
            _ = try await makeClient(transport).weeklyDigest()
            XCTFail("Expected rateLimited")
        } catch let error as PostHogError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 42))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        // §4.2: 429 is never retried inside the same session.
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testMaps400WithDetailToHogQLError() async {
        let transport = MockTransport(stubs: [
            .init(status: 400, body: Data(#"{"detail": "Unable to parse HogQL: syntax error"}"#.utf8))
        ])
        do {
            _ = try await makeClient(transport).hogQL(HogQL.cities(range: .week), as: CityRow.self)
            XCTFail("Expected hogQLError")
        } catch let error as PostHogError {
            XCTAssertEqual(error, .hogQLError("Unable to parse HogQL: syntax error"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testEnvelopeLevelErrorSurfacesAsHogQLError() async {
        // A 200 whose envelope carries an `error` field still fails the call.
        let transport = MockTransport(stubs: [
            .init(status: 200, body: Data(#"{"results": [], "error": "Estimated query size too large"}"#.utf8))
        ])
        do {
            _ = try await makeClient(transport).hogQL(HogQL.countries(range: .week), as: CountryRow.self)
            XCTFail("Expected hogQLError")
        } catch let error as PostHogError {
            XCTAssertEqual(error, .hogQLError("Estimated query size too large"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testTransientTransportFailureIsRetriedOnce() async throws {
        let transport = MockTransport(stubs: [
            .init(status: 503),
            .init(status: 200, body: Data(#"{"results": [[7]]}"#.utf8)),
        ])
        let envelope = try await makeClient(transport)
            .hogQL(HogQL.unknownLocations(range: .week), as: UnknownRow.self)

        XCTAssertEqual(envelope.results.first?.visitors, 7)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testOfflineErrorSurfacesAsTransportAfterSingleRetry() async {
        let transport = MockTransport(stubs: [])
        transport.failWith = URLError(.notConnectedToInternet)
        do {
            _ = try await makeClient(transport).weeklyDigest()
            XCTFail("Expected transport error")
        } catch let error as PostHogError {
            guard case .transport = error else {
                return XCTFail("Expected .transport, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertEqual(transport.requests.count, 2) // initial + one retry
    }

    // MARK: Single-flight (§7)

    func testConcurrentIdenticalRequestsAreCoalesced() async throws {
        let transport = MockTransport(stubs: [
            .init(status: 200, body: WeeklyDigestDecodingTests.fullFixture),
            .init(status: 200, body: WeeklyDigestDecodingTests.fullFixture),
        ])
        transport.responseDelay = 0.1
        let client = makeClient(transport)

        async let a = client.weeklyDigest(days: 7)
        async let b = client.weeklyDigest(days: 7)
        _ = try await (a, b)

        XCTAssertEqual(transport.requests.count, 1, "identical concurrent requests must share one network call")
    }

    func testDifferentRequestsAreNotCoalesced() async throws {
        let transport = MockTransport(stubs: [
            .init(status: 200, body: WeeklyDigestDecodingTests.fullFixture),
            .init(status: 200, body: WeeklyDigestDecodingTests.fullFixture),
        ])
        let client = makeClient(transport)

        async let a = client.weeklyDigest(days: 7)
        async let b = client.weeklyDigest(days: 30)
        _ = try await (a, b)

        XCTAssertEqual(transport.requests.count, 2)
    }
}
