//
//  FlagProvider.swift
//  ToolboxFeatureFlags
//

import Foundation

/// A source of flag values. Implement this to plug in Firebase Remote Config,
/// LaunchDarkly or a custom backend. `value(for:context:)` must be fast and synchronous;
/// do network fetching in the background and call ``FeatureFlags/reload()`` when new
/// values arrive.
public protocol FlagProvider: Sendable {
  /// The flag's value for `context`, or `nil` if this provider doesn't know the flag.
  func value(for name: String, context: FlagContext) -> FlagValue?
}

/// Thread-safe in-memory provider. Handy for bundled defaults, tests and overrides.
public final class MemoryFlagProvider: FlagProvider, @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: FlagEntry]

  public init(_ entries: [String: FlagEntry] = [:]) {
    self.entries = entries
  }

  public convenience init(values: [String: FlagValue]) {
    self.init(values.mapValues { FlagEntry(value: $0) })
  }

  public func set(_ entry: FlagEntry, for name: String) {
    lock.lock(); defer { lock.unlock() }
    entries[name] = entry
  }

  public func set(_ value: FlagValue, for name: String) {
    set(FlagEntry(value: value), for: name)
  }

  public func remove(_ name: String) {
    lock.lock(); defer { lock.unlock() }
    entries[name] = nil
  }

  public func removeAll() {
    lock.lock(); defer { lock.unlock() }
    entries.removeAll()
  }

  public func value(for name: String, context: FlagContext) -> FlagValue? {
    lock.lock(); defer { lock.unlock() }
    return entries[name]?.resolve(in: context)
  }
}

/// Persists plain (rule-less) flag values in `UserDefaults`. Useful for locally toggled
/// flags that should survive relaunches, such as debug overrides.
public final class UserDefaultsFlagProvider: FlagProvider, @unchecked Sendable {
  private let defaults: UserDefaults
  private let prefix: String

  public init(defaults: UserDefaults = .standard, prefix: String = "toolbox.flag.") {
    self.defaults = defaults
    self.prefix = prefix
  }

  public func set(_ value: FlagValue, for name: String) {
    switch value {
    case .bool(let value): defaults.set(value, forKey: prefix + name)
    case .int(let value): defaults.set(value, forKey: prefix + name)
    case .string(let value): defaults.set(value, forKey: prefix + name)
    }
  }

  public func remove(_ name: String) {
    defaults.removeObject(forKey: prefix + name)
  }

  public func value(for name: String, context: FlagContext) -> FlagValue? {
    switch defaults.object(forKey: prefix + name) {
    case let string as String:
      return .string(string)
    case let number as NSNumber:
      // NSNumber bridges Bool and Int; tell them apart by CF type.
      return CFGetTypeID(number) == CFBooleanGetTypeID()
        ? .bool(number.boolValue) : .int(number.intValue)
    default:
      return nil
    }
  }
}

/// Reads flags from JSON, either bundled or fetched from your backend.
///
/// ```json
/// {
///   "default":    { "new_checkout": false, "max_items": 10 },
///   "staging":    { "new_checkout": true },
///   "production": { "premium_banner": { "value": false,
///                     "rules": [{ "attribute": "isPremium", "equals": true, "value": true }] } }
/// }
/// ```
/// Values in the section matching `environment` override those in `"default"`.
public struct JSONFlagProvider: FlagProvider {
  private let entries: [String: FlagEntry]

  public init(data: Data, environment: FlagEnvironment = .production) throws {
    self.entries = try Self.parse(data, environment: environment)
  }

  /// Decodes flag JSON and merges the `environment` section over `"default"`.
  static func parse(_ data: Data, environment: FlagEnvironment) throws -> [String: FlagEntry] {
    let sections = try JSONDecoder().decode([String: [String: FlagEntry]].self, from: data)
    var merged = sections["default"] ?? [:]
    for (name, entry) in sections[environment.rawValue] ?? [:] { merged[name] = entry }
    return merged
  }

  public init(fileURL: URL, environment: FlagEnvironment = .production) throws {
    try self.init(data: Data(contentsOf: fileURL), environment: environment)
  }

  public func value(for name: String, context: FlagContext) -> FlagValue? {
    entries[name]?.resolve(in: context)
  }
}
