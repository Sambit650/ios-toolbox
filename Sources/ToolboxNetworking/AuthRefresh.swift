//
//  AuthRefresh.swift
//  ToolboxNetworking
//

import Foundation

/// Makes sure that when many requests hit a 401 at once, credentials are refreshed only once.
///
/// Every request records the "generation" it was sent with. A request that fails with 401
/// only triggers a refresh if no refresh has completed since it was sent; otherwise it simply
/// replays with the already-refreshed credentials.
actor RefreshCoordinator {
  private var generation = 0
  private var inFlight: Task<Void, Error>?

  func currentGeneration() -> Int { generation }

  func refresh(observedGeneration: Int, action: @escaping @Sendable () async throws -> Void) async throws {
    // A refresh already completed after this request was sent: just replay.
    if observedGeneration != generation { return }
    // A refresh is running: wait for it instead of starting another.
    if let inFlight {
      try await inFlight.value
      return
    }

    let task = Task { try await action() }
    inFlight = task
    do {
      try await task.value
      generation += 1
      inFlight = nil
    } catch {
      inFlight = nil
      throw error
    }
  }
}
