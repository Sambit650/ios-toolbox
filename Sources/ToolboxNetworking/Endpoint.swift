//
//  Endpoint.swift
//  ToolboxNetworking
//

import Foundation

/// Describes a single request relative to an ``APIClient``'s base URL.
public struct Endpoint: Sendable, Hashable {
  public var path: String
  public var method: HTTPMethod
  public var queryItems: [URLQueryItem]
  public var headers: [String: String]
  public var body: Data?
  public var timeout: TimeInterval?
  /// Response caching behaviour (GET only). Defaults to always hitting the network.
  public var cachePolicy: CachePolicy
  /// Set to `false` for the request that refreshes credentials, so a 401 from it cannot recurse.
  public var triggersAuthRefresh: Bool

  public init(
    path: String,
    method: HTTPMethod = .get,
    queryItems: [URLQueryItem] = [],
    headers: [String: String] = [:],
    body: Data? = nil,
    timeout: TimeInterval? = nil,
    cachePolicy: CachePolicy = .networkOnly,
    triggersAuthRefresh: Bool = true
  ) {
    self.path = path
    self.method = method
    self.queryItems = queryItems
    self.headers = headers
    self.body = body
    self.timeout = timeout
    self.cachePolicy = cachePolicy
    self.triggersAuthRefresh = triggersAuthRefresh
  }

  // Identity is "what is requested": timeout, cache policy and refresh flag don't change it,
  // so they don't affect cache keys or request de-duplication.
  public static func == (lhs: Endpoint, rhs: Endpoint) -> Bool {
    lhs.path == rhs.path && lhs.method == rhs.method && lhs.queryItems == rhs.queryItems
      && lhs.headers == rhs.headers && lhs.body == rhs.body
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(path)
    hasher.combine(method)
    hasher.combine(queryItems)
    hasher.combine(headers)
    hasher.combine(body)
  }

  /// Creates an endpoint with a JSON-encoded body and the matching `Content-Type` header.
  public static func json<Body: Encodable>(
    path: String,
    method: HTTPMethod = .post,
    body: Body,
    queryItems: [URLQueryItem] = [],
    headers: [String: String] = [:],
    encoder: JSONEncoder = JSONEncoder()
  ) throws -> Endpoint {
    var headers = headers
    headers["Content-Type"] = "application/json"
    do {
      return Endpoint(
        path: path, method: method, queryItems: queryItems,
        headers: headers, body: try encoder.encode(body))
    } catch {
      throw NetworkError.encoding(error)
    }
  }

  /// Builds the final `URLRequest` against a base URL.
  func urlRequest(baseURL: URL) throws -> URLRequest {
    let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let url = trimmed.isEmpty ? baseURL : baseURL.appendingPathComponent(trimmed)
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw NetworkError.invalidURL
    }
    if !queryItems.isEmpty {
      components.queryItems = (components.queryItems ?? []) + queryItems
    }
    guard let finalURL = components.url else { throw NetworkError.invalidURL }

    var request = URLRequest(url: finalURL)
    request.httpMethod = method.rawValue
    request.httpBody = body
    if let timeout { request.timeoutInterval = timeout }
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    return request
  }
}
