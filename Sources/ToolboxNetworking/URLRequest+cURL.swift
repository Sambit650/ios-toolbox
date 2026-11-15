//
//  URLRequest+cURL.swift
//  ToolboxNetworking
//

import Foundation

public extension URLRequest {
  /// A copy-pasteable `curl` command for this request.
  /// - Parameter redactedHeaders: Header names (case-insensitive) whose values are replaced with `<redacted>`.
  func curlCommand(redactedHeaders: Set<String> = NetworkLogStore.defaultRedactedHeaders) -> String {
    let redacted = Set(redactedHeaders.map { $0.lowercased() })
    var parts = ["curl"]

    let method = httpMethod ?? "GET"
    if method != "GET" { parts.append("-X \(method)") }

    for (key, value) in (allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
      let shown = redacted.contains(key.lowercased()) ? "<redacted>" : value
      parts.append("-H \(Self.shellQuote("\(key): \(shown)"))")
    }

    if let body = httpBody, !body.isEmpty {
      let text = String(data: body, encoding: .utf8) ?? "<\(body.count) bytes binary>"
      parts.append("-d \(Self.shellQuote(text))")
    }

    parts.append(Self.shellQuote(url?.absoluteString ?? ""))
    return parts.joined(separator: " ")
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
