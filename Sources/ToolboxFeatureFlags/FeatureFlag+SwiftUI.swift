//
//  FeatureFlag+SwiftUI.swift
//  ToolboxFeatureFlags
//

#if canImport(SwiftUI)
import SwiftUI

/// Reads a flag in a SwiftUI view and refreshes the view when it changes.
///
/// ```swift
/// struct CheckoutView: View {
///   @FeatureFlag(.newCheckout, flags: appFlags) var useNewCheckout
///   var body: some View { useNewCheckout ? NewCheckout() : OldCheckout() }
/// }
/// ```
@propertyWrapper
public struct FeatureFlag<Value: FlagValueConvertible>: DynamicProperty {
  @ObservedObject private var flags: FeatureFlags
  private let key: FlagKey<Value>

  public init(_ key: FlagKey<Value>, flags: FeatureFlags) {
    self.key = key
    self.flags = flags
  }

  public var wrappedValue: Value { flags.value(for: key) }
}
#endif
