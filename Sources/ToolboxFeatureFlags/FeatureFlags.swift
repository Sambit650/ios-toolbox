//
//  FeatureFlags.swift
//  ToolboxFeatureFlags
//

import Combine
import Foundation

/// Resolves flags from layered providers.
///
/// Resolution order: runtime overrides, then `providers` in the order given (put a
/// remote provider before your bundled defaults). The first provider that returns a
/// value of the right type wins; otherwise the key's `defaultValue` is used.
public final class FeatureFlags: ObservableObject, @unchecked Sendable {
  public let environment: FlagEnvironment

  private let lock = NSLock()
  private let overrides = MemoryFlagProvider()
  private let providers: [FlagProvider]
  private var _context: FlagContext
  private let changes = PassthroughSubject<Void, Never>()

  public init(
    providers: [FlagProvider],
    environment: FlagEnvironment = .production,
    context: FlagContext = FlagContext()
  ) {
    self.providers = providers
    self.environment = environment
    self._context = context
  }

  /// User attributes for targeting rules. Setting it re-evaluates every flag.
  public var context: FlagContext {
    get { lock.lock(); defer { lock.unlock() }; return _context }
    set {
      lock.lock(); _context = newValue; lock.unlock()
      notifyChange()
    }
  }

  public func value<Value: FlagValueConvertible>(for key: FlagKey<Value>) -> Value {
    let context = self.context
    for provider in [overrides] + providers {
      if let raw = provider.value(for: key.name, context: context),
        let typed = Value(flagValue: raw) {
        return typed
      }
    }
    return key.defaultValue
  }

  public subscript<Value: FlagValueConvertible>(key: FlagKey<Value>) -> Value {
    value(for: key)
  }

  // MARK: Overrides (e.g. from a debug menu)

  public func setOverride<Value: FlagValueConvertible>(_ value: Value, for key: FlagKey<Value>) {
    overrides.set(value.flagValue, for: key.name)
    notifyChange()
  }

  public func removeOverride<Value>(for key: FlagKey<Value>) {
    overrides.remove(key.name)
    notifyChange()
  }

  public func removeAllOverrides() {
    overrides.removeAll()
    notifyChange()
  }

  // MARK: Change notification

  /// Call after a provider's underlying data changed (e.g. a remote fetch finished).
  public func reload() {
    notifyChange()
  }

  /// Refreshes `remote` and notifies observers if its values changed.
  public func refresh(_ remote: RemoteFlagProvider, force: Bool = false) async {
    if await remote.refresh(force: force) { reload() }
  }

  /// Emits the flag's current value immediately, then again whenever it changes.
  /// Use from UIKit: `flags.publisher(for: .newCheckout).sink { ... }`.
  public func publisher<Value: FlagValueConvertible & Equatable>(
    for key: FlagKey<Value>
  ) -> AnyPublisher<Value, Never> {
    changes
      .prepend(())
      .map { [unowned self] in self.value(for: key) }
      .removeDuplicates()
      .eraseToAnyPublisher()
  }

  private func notifyChange() {
    let send = { [self] in
      objectWillChange.send()
      changes.send()
    }
    if Thread.isMainThread { send() } else { DispatchQueue.main.async(execute: send) }
  }
}
