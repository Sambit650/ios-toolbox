//
//  FlagValue.swift
//  ToolboxFeatureFlags
//

import Foundation

/// The value of a flag: a boolean, integer or string.
public enum FlagValue: Sendable, Equatable, Codable {
  case bool(Bool)
  case int(Int)
  case string(String)

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else {
      throw DecodingError.typeMismatch(
        FlagValue.self,
        .init(codingPath: decoder.codingPath, debugDescription: "Flag values must be Bool, Int or String"))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    }
  }
}

/// Swift types that can be stored as a flag: `Bool`, `Int` and `String`.
public protocol FlagValueConvertible: Sendable {
  init?(flagValue: FlagValue)
  var flagValue: FlagValue { get }
}

extension Bool: FlagValueConvertible {
  public init?(flagValue: FlagValue) {
    guard case .bool(let value) = flagValue else { return nil }
    self = value
  }
  public var flagValue: FlagValue { .bool(self) }
}

extension Int: FlagValueConvertible {
  public init?(flagValue: FlagValue) {
    guard case .int(let value) = flagValue else { return nil }
    self = value
  }
  public var flagValue: FlagValue { .int(self) }
}

extension String: FlagValueConvertible {
  public init?(flagValue: FlagValue) {
    guard case .string(let value) = flagValue else { return nil }
    self = value
  }
  public var flagValue: FlagValue { .string(self) }
}

/// A type-safe flag identifier carrying its fallback value.
///
/// ```swift
/// extension FlagKey where Value == Bool {
///   static let newCheckout = FlagKey("new_checkout", default: false)
/// }
/// ```
public struct FlagKey<Value: FlagValueConvertible>: Sendable {
  public let name: String
  public let defaultValue: Value

  public init(_ name: String, default defaultValue: Value) {
    self.name = name
    self.defaultValue = defaultValue
  }
}
