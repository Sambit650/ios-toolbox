//
//  NetworkLogEntry+Display.swift
//  ToolboxDebug
//

import Foundation
import ToolboxNetworking

/// Coarse classification used to colour rows and filter the list.
public enum StatusCategory: Sendable, Equatable {
  case success       // 2xx
  case redirect      // 3xx
  case clientError   // 4xx
  case serverError   // 5xx
  case failure       // no HTTP response (offline, timeout, decoding...)

  public init(statusCode: Int?) {
    switch statusCode {
    case .some(200..<300): self = .success
    case .some(300..<400): self = .redirect
    case .some(400..<500): self = .clientError
    case .some(500..<600): self = .serverError
    default: self = .failure
    }
  }
}

public extension NetworkLogEntry {
  var category: StatusCategory { StatusCategory(statusCode: statusCode) }

  /// Path plus query, e.g. `/v1/users?page=2`.
  var displayPath: String {
    guard let components = URLComponents(string: url) else { return url }
    var path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    if let query = components.percentEncodedQuery { path += "?" + query }
    return path
  }

  var host: String { URLComponents(string: url)?.host ?? "" }

  /// `"200"`, or `"ERR"` when there was no HTTP response.
  var statusText: String { statusCode.map(String.init) ?? "ERR" }

  /// `"142 ms"` or `"1.20 s"`.
  var durationText: String {
    duration < 1 ? "\(Int((duration * 1000).rounded())) ms" : String(format: "%.2f s", duration)
  }

  /// A complete, shareable plain-text report of this exchange.
  var exportText: String {
    var lines: [String] = []
    lines.append("\(method) \(url)")
    lines.append("Status: \(statusText)\(fromCache ? " (cache)" : "")  Duration: \(durationText)  Attempt: \(attempt)")
    if let errorDescription { lines.append("Error: \(errorDescription)") }

    lines.append("")
    lines.append("--- Request headers ---")
    lines.append(contentsOf: Self.format(headers: requestHeaders))
    if let body = BodyFormatter.format(requestBody) {
      lines.append("--- Request body ---")
      lines.append(body)
    }

    lines.append("")
    lines.append("--- Response headers ---")
    lines.append(contentsOf: Self.format(headers: responseHeaders))
    if let body = BodyFormatter.format(responseBody) {
      lines.append("--- Response body ---")
      lines.append(body)
    }

    lines.append("")
    lines.append("--- cURL ---")
    lines.append(curl)
    return lines.joined(separator: "\n")
  }

  private static func format(headers: [String: String]) -> [String] {
    headers.isEmpty ? ["(none)"] : headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
  }
}
