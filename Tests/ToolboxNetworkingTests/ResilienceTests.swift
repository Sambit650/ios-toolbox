import Foundation
import Testing

@testable import ToolboxNetworking

/// Thread-safe mutable box usable from `@Sendable` closures.
private final class Box<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: T
  init(_ value: T) { _value = value }
  var value: T {
    get { lock.lock(); defer { lock.unlock() }; return _value }
    set { lock.lock(); _value = newValue; lock.unlock() }
  }
  func mutate(_ body: (inout T) -> Void) { lock.lock(); body(&_value); lock.unlock() }
}

private let base = URL(string: "https://api.example.com")!

private func http(_ request: URLRequest, _ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
  HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
}

private func makeClient(
  transport: MockTransport,
  retry: RetryPolicy = RetryPolicy(maxAttempts: 3, baseDelay: 1, usesJitter: false),
  interceptors: [any RequestInterceptor] = [],
  refresher: (@Sendable () async throws -> Void)? = nil,
  logStore: NetworkLogStore? = nil,
  cache: ResponseCache = ResponseCache(),
  dedupe: Bool = true,
  delays: Box<[TimeInterval]> = Box([])
) -> APIClient {
  APIClient(
    baseURL: base, transport: transport, retryPolicy: retry, interceptors: interceptors,
    authRefresher: refresher, logStore: logStore, cache: cache, deduplicatesRequests: dedupe,
    sleep: { seconds in delays.mutate { $0.append(seconds) } })
}

// MARK: - 401 refresh & replay

struct AuthRefreshTests {

  /// Transport that accepts only the "new" token; interceptor reads the current token.
  private func fixture() -> (token: Box<String>, calls: Box<Int>, refreshes: Box<Int>, transport: MockTransport, auth: BearerTokenInterceptor) {
    let token = Box("old")
    let calls = Box(0)
    let refreshes = Box(0)
    let transport = MockTransport { request in
      calls.mutate { $0 += 1 }
      let ok = request.value(forHTTPHeaderField: "Authorization") == "Bearer new"
      return (Data(), http(request, ok ? 200 : 401))
    }
    return (token, calls, refreshes, transport, BearerTokenInterceptor { token.value })
  }

  @Test func refreshesOn401AndReplaysOnce() async throws {
    let f = fixture()
    let client = makeClient(transport: f.transport, interceptors: [f.auth], refresher: {
      f.refreshes.mutate { $0 += 1 }
      f.token.value = "new"
    })
    try await client.send(Endpoint(path: "me"))
    #expect(f.calls.value == 2)
    #expect(f.refreshes.value == 1)
  }

  @Test func concurrentUnauthorizedRequestsShareOneRefresh() async throws {
    let f = fixture()
    let client = makeClient(transport: f.transport, interceptors: [f.auth], refresher: {
      f.refreshes.mutate { $0 += 1 }
      try await Task.sleep(nanoseconds: 50_000_000)
      f.token.value = "new"
    })
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<5 { group.addTask { try await client.send(Endpoint(path: "item/\(i)")) } }
      try await group.waitForAll()
    }
    #expect(f.refreshes.value == 1)
  }

  @Test func coordinatorSkipsRefreshWhenAlreadyRefreshed() async throws {
    let coordinator = RefreshCoordinator()
    let runs = Box(0)
    try await coordinator.refresh(observedGeneration: 0) { runs.mutate { $0 += 1 } }
    // A request sent before that refresh finished now reports its stale generation.
    try await coordinator.refresh(observedGeneration: 0) { runs.mutate { $0 += 1 } }
    #expect(runs.value == 1)
    #expect(await coordinator.currentGeneration() == 1)
  }

  @Test func failedRefreshSurfacesTokenRefreshFailed() async throws {
    let f = fixture()
    struct Boom: Error {}
    let client = makeClient(transport: f.transport, interceptors: [f.auth], refresher: { throw Boom() })
    do {
      try await client.send(Endpoint(path: "me"))
      Issue.record("expected failure")
    } catch NetworkError.tokenRefreshFailed {
      // expected
    }
    #expect(f.calls.value == 1)
  }

  @Test func stillUnauthorizedAfterRefreshIsNotLooped() async throws {
    let refreshes = Box(0)
    let calls = Box(0)
    let transport = MockTransport { request in
      calls.mutate { $0 += 1 }
      return (Data(), http(request, 401))
    }
    let client = makeClient(transport: transport, refresher: { refreshes.mutate { $0 += 1 } })
    do {
      try await client.send(Endpoint(path: "me"))
      Issue.record("expected failure")
    } catch let error as NetworkError {
      #expect(error.statusCode == 401)
    }
    #expect(refreshes.value == 1)
    #expect(calls.value == 2)
  }

  @Test func endpointCanOptOutOfRefresh() async throws {
    let refreshes = Box(0)
    let client = makeClient(transport: .stub(status: 401), refresher: { refreshes.mutate { $0 += 1 } })
    _ = try? await client.send(Endpoint(path: "auth/refresh", triggersAuthRefresh: false))
    #expect(refreshes.value == 0)
  }
}

