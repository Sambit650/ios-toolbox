//
//  FlagContext.swift
//  ToolboxFeatureFlags
//

import Foundation

/// Deployment environment. Used by ``JSONFlagProvider`` to pick per-environment values.
public enum FlagEnvironment: String, Sendable, CaseIterable {
  case development
  case staging
  case production
}

/// User attributes used to evaluate targeting rules (e.g. `isPremium`, `country`).
public struct FlagContext: Sendable, Equatable {
  public var attributes: [String: FlagValue]

  public init(attributes: [String: FlagValue] = [:]) {
    self.attributes = attributes
  }

  public subscript(attribute: String) -> FlagValue? {
    get { attributes[attribute] }
    set { attributes[attribute] = newValue }
  }
}

/// "When `attribute` equals `equals`, the flag resolves to `value`."
public struct FlagRule: Sendable, Equatable, Codable {
  public let attribute: String
  public let equals: FlagValue
  public let value: FlagValue

  public init(attribute: String, equals: FlagValue, value: FlagValue) {
    self.attribute = attribute
    self.equals = equals
    self.value = value
  }

  func matches(_ context: FlagContext) -> Bool {
    context[attribute] == equals
  }
}

/// A flag's base value plus optional targeting rules. The first matching rule wins.
public struct FlagEntry: Sendable, Equatable {
  public let value: FlagValue
  public let rules: [FlagRule]

  public init(value: FlagValue, rules: [FlagRule] = []) {
    self.value = value
    self.rules = rules
  }

  public func resolve(in context: FlagContext) -> FlagValue {
    rules.first(where: { $0.matches(context) })?.value ?? value
  }
}

/// Decodes either a bare value (`true`) or `{ "value": ..., "rules": [...] }`.
extension FlagEntry: Decodable {
  private enum CodingKeys: String, CodingKey { case value, rules }

  public init(from decoder: Decoder) throws {
    if let bare = try? decoder.singleValueContainer().decode(FlagValue.self) {
      self.init(value: bare)
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      value: try container.decode(FlagValue.self, forKey: .value),
      rules: try container.decodeIfPresent([FlagRule].self, forKey: .rules) ?? [])
  }
}
