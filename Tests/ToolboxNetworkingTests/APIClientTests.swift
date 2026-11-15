import Foundation
import Testing

@testable import ToolboxNetworking

/// Thread-safe call recorder for closures that must be `@Sendable`.
private final class Recorder<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [T] = []
  func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
  var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}

private let baseURL = URL(string: "https://api.example.com/v1")!

private func makeClient(
  transport: MockTransport,
  retry: RetryPolicy = RetryPolicy(maxAttempts: 3, baseDelay: 1, usesJitter: false),
  interceptors: [any RequestInterceptor] = [],
  logStore: NetworkLogStore? = nil,
  delays: Recorder<TimeInterval> = Recorder()
) -> APIClient {
  APIClient(
    baseURL: baseURL, transport: transport, retryPolicy: retry,
    interceptors: interceptors, logStore: logStore,
    sleep: { delays.add($0) })
}

private func response(_ request: URLRequest, status: Int) -> HTTPURLResponse {
  HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

struct User: Codable, Equatable, Sendable { let id: Int; let name: String }

struct APIClientTests {

  @Test func decodesSuccessfulResponse() async throws {
    let json = #"{"id":1,"name":"Ada"}"#.data(using: .utf8)!
    let client = makeClient(transport: .stub(data: json))
    let user: User = try await client.send(Endpoint(path: "users/1"))
    #expect(user == User(id: 1, name: "Ada"))
  }

  @Test func buildsURLWithPathAndQuery() async throws {
    let seen = Recorder<URL>()
    let transport = MockTransport { request in
      seen.add(request.url!)
      return (Data(), response(request, status: 200))
    }
    let client = makeClient(transport: transport)
    try await client.send(Endpoint(path: "/users", queryItems: [URLQueryItem(name: "page", value: "2")]))
    #expect(seen.all.first?.absoluteString == "https://api.example.com/v1/users?page=2")
  }

  @Test func retriesTransientStatusThenSucceeds() async throws {
    let calls = Recorder<Int>()
    let delays = Recorder<TimeInterval>()
    let transport = MockTransport { request in
      calls.add(1)
      return (Data(), response(request, status: calls.all.count < 3 ? 503 : 200))
    }
    let client = makeClient(transport: transport, delays: delays)
    try await client.send(Endpoint(path: "x"))
    #expect(calls.all.count == 3)
    #expect(delays.all == [1, 2])  // exponential, no jitter
  }

  @Test func doesNotRetryClientErrors() async throws {
    let calls = Recorder<Int>()
    let transport = MockTransport { request in
      calls.add(1)
      return (Data(), response(request, status: 404))
    }
    let client = makeClient(transport: transport)
    await #expect(throws: NetworkError.self) { try await client.send(Endpoint(path: "x")) }
    #expect(calls.all.count == 1)
  }

  @Test func doesNotRetryPOSTByDefault() async throws {
    let calls = Recorder<Int>()
    let transport = MockTransport { request in
      calls.add(1)
      return (Data(), response(request, status: 503))
    }
    let client = makeClient(transport: transport)
    await #expect(throws: NetworkError.self) { try await client.send(Endpoint(path: "x", method: .post)) }
    #expect(calls.all.count == 1)
  }

  @Test func givesUpAfterMaxAttempts() async throws {
    let calls = Recorder<Int>()
    let transport = MockTransport { request in
      calls.add(1)
      return (Data(), response(request, status: 500))
    }
    let client = makeClient(transport: transport)
    do {
      try await client.send(Endpoint(path: "x"))
      Issue.record("expected failure")
    } catch let error as NetworkError {
      #expect(error.statusCode == 500)
    }
    #expect(calls.all.count == 3)
  }

  @Test func retriesTransientURLError() async throws {
    let calls = Recorder<Int>()
    let transport = MockTransport { request in
      calls.add(1)
      if calls.all.count == 1 { throw URLError(.timedOut) }
      return (Data(), response(request, status: 200))
    }
    let client = makeClient(transport: transport)
    try await client.send(Endpoint(path: "x"))
    #expect(calls.all.count == 2)
  }

  @Test func wrapsDecodingFailures() async throws {
    let client = makeClient(transport: .stub(data: Data("nope".utf8)))
    await #expect(throws: NetworkError.self) {
      let _: User = try await client.send(Endpoint(path: "x"))
    }
  }

  @Test func interceptorsRunOnEveryAttempt() async throws {
    let tokens = Recorder<String>()
    let auth = BearerTokenInterceptor { tokens.add("t"); return "abc" }
    let seenAuth = Recorder<String?>()
    let calls = Recorder<Int>()
    let transport = MockTransport { request in
      calls.add(1)
      seenAuth.add(request.value(forHTTPHeaderField: "Authorization"))
      return (Data(), response(request, status: calls.all.count == 1 ? 503 : 200))
    }
    let client = makeClient(transport: transport, interceptors: [auth])
    try await client.send(Endpoint(path: "x"))
    #expect(tokens.all.count == 2)
    #expect(seenAuth.all == ["Bearer abc", "Bearer abc"])
  }

  @Test func jsonEndpointSetsBodyAndContentType() throws {
    let endpoint = try Endpoint.json(path: "users", body: User(id: 1, name: "Ada"))
    let request = try endpoint.urlRequest(baseURL: baseURL)
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.httpBody != nil)
  }
}