// MARK: - Retry-After

struct RetryAfterTests {

  @Test func usesRetryAfterSecondsWhenLargerThanBackoff() async throws {
    let calls = Box(0)
    let delays = Box<[TimeInterval]>([])
    let transport = MockTransport { request in
      calls.mutate { $0 += 1 }
      return calls.value == 1
        ? (Data(), http(request, 429, headers: ["Retry-After": "7"]))
        : (Data(), http(request, 200))
    }
    let client = makeClient(transport: transport, delays: delays)
    try await client.send(Endpoint(path: "x"))
    #expect(delays.value == [7])
  }

  @Test func givesUpWhenServerAsksForTooLongAWait() async throws {
    let calls = Box(0)
    let transport = MockTransport { request in
      calls.mutate { $0 += 1 }
      return (Data(), http(request, 503, headers: ["Retry-After": "3600"]))
    }
    let client = makeClient(transport: transport)
    _ = try? await client.send(Endpoint(path: "x"))
    #expect(calls.value == 1)
  }

  @Test func ignoresRetryAfterWhenDisabled() async throws {
    let delays = Box<[TimeInterval]>([])
    let calls = Box(0)
    let transport = MockTransport { request in
      calls.mutate { $0 += 1 }
      return calls.value == 1
        ? (Data(), http(request, 429, headers: ["Retry-After": "7"]))
        : (Data(), http(request, 200))
    }
    let policy = RetryPolicy(baseDelay: 1, usesJitter: false, respectsRetryAfter: false)
    let client = makeClient(transport: transport, retry: policy, delays: delays)
    try await client.send(Endpoint(path: "x"))
    #expect(delays.value == [1])
  }

  @Test func parsesHTTPDate() {
    let error = NetworkError.httpStatus(
      code: 503, data: Data(), headers: ["retry-after": "Wed, 21 Oct 2015 07:28:00 GMT"])
    let now = Date(timeIntervalSince1970: 1_445_412_470)  // 10s earlier
    #expect(error.retryAfter(now: now) == 10)
  }

  @Test func missingHeaderMeansNoHint() {
    #expect(NetworkError.httpStatus(code: 503, data: Data(), headers: [:]).retryAfter() == nil)
  }
}

// MARK: - De-duplication

struct DeduplicationTests {

  private func slowTransport(calls: Box<Int>) -> MockTransport {
    MockTransport { request in
      calls.mutate { $0 += 1 }
      try await Task.sleep(nanoseconds: 80_000_000)
      return (Data("ok".utf8), http(request, 200))
    }
  }

