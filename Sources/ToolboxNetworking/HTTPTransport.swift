//
//  HTTPTransport.swift
//  ToolboxNetworking
//

import Foundation

/// Abstraction over the thing that actually performs a request.
/// `URLSession` conforms out of the box; use ``MockTransport`` in tests.
public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
  public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await data(for: request, delegate: nil)
  }
}

/// A transport that answers requests from a closure. Ideal for unit tests and SwiftUI previews.
public struct MockTransport: HTTPTransport {
  public typealias Handler = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
  private let handler: Handler

  public init(handler: @escaping Handler) {
    self.handler = handler
  }

  /// Always answers with the given status code and body.
  public static func stub(status: Int = 200, data: Data = Data(), headers: [String: String] = [:]) -> MockTransport {
    MockTransport { request in
      let response = HTTPURLResponse(
        url: request.url ?? URL(string: "https://mock.local")!,
        statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
      return (data, response)
    }
  }

  public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await handler(request)
  }
}
