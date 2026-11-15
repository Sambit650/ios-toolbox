//
//  BodyFormatter.swift
//  ToolboxDebug
//

import Foundation

/// Turns raw request/response bytes into something readable.
public enum BodyFormatter {
  /// Pretty-printed JSON when possible, otherwise UTF-8 text, otherwise a byte-count placeholder.
  /// Returns `nil` for missing or empty bodies.
  public static func format(_ data: Data?) -> String? {
    guard let data, !data.isEmpty else { return nil }

    if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
      JSONSerialization.isValidJSONObject(object),
      let pretty = try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
      let text = String(data: pretty, encoding: .utf8)
    {
      return text
    }

    if let text = String(data: data, encoding: .utf8) { return text }
    return "<\(data.count) bytes of binary data>"
  }
}
