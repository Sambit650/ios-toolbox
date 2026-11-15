//
//  RemoteFlagProvider.swift
//  ToolboxFeatureFlags
//

import Foundation
import ToolboxNetworking

/// Serves flags fetched from your backend, using the JSON format of ``JSONFlagProvider``.
///
/// Reads are synchronous and come from memory. The last good response is cached on disk
/// and loaded at init, so flags work offline and immediately at launch. A failed or invalid
/// fetch never discards the values you already have.
///
/// ```swift
/// let remote = RemoteFlagProvider(client: apiClient, endpoint: Endpoint(path: "flags"),
///                                 environment: .staging, refreshInterval: 15 * 60)
/// let flags = FeatureFlags(providers: [remote, bundled])
/// await flags.refresh(remote)   // e.g. at launch and when the app becomes active
/// ```
public final class RemoteFlagProvider: FlagProvider, @unchecked Sendable {
  public typealias Fetch = @Sendable () async throws -> Data

  private let fetch: Fetch
  private let environment: FlagEnvironment
  private let cacheURL: URL?
  private let refreshInterval: TimeInterval
  private let now: @Sendable () -> Date

  private let lock = NSLock()
  private var entries: [String: FlagEntry] = [:]
  private var lastRefresh: Date?
  private var isRefreshing = false

  /// - Parameters:
  ///   - fetch: Returns the raw JSON. Use the `APIClient` convenience init for the common case.
  ///   - cacheURL: Where to persist the last good response; `nil` disables the disk cache.
  ///   - refreshInterval: Minimum seconds between non-forced refreshes.
  public init(
    fetch: @escaping Fetch,
    environment: FlagEnvironment = .production,
    cacheURL: URL? = RemoteFlagProvider.defaultCacheURL(for: .production),
    refreshInterval: TimeInterval = 15 * 60,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.fetch = fetch
    self.environment = environment
    self.cacheURL = cacheURL
    self.refreshInterval = refreshInterval
    self.now = now
    if let cacheURL, let data = try? Data(contentsOf: cacheURL),
      let cached = try? JSONFlagProvider.parse(data, environment: environment) {
      entries = cached
    }
  }

  /// Fetches `endpoint` through `client`.
  public convenience init(
    client: APIClient,
    endpoint: Endpoint,
    environment: FlagEnvironment = .production,
    cacheURL: URL? = nil,
    refreshInterval: TimeInterval = 15 * 60,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.init(
      fetch: { try await client.send(endpoint).data },
      environment: environment,
      cacheURL: cacheURL ?? Self.defaultCacheURL(for: environment),
      refreshInterval: refreshInterval,
      now: now)
  }

  /// `Caches/ToolboxFeatureFlags/flags-<environment>.json`
  public static func defaultCacheURL(for environment: FlagEnvironment) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("ToolboxFeatureFlags", isDirectory: true)
      .appendingPathComponent("flags-\(environment.rawValue).json")
  }

  public func value(for name: String, context: FlagContext) -> FlagValue? {
    lock.lock(); defer { lock.unlock() }
    return entries[name]?.resolve(in: context)
  }

  /// Fetches new values. Returns `true` if they differ from the current ones.
  ///
  /// Does nothing (returns `false`) when called within `refreshInterval` of the last
  /// successful refresh unless `force` is set, or when a refresh is already running.
  /// On any failure the existing values are kept.
  @discardableResult
  public func refresh(force: Bool = false) async -> Bool {
    guard beginRefresh(force: force) else { return false }
    defer { endRefresh() }

    guard let data = try? await fetch(),
      let fresh = try? JSONFlagProvider.parse(data, environment: environment)
    else { return false }

    let changed = apply(fresh)
    persist(data)
    return changed
  }

  // Lock-protected state transitions live in synchronous helpers (NSLock must not be
  // held across, or called from, async contexts).

  private func beginRefresh(force: Bool) -> Bool {
    lock.lock(); defer { lock.unlock() }
    if isRefreshing { return false }
    if !force, let lastRefresh, now().timeIntervalSince(lastRefresh) < refreshInterval { return false }
    isRefreshing = true
    return true
  }

  private func endRefresh() {
    lock.lock(); defer { lock.unlock() }
    isRefreshing = false
  }

  private func apply(_ fresh: [String: FlagEntry]) -> Bool {
    lock.lock(); defer { lock.unlock() }
    let changed = fresh != entries
    entries = fresh
    lastRefresh = now()
    return changed
  }

  private func persist(_ data: Data) {
    guard let cacheURL else { return }
    try? FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: cacheURL, options: .atomic)
  }
}
