//
//  RequestInterceptor.swift
//  ToolboxNetworking
//

import Foundation

/// Mutates every outgoing request just before it is sent (auth headers, signing, ...).
/// Called again on every retry, so refreshed tokens are picked up.
public protocol RequestInterceptor: Sendable {
  func adapt(_ request: URLRequest) async throws -> URLRequest
}

/// Adds an `Authorization: Bearer <token>` header using a (possibly async) token provider.
public struct BearerTokenInterceptor: RequestInterceptor {
  private let tokenProvider: @Sendable () async throws -> String?

  public init(tokenProvider: @escaping @Sendable () async throws -> String?) {
    self.tokenProvider = tokenProvider
  }

  public func adapt(_ request: URLRequest) async throws -> URLRequest {
    guard let token = try await tokenProvider() else { return request }
    var request = request
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }
}

/// Adds fixed headers (e.g. `User-Agent`, `Accept-Language`) to every request.
public struct StaticHeadersInterceptor: RequestInterceptor {
  private let headers: [String: String]

  public init(_ headers: [String: String]) {
    self.headers = headers
  }

  public func adapt(_ request: URLRequest) async throws -> URLRequest {
    var request = request
    for (key, value) in headers where request.value(forHTTPHeaderField: key) == nil {
      request.setValue(value, forHTTPHeaderField: key)
    }
    return request
  }
}
