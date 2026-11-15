//
//  ResponseCache.swift
//  ToolboxNetworking
//

import Foundation

/// Per-endpoint caching behaviour for GET requests.
public enum CachePolicy: Sendable, Equatable {
  /// Always go to the network and don't store the result. (Default.)
  case networkOnly
  /// Serve a stored response if it is younger than `ttl` seconds, otherwise fetch and store it.
  case cacheFirst(ttl: TimeInterval)
  /// Always go to the network, but store the result for `ttl` seconds (pull-to-refresh).
  case refresh(ttl: TimeInterval)

  var ttl: TimeInterval? {
    switch self {
    case .networkOnly: return nil
    case let .cacheFirst(ttl), let .refresh(ttl): return ttl
    }
  }
}

/// A successful response body plus its HTTP metadata.
struct RawResponse: @unchecked Sendable {
  let data: Data
  let response: HTTPURLResponse
}

/// In-memory, bounded (least-recently-used) response cache with per-entry TTL.
///
/// The cache key is the endpoint (method, path, query, headers, body). Authentication headers are
/// added by interceptors *after* the key is built, so call ``removeAll()`` when the user logs out.
public actor ResponseCache {
  private struct Stored {
    let response: RawResponse
    let expiresAt: Date
  }

  public let capacity: Int
  private let clock: @Sendable () -> Date
  private var storage: [Endpoint: Stored] = [:]
  private var recency: [Endpoint] = []  // least recently used first

  public init(capacity: Int = 100, clock: @escaping @Sendable () -> Date = { Date() }) {
    self.capacity = max(1, capacity)
    self.clock = clock
  }

  public var count: Int { storage.count }

  public func removeAll() {
    storage.removeAll()
    recency.removeAll()
  }

  /// Drops the cached response for a single endpoint.
  public func invalidate(_ endpoint: Endpoint) {
    storage[endpoint] = nil
    recency.removeAll { $0 == endpoint }
  }

  func lookup(_ endpoint: Endpoint) -> RawResponse? {
    guard let stored = storage[endpoint] else { return nil }
    guard stored.expiresAt > clock() else {
      invalidate(endpoint)
      return nil
    }
    touch(endpoint)
    return stored.response
  }

  func store(_ response: RawResponse, for endpoint: Endpoint, ttl: TimeInterval) {
    guard ttl > 0, !Self.forbidsStorage(response.response) else { return }
    storage[endpoint] = Stored(response: response, expiresAt: clock().addingTimeInterval(ttl))
    touch(endpoint)
    while recency.count > capacity {
      storage[recency.removeFirst()] = nil
    }
  }

  private func touch(_ endpoint: Endpoint) {
    recency.removeAll { $0 == endpoint }
    recency.append(endpoint)
  }

  private static func forbidsStorage(_ response: HTTPURLResponse) -> Bool {
    let control = response.stringHeaders.first { $0.key.caseInsensitiveCompare("Cache-Control") == .orderedSame }?.value
    return control?.lowercased().contains("no-store") ?? false
  }
}
