//
//  InFlightRequests.swift
//  ToolboxNetworking
//

import Foundation

/// Coalesces concurrent identical work: the first caller starts it, later callers share the result.
/// The underlying work is cancelled only when *every* waiting caller has been cancelled.
actor InFlightRequests<Key: Hashable & Sendable, Value: Sendable> {
  private struct Entry {
    let id: UUID
    let task: Task<Value, Error>
    var waiters: Int
  }

  private var entries: [Key: Entry] = [:]

  func run(key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
    let id: UUID
    let task: Task<Value, Error>
    if var existing = entries[key] {
      existing.waiters += 1
      entries[key] = existing
      id = existing.id
      task = existing.task
    } else {
      id = UUID()
      task = Task { try await operation() }
      entries[key] = Entry(id: id, task: task, waiters: 1)
    }

    return try await withTaskCancellationHandler {
      do {
        let value = try await task.value
        finish(key, id)
        try Task.checkCancellation()
        return value
      } catch {
        finish(key, id)
        throw error
      }
    } onCancel: {
      Task { await self.cancelWaiter(key, id) }
    }
  }

  private func finish(_ key: Key, _ id: UUID) {
    if entries[key]?.id == id { entries[key] = nil }
  }

  private func cancelWaiter(_ key: Key, _ id: UUID) {
    guard var entry = entries[key], entry.id == id else { return }
    entry.waiters -= 1
    if entry.waiters <= 0 {
      entry.task.cancel()
      entries[key] = nil
    } else {
      entries[key] = entry
    }
  }
}
