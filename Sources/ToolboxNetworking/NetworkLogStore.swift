//
//  NetworkLogStore.swift
//  ToolboxNetworking
//

import Foundation

/// A recorded request/response pair (or failure).
public struct NetworkLogEntry: Sendable, Identifiable {
  public let id: UUID
  public let startedAt: Date
  public let duration: TimeInterval
  /// 1-based attempt number (greater than 1 means this was a retry).
  public let attempt: Int

  public let method: String
  public let url: String
  public let requestHeaders: [String: String]
  public let requestBody: Data?
  public let curl: String

  public let statusCode: Int?
  public let responseHeaders: [String: String]
  public let responseBody: Data?
  public let errorDescription: String?
  /// `true` when the response was served from ``ResponseCache`` without touching the network.
  public let fromCache: Bool

  public var isSuccess: Bool {
    guard errorDescription == nil, let statusCode else { return false }
    return (200..<300).contains(statusCode)
  }

  public var requestBodyString: String? { requestBody.flatMap { String(data: $0, encoding: .utf8) } }
  public var responseBodyString: String? { responseBody.flatMap { String(data: $0, encoding: .utf8) } }
}

/// Thread-safe, bounded in-memory log of network traffic. Share one instance between
/// an ``APIClient`` and any UI that wants to display it.
public actor NetworkLogStore {
  public static let defaultRedactedHeaders: Set<String> = ["Authorization", "Cookie", "Set-Cookie", "Proxy-Authorization"]

  public nonisolated let capacity: Int
  public nonisolated let maxBodyBytes: Int
  public nonisolated let redactedHeaders: Set<String>

  private var storage: [NetworkLogEntry] = []
  private var subscribers: [UUID: AsyncStream<NetworkLogEntry>.Continuation] = [:]

  public init(
    capacity: Int = 200,
    maxBodyBytes: Int = 64 * 1024,
    redactedHeaders: Set<String> = NetworkLogStore.defaultRedactedHeaders
  ) {
    self.capacity = max(1, capacity)
    self.maxBodyBytes = maxBodyBytes
    self.redactedHeaders = redactedHeaders
  }

  /// Entries, oldest first.
  public var entries: [NetworkLogEntry] { storage }

  public func clear() { storage.removeAll() }

  /// Emits every entry recorded after this call.
  public func updates() -> AsyncStream<NetworkLogEntry> {
    let id = UUID()
    var continuation: AsyncStream<NetworkLogEntry>.Continuation!
    let stream = AsyncStream<NetworkLogEntry> { continuation = $0 }
    subscribers[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(id) }
    }
    return stream
  }

  func record(
    request: URLRequest,
    response: HTTPURLResponse?,
    data: Data?,
    error: Error?,
    startedAt: Date,
    attempt: Int,
    fromCache: Bool = false
  ) {
    let entry = NetworkLogEntry(
      id: UUID(),
      startedAt: startedAt,
      duration: Date().timeIntervalSince(startedAt),
      attempt: attempt,
      method: request.httpMethod ?? "GET",
      url: request.url?.absoluteString ?? "",
      requestHeaders: redact(request.allHTTPHeaderFields ?? [:]),
      requestBody: truncate(request.httpBody),
      curl: request.curlCommand(redactedHeaders: redactedHeaders),
      statusCode: response?.statusCode,
      responseHeaders: redact(response?.stringHeaders ?? [:]),
      responseBody: truncate(data),
      errorDescription: error?.localizedDescription,
      fromCache: fromCache)

    storage.append(entry)
    if storage.count > capacity { storage.removeFirst(storage.count - capacity) }
    for continuation in subscribers.values { continuation.yield(entry) }
  }

  private func removeSubscriber(_ id: UUID) { subscribers[id] = nil }

  private func truncate(_ data: Data?) -> Data? {
    guard let data else { return nil }
    return data.count > maxBodyBytes ? data.prefix(maxBodyBytes) : data
  }

  private func redact(_ headers: [String: String]) -> [String: String] {
    let lowered = Set(redactedHeaders.map { $0.lowercased() })
    return headers.reduce(into: [:]) { result, pair in
      result[pair.key] = lowered.contains(pair.key.lowercased()) ? "<redacted>" : pair.value
    }
  }

}