  @Test func identicalConcurrentGetsShareOneCall() async throws {
    let calls = Box(0)
    let client = makeClient(transport: slowTransport(calls: calls))
    try await withThrowingTaskGroup(of: Data.self) { group in
      for _ in 0..<5 { group.addTask { try await client.send(Endpoint(path: "same")).data } }
      for try await data in group { #expect(String(data: data, encoding: .utf8) == "ok") }
    }
    #expect(calls.value == 1)
  }

  @Test func differentEndpointsAreNotMerged() async throws {
    let calls = Box(0)
    let client = makeClient(transport: slowTransport(calls: calls))
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<3 { group.addTask { try await client.send(Endpoint(path: "p/\(i)")) } }
      try await group.waitForAll()
    }
    #expect(calls.value == 3)
  }

  @Test func postsAreNeverMerged() async throws {
    let calls = Box(0)
    let client = makeClient(transport: slowTransport(calls: calls), retry: .none)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<3 { group.addTask { try await client.send(Endpoint(path: "same", method: .post)) } }
      try await group.waitForAll()
    }
    #expect(calls.value == 3)
  }

  @Test func canBeDisabled() async throws {
    let calls = Box(0)
    let client = makeClient(transport: slowTransport(calls: calls), dedupe: false)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<3 { group.addTask { try await client.send(Endpoint(path: "same")) } }
      try await group.waitForAll()
    }
    #expect(calls.value == 3)
  }

  @Test func sharedFailureReachesAllCallers() async throws {
    let calls = Box(0)
    let transport = MockTransport { request in
      calls.mutate { $0 += 1 }
      try await Task.sleep(nanoseconds: 50_000_000)
      return (Data(), http(request, 404))
    }
    let client = makeClient(transport: transport)
    await withTaskGroup(of: Int?.self) { group in
      for _ in 0..<3 {
        group.addTask {
          do { try await client.send(Endpoint(path: "missing")); return nil }
          catch let error as NetworkError { return error.statusCode }
          catch { return nil }
        }
      }
      var codes: [Int?] = []
      for await code in group { codes.append(code) }
      #expect(codes == [404, 404, 404])
    }
    #expect(calls.value == 1)
  }
}

// MARK: - Response cache

struct ResponseCacheTests {

  private func countingTransport(_ calls: Box<Int>, headers: [String: String] = [:]) -> MockTransport {
    MockTransport { request in
      calls.mutate { $0 += 1 }
      return (Data("v\(calls.value)".utf8), http(request, 200, headers: headers))
    }
  }

  @Test func cacheFirstServesFreshEntries() async throws {
    let calls = Box(0)
    let client = makeClient(transport: countingTransport(calls))
    let endpoint = Endpoint(path: "x", cachePolicy: .cacheFirst(ttl: 60))
    let first = try await client.send(endpoint).data
    let second = try await client.send(endpoint).data
    #expect(calls.value == 1)
    #expect(first == second)
  }

  @Test func entriesExpireAfterTTL() async throws {
    let now = Box(Date(timeIntervalSince1970: 1_000))
    let cache = ResponseCache(clock: { now.value })
    let calls = Box(0)
    let client = makeClient(transport: countingTransport(calls), cache: cache)
    let endpoint = Endpoint(path: "x", cachePolicy: .cacheFirst(ttl: 60))

    try await client.send(endpoint)
    now.value = now.value.addingTimeInterval(59)
    try await client.send(endpoint)
    #expect(calls.value == 1)

    now.value = now.value.addingTimeInterval(2)  // 61s after store
    let refreshed = try await client.send(endpoint).data
    #expect(calls.value == 2)
    #expect(String(data: refreshed, encoding: .utf8) == "v2")
  }

  @Test func defaultPolicyNeverCaches() async throws {
    let calls = Box(0)
    let client = makeClient(transport: countingTransport(calls))
    try await client.send(Endpoint(path: "x"))
    try await client.send(Endpoint(path: "x"))
    #expect(calls.value == 2)
  }

