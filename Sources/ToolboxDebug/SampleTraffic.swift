//
//  SampleTraffic.swift
//  ToolboxDebug
//

import Foundation
import ToolboxNetworking

public extension NetworkLogStore {
  /// A store pre-filled with realistic fake traffic: handy for SwiftUI previews, demos and screenshots.
  static func sample() async -> NetworkLogStore {
    let store = NetworkLogStore()
    let transport = MockTransport { request in
      let path = request.url?.path ?? ""
      func reply(_ status: Int, _ json: String, _ headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        var headers = headers
        headers["Content-Type"] = "application/json"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(json.utf8), response)
      }
      try await Task.sleep(nanoseconds: UInt64.random(in: 5...60) * 1_000_000)
      switch path {
      case "/v1/users": return reply(200, #"{"users":[{"id":1,"name":"Ada"},{"id":2,"name":"Linus"}],"page":1}"#)
      case "/v1/login": return reply(200, #"{"token":"abc123","expiresIn":3600}"#)
      case "/v1/orders": return reply(503, #"{"error":"Service temporarily unavailable"}"#, ["Retry-After": "1"])
      case "/v1/missing": return reply(404, #"{"error":"Not found"}"#)
      default: throw URLError(.notConnectedToInternet)
      }
    }

    let client = APIClient(
      baseURL: URL(string: "https://api.example.com")!,
      transport: transport,
      retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 0.01, usesJitter: false),
      interceptors: [BearerTokenInterceptor { "sample-secret-token" }],
      logStore: store)

    let cached = Endpoint(path: "v1/users", queryItems: [URLQueryItem(name: "page", value: "1")], cachePolicy: .cacheFirst(ttl: 60))
    _ = try? await client.send(cached)
    _ = try? await client.send(cached)  // served from cache
    _ = try? await client.send(Endpoint.json(path: "v1/login", body: ["email": "ada@example.com", "password": "hunter2"]))
    _ = try? await client.send(Endpoint(path: "v1/orders"))  // 503 -> retried
    _ = try? await client.send(Endpoint(path: "v1/missing"))
    _ = try? await client.send(Endpoint(path: "v1/offline"))  // transport error
    return store
  }
}
