//
//  NetworkLogFilter.swift
//  ToolboxDebug
//

import Foundation
import ToolboxNetworking

/// Search text plus a status filter for the inspector list.
public struct NetworkLogFilter: Sendable, Equatable {
  public enum Status: String, CaseIterable, Sendable, Identifiable {
    case all = "All"
    case success = "Success"
    case failed = "Failed"
    case cached = "Cached"
    public var id: String { rawValue }
  }

  public var query: String
  public var status: Status

  public init(query: String = "", status: Status = .all) {
    self.query = query
    self.status = status
  }

  public var isActive: Bool { status != .all || !query.trimmingCharacters(in: .whitespaces).isEmpty }

  public func matches(_ entry: NetworkLogEntry) -> Bool {
    switch status {
    case .all: break
    case .success: if !entry.isSuccess { return false }
    case .failed: if entry.isSuccess { return false }
    case .cached: if !entry.fromCache { return false }
    }

    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return true }

    return entry.url.lowercased().contains(needle)
      || entry.method.lowercased() == needle
      || entry.statusText == needle
      || (entry.requestBodyString?.lowercased().contains(needle) ?? false)
      || (entry.responseBodyString?.lowercased().contains(needle) ?? false)
      || (entry.errorDescription?.lowercased().contains(needle) ?? false)
  }

  public func apply(to entries: [NetworkLogEntry]) -> [NetworkLogEntry] {
    isActive ? entries.filter(matches) : entries
  }
}
