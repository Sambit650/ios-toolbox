//
//  NetworkInspectorViewModel.swift
//  ToolboxDebug
//

import Foundation
import ToolboxNetworking

/// Mirrors a ``NetworkLogStore`` for SwiftUI and keeps itself up to date while ``start()`` runs.
@MainActor
public final class NetworkInspectorViewModel: ObservableObject {
  @Published public private(set) var entries: [NetworkLogEntry] = []
  @Published public var filter = NetworkLogFilter()

  private let store: NetworkLogStore

  public init(store: NetworkLogStore) {
    self.store = store
  }

  /// Entries matching the current filter, newest first.
  public var visibleEntries: [NetworkLogEntry] {
    filter.apply(to: entries).reversed()
  }

  /// Loads existing entries, then live-updates until the surrounding task is cancelled.
  public func start() async {
    // Subscribe before taking the snapshot so nothing recorded in between is lost.
    let stream = await store.updates()
    entries = await store.entries
    let capacity = store.capacity

    for await entry in stream {
      if entries.contains(where: { $0.id == entry.id }) { continue }  // seen in the snapshot too
      entries.append(entry)
      if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }
  }

  public func clear() async {
    await store.clear()
    entries = []
  }
}