struct RetryPolicyTests {
  @Test func exponentialBackoffIsCapped() {
    let policy = RetryPolicy(baseDelay: 1, maxDelay: 5, usesJitter: false)
    #expect(policy.delay(afterAttempt: 1) == 1)
    #expect(policy.delay(afterAttempt: 2) == 2)
    #expect(policy.delay(afterAttempt: 3) == 4)
    #expect(policy.delay(afterAttempt: 4) == 5)
  }

  @Test func jitterScalesDelay() {
    let policy = RetryPolicy(baseDelay: 2, usesJitter: true)
    #expect(policy.delay(afterAttempt: 1, randomFactor: 0.5) == 1)
  }
}

struct NetworkLoggingTests {

  @Test func curlRedactsSecretsAndEscapesQuotes() {
    var request = URLRequest(url: URL(string: "https://api.example.com/x")!)
    request.httpMethod = "POST"
    request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
    request.httpBody = Data("it's".utf8)
    let curl = request.curlCommand()
    #expect(curl.contains("-X POST"))
    #expect(curl.contains("<redacted>"))
    #expect(!curl.contains("secret"))
    #expect(curl.contains("'it'\\''s'"))
  }

  @Test func storeRecordsRedactedEntries() async throws {
    let store = NetworkLogStore()
    let client = makeClient(
      transport: .stub(data: Data("ok".utf8), headers: ["Set-Cookie": "sid=1"]),
      interceptors: [BearerTokenInterceptor { "tok" }], logStore: store)
    try await client.send(Endpoint(path: "x"))

    let entries = await store.entries
    #expect(entries.count == 1)
    #expect(entries[0].isSuccess)
    #expect(entries[0].requestHeaders["Authorization"] == "<redacted>")
    #expect(entries[0].responseHeaders["Set-Cookie"] == "<redacted>")
    #expect(entries[0].responseBodyString == "ok")
  }

  @Test func storeIsBounded() async throws {
    let store = NetworkLogStore(capacity: 2)
    let client = makeClient(transport: .stub(), logStore: store)
    for _ in 0..<5 { try await client.send(Endpoint(path: "x")) }
    #expect(await store.entries.count == 2)
  }

  @Test func failuresAreLoggedPerAttempt() async throws {
    let store = NetworkLogStore()
    let client = makeClient(transport: .stub(status: 503), logStore: store)
    _ = try? await client.send(Endpoint(path: "x"))
    let entries = await store.entries
    #expect(entries.map(\.attempt) == [1, 2, 3])
    #expect(entries.allSatisfy { !$0.isSuccess })
  }

  @Test func updatesStreamEmitsNewEntries() async throws {
    let store = NetworkLogStore()
    let stream = await store.updates()
    let client = makeClient(transport: .stub(), logStore: store)
    try await client.send(Endpoint(path: "x"))
    var iterator = stream.makeAsyncIterator()
    let entry = await iterator.next()
    #expect(entry?.url == "https://api.example.com/v1/x")
  }
}