  @Test func refreshPolicySkipsReadButStores() async throws {
    let calls = Box(0)
    let client = makeClient(transport: countingTransport(calls))
    try await client.send(Endpoint(path: "x", cachePolicy: .refresh(ttl: 60)))
    try await client.send(Endpoint(path: "x", cachePolicy: .refresh(ttl: 60)))
    #expect(calls.value == 2)
    try await client.send(Endpoint(path: "x", cachePolicy: .cacheFirst(ttl: 60)))
    #expect(calls.value == 2)  // served from what refresh stored
  }

  @Test func failuresAreNotCached() async throws {
    let calls = Box(0)
    let transport = MockTransport { request in
      calls.mutate { $0 += 1 }
      return (Data(), http(request, calls.value == 1 ? 500 : 200))
    }
    let client = makeClient(transport: transport, retry: .none)
    let endpoint = Endpoint(path: "x", cachePolicy: .cacheFirst(ttl: 60))
    _ = try? await client.send(endpoint)
    try await client.send(endpoint)
    #expect(calls.value == 2)
  }

  @Test func noStoreResponsesAreNotCached() async throws {
    let calls = Box(0)
    let client = makeClient(transport: countingTransport(calls, headers: ["Cache-Control": "no-store"]))
    let endpoint = Endpoint(path: "x", cachePolicy: .cacheFirst(ttl: 60))
    try await client.send(endpoint)
    try await client.send(endpoint)
    #expect(calls.value == 2)
  }

  @Test func onlyGetsAreCached() async throws {
    let calls = Box(0)
    let client = makeClient(transport: countingTransport(calls))
    let endpoint = Endpoint(path: "x", method: .post, cachePolicy: .cacheFirst(ttl: 60))
    try await client.send(endpoint)
    try await client.send(endpoint)
    #expect(calls.value == 2)
  }

  @Test func queryAndHeadersPartitionTheCache() async throws {
    let calls = Box(0)
    let client = makeClient(transport: countingTransport(calls))
    let policy = CachePolicy.cacheFirst(ttl: 60)
    try await client.send(Endpoint(path: "x", queryItems: [URLQueryItem(name: "p", value: "1")], cachePolicy: policy))
    try await client.send(Endpoint(path: "x", queryItems: [URLQueryItem(name: "p", value: "2")], cachePolicy: policy))
    #expect(calls.value == 2)
  }

  @Test func lruEvictsLeastRecentlyUsed() async throws {
    let cache = ResponseCache(capacity: 2)
    let calls = Box(0)
    let client = makeClient(transport: countingTransport(calls), cache: cache)
    let policy = CachePolicy.cacheFirst(ttl: 60)
    try await client.send(Endpoint(path: "a", cachePolicy: policy))
    try await client.send(Endpoint(path: "b", cachePolicy: policy))
    try await client.send(Endpoint(path: "a", cachePolicy: policy))  // touch a -> b is LRU
    try await client.send(Endpoint(path: "c", cachePolicy: policy))  // evicts b
    #expect(await cache.count == 2)
    let before = calls.value
    try await client.send(Endpoint(path: "a", cachePolicy: policy))
    #expect(calls.value == before)  // a still cached
    try await client.send(Endpoint(path: "b", cachePolicy: policy))
    #expect(calls.value == before + 1)  // b was evicted
  }

  @Test func clearCacheForcesRefetchAndHitsAreLogged() async throws {
    let calls = Box(0)
    let store = NetworkLogStore()
    let client = makeClient(transport: countingTransport(calls), logStore: store)
    let endpoint = Endpoint(path: "x", cachePolicy: .cacheFirst(ttl: 60))
    try await client.send(endpoint)
    try await client.send(endpoint)
    let entries = await store.entries
    #expect(entries.map(\.fromCache) == [false, true])

    await client.clearCache()
    try await client.send(endpoint)
    #expect(calls.value == 2)
  }
}
