//
//  APIClient.swift
//  ToolboxNetworking
//

import Foundation

/// A small async/await HTTP client with interceptors, retry/backoff, 401 refresh-and-replay,
/// request de-duplication, response caching and traffic logging.
///
/// ```swift
/// let logs = NetworkLogStore()
/// let client = APIClient(
///   baseURL: URL(string: "https://api.example.com")!,
///   interceptors: [BearerTokenInterceptor { await session.accessToken }],
///   authRefresher: { try await session.refreshTokens() },
///   logStore: logs)
/// let user: User = try await client.send(Endpoint(path: "users/42", cachePolicy: .cacheFirst(ttl: 60)))
/// ```
public final class APIClient: Sendable {
  public let baseURL: URL
  private let transport: any HTTPTransport
  private let retryPolicy: RetryPolicy
  private let interceptors: [any RequestInterceptor]
  private let authRefresher: (@Sendable () async throws -> Void)?
  private let logStore: NetworkLogStore?
  private let cache: ResponseCache
  private let deduplicatesRequests: Bool
  private let decoderFactory: @Sendable () -> JSONDecoder
  private let sleep: @Sendable (TimeInterval) async throws -> Void

  private let refreshCoordinator = RefreshCoordinator()
  private let inFlight = InFlightRequests<Endpoint, RawResponse>()

  /// - Parameters:
  ///   - authRefresher: Called when a request fails with 401. Refresh your credentials here (e.g. call
  ///     your token endpoint); the request is then replayed once. Concurrent 401s trigger a single
  ///     refresh. The refresh request itself must use `triggersAuthRefresh: false` (or another client).
  ///   - cache: Backing store for endpoints using a caching ``CachePolicy``.
  ///   - deduplicatesRequests: Share one network call between identical concurrent GET/HEAD requests.
  public init(
    baseURL: URL,
    transport: any HTTPTransport = URLSession.shared,
    retryPolicy: RetryPolicy = .default,
    interceptors: [any RequestInterceptor] = [],
    authRefresher: (@Sendable () async throws -> Void)? = nil,
    logStore: NetworkLogStore? = nil,
    cache: ResponseCache = ResponseCache(),
    deduplicatesRequests: Bool = true,
    decoderFactory: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() },
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
      try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
  ) {
    self.baseURL = baseURL
    self.transport = transport
    self.retryPolicy = retryPolicy
    self.interceptors = interceptors
    self.authRefresher = authRefresher
    self.logStore = logStore
    self.cache = cache
    self.deduplicatesRequests = deduplicatesRequests
    self.decoderFactory = decoderFactory
    self.sleep = sleep
  }

  /// Sends the request and returns the raw body and response of a 2xx answer.
  @discardableResult
  public func send(_ endpoint: Endpoint) async throws -> (data: Data, response: HTTPURLResponse) {
    let isGet = endpoint.method == .get

    if isGet, case .cacheFirst = endpoint.cachePolicy, let hit = await cache.lookup(endpoint) {
      await logCacheHit(endpoint, hit)
      return (hit.data, hit.response)
    }

    let raw: RawResponse
    if deduplicatesRequests && endpoint.method.isSafe {
      raw = try await inFlight.run(key: endpoint) { [self] in try await execute(endpoint) }
    } else {
      raw = try await execute(endpoint)
    }

    if isGet, let ttl = endpoint.cachePolicy.ttl {
      await cache.store(raw, for: endpoint, ttl: ttl)
    }
    return (raw.data, raw.response)
  }

  /// Sends the request and decodes the body as JSON.
  public func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self) async throws -> Response {
    let (data, _) = try await send(endpoint)
    do {
      return try decoderFactory().decode(Response.self, from: data)
    } catch {
      throw NetworkError.decoding(error)
    }
  }

  /// Removes every cached response (call on logout).
  public func clearCache() async { await cache.removeAll() }

  // MARK: - Private

  /// Runs the request with 401 refresh-and-replay and retry/backoff.
  private func execute(_ endpoint: Endpoint) async throws -> RawResponse {
    var attempt = 1
    var hasRefreshed = false

    while true {
      let generation = await refreshCoordinator.currentGeneration()
      do {
        let (data, response) = try await performOnce(endpoint, attempt: attempt)
        return RawResponse(data: data, response: response)
      } catch let error as NetworkError {
        if error.statusCode == 401, endpoint.triggersAuthRefresh, let authRefresher, !hasRefreshed {
          hasRefreshed = true
          do {
            try await refreshCoordinator.refresh(observedGeneration: generation, action: authRefresher)
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            throw NetworkError.tokenRefreshFailed(error)
          }
          continue  // replay; doesn't consume a retry attempt
        }

        guard retryPolicy.shouldRetry(error: error, method: endpoint.method, attempt: attempt) else { throw error }
        try await sleep(retryPolicy.retryDelay(afterAttempt: attempt, error: error))
        attempt += 1
      }
    }
  }

  private func performOnce(_ endpoint: Endpoint, attempt: Int) async throws -> (data: Data, response: HTTPURLResponse) {
    var request = try endpoint.urlRequest(baseURL: baseURL)
    for interceptor in interceptors { request = try await interceptor.adapt(request) }

    let startedAt = Date()
    var data: Data?
    var http: HTTPURLResponse?
    var failure: NetworkError?

    do {
      let (body, response) = try await transport.data(for: request)
      data = body
      guard let httpResponse = response as? HTTPURLResponse else { throw NetworkError.nonHTTPResponse }
      http = httpResponse
      if !(200..<300).contains(httpResponse.statusCode) {
        failure = .httpStatus(code: httpResponse.statusCode, data: body, headers: httpResponse.stringHeaders)
      }
    } catch let error as NetworkError {
      failure = error
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw error
    } catch {
      failure = .transport(error)
    }

    await logStore?.record(
      request: request, response: http, data: data, error: failure, startedAt: startedAt, attempt: attempt)

    if let failure { throw failure }
    return (data ?? Data(), http!)
  }

  private func logCacheHit(_ endpoint: Endpoint, _ hit: RawResponse) async {
    guard let logStore, let request = try? endpoint.urlRequest(baseURL: baseURL) else { return }
    await logStore.record(
      request: request, response: hit.response, data: hit.data, error: nil,
      startedAt: Date(), attempt: 1, fromCache: true)
  }
}
