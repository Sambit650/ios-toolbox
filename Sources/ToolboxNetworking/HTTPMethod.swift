//
//  HTTPMethod.swift
//  ToolboxNetworking
//

import Foundation

/// HTTP request methods.
public enum HTTPMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
  case head = "HEAD"

  /// Safe methods never change server state, so concurrent duplicates can be coalesced.
  public var isSafe: Bool { self == .get || self == .head }

  /// Idempotent methods are safe to retry automatically.
  public var isIdempotent: Bool {
    switch self {
    case .get, .put, .delete, .head: return true
    case .post, .patch: return false
    }
  }
}
